#!/usr/bin/env bash
# vim: set sw=4 sts=4 et tw=80 :

#
# Program: Install TeleMT Telegram MTProto Proxy <install_telemt.sh>
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

# Default settings
DEFAULT_DOMAIN="google.com"
DEFAULT_PORT="443"

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

# Checking the availability of necessary utilities
COMMAND_EXIST_ARRAY=(JQ NETSTAT CURL WGET TAR SYSTEMCTL OPENSSL)
for ((i=0; i<${#COMMAND_EXIST_ARRAY[@]}; i++)); do
	__CMDVAR=${COMMAND_EXIST_ARRAY[$i]}
	CMD_FIND=$(echo "${__CMDVAR}" | tr '[:upper:]' '[:lower:]')
	if _command_exists ${CMD_FIND} ; then
		eval $__CMDVAR'_BIN'="'$(which ${CMD_FIND})'"
		hash "${CMD_FIND}" >/dev/null 2>&1
	else
		echo -e "ERROR: Command '${CMD_FIND}' not found."
		exit 1
	fi
done

if _command_exists pgrep; then
	PGREP_BIN=$(which pgrep)
	PROCESS_RUN=$(${PGREP_BIN} -x "${PROGRAM_NAME}" 2>/dev/null | wc -l)
else
	PROCESS_RUN=$(ps -ef 2>/dev/null | grep [t]elemt -c)
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
	echo "WARNING: TeleMT is already running."
	if [ ! -f "${CONF_DIR}/.installed" ]; then
		echo "ERROR: TeleMT was installed by another script or in another way and cannot be reinstalled by this script."
		exit 1
	fi
fi

if [ -f "/etc/redhat-release" ]; then
	DEFAULT_DIR=/ets/sysconfig
fi

if [ -f "${CONF_DIR}/.installed" ]; then
	echo "WARNING: TeleMT is already installed."
	echo "CONF_DIR: ${CONF_DIR}"
	echo "DATA_DIR: ${DATA_DIR}"
	echo "DEFAULT_DIR: ${DEFAULT_DIR}"
	_confirm "Would you really reinstall TeleMT (old config file will be renamed)? [y/N]" || exit 0
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
if [ $? -eq 0 ]; then
	echo "Download complete."
	if [ -f "${SCRIPT_DIR}/${PROGRAM_NAME}.tar.gz" ]; then
		echo "Extract ${PROGRAM_NAME}.tar.gz..."
		${TAR_BIN} -zxf "${SCRIPT_DIR}/${PROGRAM_NAME}.tar.gz" >/dev/null 2>&1
	else
		echo "ERROR: TeleMT archive not found. Exit..."
		exit 1
	fi
	if [ -f "${SCRIPT_DIR}/${PROGRAM_NAME}" ]; then
		echo "Stoping old TeleMT..."
		${SYSTEMCTL_BIN} stop ${PROGRAM_NAME} >/dev/null 2>&1
		echo "Install new binary..."
		yes | cp "${SCRIPT_DIR}/${PROGRAM_NAME}" "/usr/sbin/${PROGRAM_NAME}"
	else
		echo "ERROR: TeleMT binary not found. Exit..."
		exit 1
	fi
	echo "Creating config directory '${CONF_DIR}'..."
	mkdir "${CONF_DIR}" >/dev/null 2>&1
	mkdir "${DATA_DIR}" >/dev/null 2>&1
	if [ -f "${CONF_DIR}/${PROGRAM_NAME}.toml" ]; then
		echo "Backup old config..."
		rm -f "${CONF_DIR}/${PROGRAM_NAME}.bak" >/dev/null 2>&1
		yes | mv "${CONF_DIR}/${PROGRAM_NAME}.toml" "${CONF_DIR}/${PROGRAM_NAME}.bak" >/dev/null 2>&1
	fi
	if [ ! -f "${CONF_DIR}/${PROGRAM_NAME}.toml" ]; then
		echo -n "Enter Fake-TLS domain [${DEFAULT_DOMAIN}]: "
		read FAKE_TLS_DOMAIN
		if [ -z "${FAKE_TLS_DOMAIN}" ]; then
			FAKE_TLS_DOMAIN="${DEFAULT_DOMAIN}"
		fi
		SECRET_HEX=$(${OPENSSL_BIN} rand -hex 16)
		echo -n "Enter Bind port [${DEFAULT_PORT}]: "
		read BIND_PORT
		if [ -z "${BIND_PORT}" ]; then
			BIND_PORT="${DEFAULT_PORT}"
		fi
		echo "Created standart Telemt config..."
		cat <<EOF >"${CONF_DIR}/${PROGRAM_NAME}.toml"
[general]
use_middle_proxy = false
log_level = "normal"

[general.modes]
classic = false
secure = false
tls = true

[general.links]
show = "*"

[server]
port = ${BIND_PORT}

[server.api]
enabled = true
listen = "127.0.0.1:9091"
whitelist = ["127.0.0.1/32"]
read_only = true

[[server.listeners]]
ip = "0.0.0.0"

[censorship]
tls_domain = "${FAKE_TLS_DOMAIN}"

[access.users]
hello = "${SECRET_HEX}"
EOF
	fi
	rm -f "${SCRIPT_DIR}/${PROGRAM_NAME}.tar.gz" >/dev/null 2>&1
	rm -rf "${SCRIPT_DIR}/${PROGRAM_NAME}" >/dev/null 2>&1
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
Description=Telemt - MTProto proxy server
Documentation=https://github.com/telemt/telemt
After=network.target
 
[Service]
Type=simple
User=${PROGRAM_NAME}
Group=${PROGRAM_NAME}
EnvironmentFile=-${DEFAULT_DIR}/${PROGRAM_NAME}
WorkingDirectory=${DATA_DIR}
ExecStart=/usr/sbin/${PROGRAM_NAME} \$OPTIONS
Restart=on-failure
RestartSec=3
LimitNOFILE=65536
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
	echo "Starting Telemt..."
	${SYSTEMCTL_BIN} daemon-reload >/dev/null 2>&1
	${SYSTEMCTL_BIN} enable ${PROGRAM_NAME} --now >/dev/null 2>&1
	touch "${CONF_DIR}/.installed" >/dev/null 2>&1
	echo "Waiting 10 second..."
	sleep 10
	echo "Show logs:"
	journalctl -u ${PROGRAM_NAME} -n 35 --no-pager
	echo "Show netstat:"
	${NETSTAT_BIN} -ltupn | grep LISTEN | grep ${PROGRAM_NAME}
	echo "Show connections links per user:"
	${CURL_BIN} -s http://127.0.0.1:9091/v1/users | ${JQ_BIN} -r '.data[] | "[\(.username)]", (.links.classic[]? | "classic: \(.)"), (.links.secure[]? | "secure: \(.)"), (.links.tls[]? | "tls: \(.)"), ""'
else
	echo "ERROR: Download not completed. Exit..."
	exit 1
fi
