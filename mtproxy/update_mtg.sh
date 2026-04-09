#!/usr/bin/env bash
# vim: set sw=4 sts=4 et tw=80 :

#
# Program: Update MTG Telegram MTProto Proxy <update_mtg.sh>
#
# Author: Mikhail Grigorev <sleuthhound at gmail dot com>
#
# Current Version: 1.1
#
# Revision History:
#
#  Version 1.0
#    Initial Release
#
# License:
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

# Don't change this settings
PROGRAM_NAME="mtg"
CONF_DIR="/etc/${PROGRAM_NAME}"
DATA_DIR="/var/lib/${PROGRAM_NAME}"
DEFAULT_DIR="/etc/default"
SYSTEMD_DIR="/etc/systemd/system"

# Don't edit this config
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
	DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
	SOURCE="$(readlink "$SOURCE")"
	[[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
SCRIPT_NAME=$(basename "$0")

# Check command exist function
_command_exists() {
	type "$1" &>/dev/null
}

case "$(uname -m)" in
x86_64 | x64 | amd64) ARCH="amd64" ;;
i*86 | x86) ARCH="386" ;;
armv8* | armv8 | arm64 | aarch64) ARCH="arm64" ;;
armv7* | armv7 | arm) ARCH="armv7" ;;
armv6* | armv6) ARCH="armv6" ;;
mips*) ARCH="mips" ;;
*) echo "ERROR: Unsupported CPU architecture!" && exit 1 ;;
esac

# Detect jq
if _command_exists jq; then
	JQ_BIN=$(which jq)
else
	echo "ERROR: jq binary not found."
	exit 1
fi

# Detect netstat
if _command_exists netstat; then
	NETSTAT_BIN=$(which netstat)
else
	echo "ERROR: netstat binary not found."
	exit 1
fi

# Detect curl
if _command_exists curl; then
	CURL_BIN=$(which curl)
else
	echo "ERROR: curl binary not found."
	exit 1
fi

# Detect wget
if _command_exists wget; then
	WGET_BIN=$(which wget)
else
	echo "ERROR: wget binary not found."
	exit 1
fi

# Detect tar
if _command_exists tar; then
	TAR_BIN=$(which tar)
else
	echo "ERROR: tar binary not found."
	exit 1
fi

# Detect systemctl
if _command_exists systemctl; then
	SYSTEMCTL_BIN=$(which systemctl)
else
	echo "ERROR: systemctl binary not found."
	exit 1
fi

# Detect pgrep
if _command_exists pgrep; then
	PGREP_BIN=$(which pgrep)
	PROCESS_RUN=$(${PGREP_BIN} -x "${PROGRAM_NAME}" 2>/dev/null | wc -l)
else
	PROCESS_RUN=$(ps -ef 2>/dev/null | grep [m]tg -c)
fi

if [ ${PROCESS_RUN} -ne 0 ]; then
	echo "WARNING: MTG is already running."
fi

if [ ! -f "${CONF_DIR}/.installed" ]; then
	echo "ERROR: MTG was installed by another script or in another way and cannot be reinstalled by this script."
	exit 1
fi

OS_NAME=$(uname -s)
echo "OS: ${OS_NAME}"
if [ -f "/etc/os-release" ]; then
	. "/etc/os-release"
	OS=$NAME
	VER=$VERSION_ID
	echo "Distro: ${OS}"
	echo "Version: ${VER}"
elif type lsb_release >/dev/null 2>&1; then
	OS=$(lsb_release -si)
	VER=$(lsb_release -sr)
	echo "Distro: ${OS}"
	echo "Version: ${VER}"
elif [ -f "/etc/lsb-release" ]; then
	. "/etc/lsb-release"
	OS=$DISTRIB_ID
	VER=$DISTRIB_RELEASE
	echo "Distro: ${OS}"
	echo "Version: ${VER}"
elif [ -f "/etc/debian_version" ]; then
	OS=Debian
	VER=$(cat "/etc/debian_version")
	echo "Distro: ${OS}"
	echo "Version: ${VER}"
else
	echo "Distro: Unknown"
	echo "Version: Unknown"
fi
echo "Arch: ${ARCH}"

echo -n "Checking your privileges... "
CURRENT_USER=$(whoami)
if [[ "${CURRENT_USER}" = "root" ]]; then
	echo "OK"
else
	echo "ERROR: root access is required"
	exit 1
fi

LATEST_VER=$(${CURL_BIN} -Ls "https://api.github.com/repos/9seconds/${PROGRAM_NAME}/releases/latest" 2>/dev/null | ${JQ_BIN} -r .tag_name | sed 's/[^0-9.]//g')
if [ -n "${LATEST_VER}" ]; then
	OS_NAME=$(uname -s | tr '[:upper:]' '[:lower:]')
	echo "Latest MTG version: ${LATEST_VER}"
	echo "Downloading latest version..."
	${WGET_BIN} https://github.com/9seconds/${PROGRAM_NAME}/releases/download/v${LATEST_VER}/${PROGRAM_NAME}-${LATEST_VER}-${OS_NAME}-${ARCH}.tar.gz -O "${SCRIPT_DIR}/${PROGRAM_NAME}.tar.gz" >/dev/null 2>&1
	if [ -f "${SCRIPT_DIR}/${PROGRAM_NAME}.tar.gz" ]; then
		echo "Done"
		echo "Extract mtg.tar.gz..."
		${TAR_BIN} -zxf "${SCRIPT_DIR}/${PROGRAM_NAME}.tar.gz" >/dev/null 2>&1
		if [ -f "${SCRIPT_DIR}/${PROGRAM_NAME}-${LATEST_VER}-${OS_NAME}-${ARCH}/${PROGRAM_NAME}" ]; then
			echo "Stoping old MTG..."
			${SYSTEMCTL_BIN} stop ${PROGRAM_NAME} >/dev/null 2>&1
			echo "Install new binary..."
			yes | cp ${PROGRAM_NAME}-${LATEST_VER}-${OS_NAME}-${ARCH}/${PROGRAM_NAME} /usr/sbin/${PROGRAM_NAME}
			echo "Starting new MTG..."
			${SYSTEMCTL_BIN} start ${PROGRAM_NAME} >/dev/null 2>&1
		fi
		echo "Remove ${PROGRAM_NAME}.tar.gz..."
		rm -f "${SCRIPT_DIR}/${PROGRAM_NAME}.tar.gz" >/dev/null 2>&1
		rm -rf "${SCRIPT_DIR}/${PROGRAM_NAME}-${LATEST_VER}-${OS_NAME}-${ARCH}" >/dev/null 2>&1
		echo "Show logs:"
		journalctl -u ${PROGRAM_NAME} -n 10 --no-pager
		echo "Show netstat..."
		${NETSTAT_BIN} -ltupn | grep LISTEN | grep ${PROGRAM_NAME}
		if [ -f "${CONF_DIR}/${PROGRAM_NAME}.toml" ]; then
			echo "Show doctor:"
			${PROGRAM_NAME} doctor "${CONF_DIR}/${PROGRAM_NAME}.toml"
			echo "Show access:"
			${PROGRAM_NAME} access "${CONF_DIR}/${PROGRAM_NAME}.toml"
		fi
	else
		echo "ERROR: Download not completed."
		exit 1
	fi
else
	echo "ERROR: Failed to get latest MTG version. Exit..."
	exit 1
fi
