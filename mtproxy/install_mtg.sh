#!/usr/bin/env bash
# vim: set sw=4 sts=4 et tw=80 :

#
# Program: Install MTG Telegram MTProto Proxy <install_mtg.sh>
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

# Default settings
DEFAULT_DOMAIN="google.com"
DEFAULT_PORT="3128"

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

# Detect jq
if _command_exists jq; then
	JQ_BIN=$(which jq)
else
	echo "ERROR: jq binary not found."
	exit 1
fi

# Detect pgrep
if _command_exists pgrep; then
	PGREP_BIN=$(which pgrep)
	PROCESS_RUN=$(${PGREP_BIN} -x "${PROGRAM_NAME}" 2>/dev/null | wc -l)
else
	PROCESS_RUN=$(ps -ef 2>/dev/null | grep [m]tg -c)
fi

# Confirm dialog
_confirm() {
	local RET=true
	while $RET; do
		read -r -p "${1:-Are you sure? [y/N]} " RESPONSE
		case "${RESPONSE}" in
		[yY][eE][sS] | [yY])
			RET=true
			break
			;;
		[nN][oO] | [nN])
			RET=false
			;;
		*)
			echo "Invalid response"
			;;
		esac
	done
	$RET
}

if [ ${PROCESS_RUN} -ne 0 ]; then
	echo "WARNING: MTG is already running."
	if [ ! -f "${CONF_DIR}/.installed" ]; then
		echo "ERROR: MTG was installed by another script or in another way and cannot be reinstalled by this script."
		exit 1
	fi
fi

if [ -f "/etc/redhat-release" ]; then
	DEFAULT_DIR=/ets/sysconfig
fi

if [ -f "${CONF_DIR}/.installed" ]; then
	echo "WARNING: MTG is already installed."
	echo "CONF_DIR: ${CONF_DIR}"
	echo "DATA_DIR: ${DATA_DIR}"
	echo "DEFAULT_DIR: ${DEFAULT_DIR}"
	_confirm "Would you really reinstall MTG (old config file will be renamed)? [y/N]" || exit 0
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

LATEST_VER=$(curl -Ls "https://api.github.com/repos/9seconds/${PROGRAM_NAME}/releases/latest" 2>/dev/null | ${JQ_BIN} -r .tag_name | sed 's/[^0-9.]//g')
if [ -n "${LATEST_VER}" ]; then
	echo "Latest MTG version: ${LATEST_VER}"
	OS_NAME=$(uname -s | tr '[:upper:]' '[:lower:]')
	echo "Downloading latest version..."
	wget https://github.com/9seconds/mtg/releases/download/v${LATEST_VER}/${PROGRAM_NAME}-${LATEST_VER}-${OS_NAME}-${ARCH}.tar.gz -O ${SCRIPT_DIR}/${PROGRAM_NAME}.tar.gz >/dev/null 2>&1
	if [ -f "${SCRIPT_DIR}/${PROGRAM_NAME}.tar.gz" ]; then
		echo "Done"
		echo "Extract ${PROGRAM_NAME}.tar.gz..."
		tar -zxf "${SCRIPT_DIR}/${PROGRAM_NAME}.tar.gz" >/dev/null 2>&1
		if [ -f "${SCRIPT_DIR}/${PROGRAM_NAME}-${LATEST_VER}-${OS_NAME}-${ARCH}/${PROGRAM_NAME}" ]; then
			echo "Stoping old MTG..."
			systemctl stop ${PROGRAM_NAME} >/dev/null 2>&1
			echo "Install new binary..."
			yes | cp "${SCRIPT_DIR}/${PROGRAM_NAME}-${LATEST_VER}-${OS_NAME}-${ARCH}/${PROGRAM_NAME}" /usr/sbin/${PROGRAM_NAME}
		fi
		echo "Creating config directory '${CONF_DIR}'..."
		mkdir "${CONF_DIR}" >/dev/null 2>&1
		mkdir "${DATA_DIR}" >/dev/null 2>&1
		if ! id "${PROGRAM_NAME}" &>/dev/null; then
			echo "Creating system user and group..."
			useradd --system --home-dir ${DATA_DIR} --no-create-home --shell /usr/sbin/nologin --user-group ${PROGRAM_NAME} >/dev/null 2>&1
			if [ $? -ne 0 ]; then
				echo "ERROR: System user not created. Exit..."
				exit 1
			fi
		fi
		echo "Creating file '${DEFAULT_DIR}/${PROGRAM_NAME}'..."
		cat <<EOF >"${DEFAULT_DIR}/${PROGRAM_NAME}"
OPTIONS='${CONF_DIR}/${PROGRAM_NAME}.toml'
EOF
		chown -R ${PROGRAM_NAME}:${PROGRAM_NAME} "${CONF_DIR}" "${DATA_DIR}" "${DEFAULT_DIR}/${PROGRAM_NAME}" >/dev/null 2>&1
		chmod 750 "${CONF_DIR}" "${DATA_DIR}" "${DEFAULT_DIR}/${PROGRAM_NAME}" >/dev/null 2>&1
		chmod 640 "${CONF_DIR}/${PROGRAM_NAME}.toml" >/dev/null 2>&1
		echo "Creating systemd unit file..."
		cat <<EOF >"${SYSTEMD_DIR}/${PROGRAM_NAME}.service"
[Unit]
Description=MTG - MTProto proxy server
Documentation=https://github.com/9seconds/mtg
After=network.target
 
[Service]
Type=simple
User=${PROGRAM_NAME}
Group=${PROGRAM_NAME}
EnvironmentFile=-${DEFAULT_DIR}/${PROGRAM_NAME}
WorkingDirectory=${DATA_DIR}
ExecStart=/usr/sbin/${PROGRAM_NAME} run \$OPTIONS
Restart=on-failure
RestartSec=3
DynamicUser=true
LimitNOFILE=65536
AmbientCapabilities=CAP_NET_BIND_SERVICE
 
[Install]
WantedBy=multi-user.target
EOF
		if [ -f "${CONF_DIR}/${PROGRAM_NAME}.toml" ]; then
			echo "Backup old config..."
			rm -f "${CONF_DIR}/${PROGRAM_NAME}.bak" >/dev/null 2>&1
			yes | mv "${CONF_DIR}/${PROGRAM_NAME}.toml" "${CONF_DIR}/${PROGRAM_NAME}.bak" >/dev/null 2>&1
		fi
		if [ ! -f "${CONF_DIR}/${PROGRAM_NAME}.toml" ]; then
			echo "Copy standart MTG config file..."
			cp "${SCRIPT_DIR}/${PROGRAM_NAME}-${LATEST_VER}-${OS_NAME}-${ARCH}/example.config.toml" "${CONF_DIR}/${PROGRAM_NAME}.toml" >/dev/null 2>&1
			echo -n "Enter Fake-TLS domain [${DEFAULT_DOMAIN}]: "
			read FAKE_TLS_DOMAIN
			if [ -z "${FAKE_TLS_DOMAIN}" ]; then
				FAKE_TLS_DOMAIN="${DEFAULT_DOMAIN}"
			fi
			DOMAIN_HEX=$(${PROGRAM_NAME} generate-secret --hex "${FAKE_TLS_DOMAIN}")
			echo "Fake-TLS domain hex: ${DOMAIN_HEX}"
			sed -i "s@ee367a189aee18fa31c190054efd4a8e9573746f726167652e676f6f676c65617069732e636f6d@${DOMAIN_HEX}@g" "${CONF_DIR}/${PROGRAM_NAME}.toml"
			echo -n "Enter Bind port [${DEFAULT_PORT}]: "
			read BIND_PORT
			if [ -z "${BIND_PORT}" ]; then
				BIND_PORT="${DEFAULT_PORT}"
			fi
			sed -i "s@0.0.0.0:3128@0.0.0.0:${BIND_PORT}@g" "${CONF_DIR}/${PROGRAM_NAME}.toml"
		fi
		echo "Remove ${PROGRAM_NAME}.tar.gz..."
		rm -f "${SCRIPT_DIR}/${PROGRAM_NAME}.tar.gz" >/dev/null 2>&1
		rm -rf "${SCRIPT_DIR}/${PROGRAM_NAME}-${LATEST_VER}-${OS_NAME}-${ARCH}" >/dev/null 2>&1
		echo "Starting MTG..."
		systemctl daemon-reload >/dev/null 2>&1
		systemctl enable ${PROGRAM_NAME} --now >/dev/null 2>&1
		touch "${CONF_DIR}/.installed" >/dev/null 2>&1
		echo "Waiting 10 second..."
		sleep 10
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
		echo "ERROR: Download not completed. Exit..."
		exit 1
	fi
else
	echo "ERROR: Failed to get latest MTG version. Exit..."
	exit 1
fi
