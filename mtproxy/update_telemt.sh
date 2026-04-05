#!/usr/bin/env bash
# vim: set sw=4 sts=4 et tw=80 :

#
# Program: Update TeleMT Telegram MTProto Proxy <update_telemt.sh>
#
# Author: Mikhail Grigorev <sleuthhound at gmail dot com>
#
# Current Version: 1.0
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
PROGRAM_NAME="telemt"
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

# Detect netstat
if _command_exists netstat; then
	NETSTAT_BIN=$(which netstat)
else
	echo "ERROR: netstat binary not found."
	exit 1
fi

if _command_exists wget; then
	WGET_BIN=$(which wget)
else
	echo "ERROR: wget binary not found."
	exit 1
fi

# Detect pgrep
if _command_exists pgrep; then
	PGREP_BIN=$(which pgrep)
	PROCESS_RUN=$(${PGREP_BIN} -x "${PROGRAM_NAME}" 2>/dev/null | wc -l)
else
	PROCESS_RUN=$(ps -ef 2>/dev/null | grep [t]elemt -c)
fi

if [ ${PROCESS_RUN} -ne 0 ]; then
	echo "WARNING: TeleMT is already running."
fi

if [ ! -f "${CONF_DIR}/.installed" ]; then
	echo "ERROR: TeleMT was installed by another script or in another way and cannot be reinstalled by this script."
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

echo -n "Checking your privileges... "
CURRENT_USER=$(whoami)
if [[ "${CURRENT_USER}" = "root" ]]; then
	echo "OK"
else
	echo "ERROR: root access is required"
	exit 1
fi

echo "Downloading latest version..."
${WGET_BIN} "https://github.com/telemt/telemt/releases/latest/download/telemt-$(uname -m)-linux-$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu).tar.gz" -O "${SCRIPT_DIR}/${PROGRAM_NAME}.tar.gz" >/dev/null 2>&1
if [ -f "${SCRIPT_DIR}/${PROGRAM_NAME}.tar.gz" ]; then
	echo "Done"
	echo "Extract ${PROGRAM_NAME}.tar.gz..."
	tar -zxf "${SCRIPT_DIR}/${PROGRAM_NAME}.tar.gz" >/dev/null 2>&1
	if [ -f "${SCRIPT_DIR}/${PROGRAM_NAME}" ]; then
		echo "Stoping old Telemt..."
		systemctl stop ${PROGRAM_NAME} >/dev/null 2>&1
		echo "Install new binary..."
		yes | cp "${SCRIPT_DIR}/${PROGRAM_NAME}" "/usr/sbin/${PROGRAM_NAME}"
		echo "Starting new Telemt..."
		systemctl start ${PROGRAM_NAME} >/dev/null 2>&1
	fi
	echo "Remove ${PROGRAM_NAME}.tar.gz..."
	rm -f "${SCRIPT_DIR}/${PROGRAM_NAME}.tar.gz" >/dev/null 2>&1
	rm -rf "${SCRIPT_DIR}/${PROGRAM_NAME}" >/dev/null 2>&1
	echo "Show logs:"
	journalctl -u ${PROGRAM_NAME} -n 10 --no-pager
	echo "Show netstat:"
	${NETSTAT_BIN} -ltupn | grep LISTEN | grep ${PROGRAM_NAME}
	echo "Show links:"
	curl -s http://127.0.0.1:9091/v1/users | ${JQ_BIN}
else
	echo "ERROR: Download not completed. Exit..."
	exit 1
fi
