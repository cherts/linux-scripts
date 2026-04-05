#!/usr/bin/env bash
# vim: set sw=4 sts=4 et tw=80 :

#
# Program: Remove TeleMT Telegram MTProto Proxy <remove_telemt.sh>
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

# Detect pgrep
if _command_exists pgrep; then
	PGREP_BIN=$(which pgrep)
	PROCESS_RUN=$(${PGREP_BIN} -x "${PROGRAM_NAME}" 2>/dev/null | wc -l)
else
	PROCESS_RUN=$(ps -ef 2>/dev/null | grep [t]elemt -c)
fi

if [ ! -f "${CONF_DIR}/.installed" ]; then
	echo "ERROR: TeleMT was installed by another script or in another way and cannot be removed by this script."
	exit 1
fi

if [ ${PROCESS_RUN} -ne 0 ]; then
	echo "WARNING: TeleMT is already running."
	echo "Show netstat..."
	${NETSTAT_BIN} -ltupn | grep LISTEN | grep ${PROGRAM_NAME}
	echo "Stopping ${PROGRAM_NAME}..."
	systemctl stop ${PROGRAM_NAME} >/dev/null 2>&1
	systemctl disable ${PROGRAM_NAME} >/dev/null 2>&1
else
	echo "WARNING: TeleMT is not running."
	systemctl disable ${PROGRAM_NAME} >/dev/null 2>&1
fi

echo "Remove config and data directory..."
rm -rf "${CONF_DIR}" >/dev/null 2>&1
rm -rf "${DATA_DIR}" >/dev/null 2>&1
echo "Remove binary..."
rm -f "/usr/sbin/${PROGRAM_NAME}" >/dev/null 2>&1
echo "Remove default file..."
rm -f "${DEFAULT_DIR}/${PROGRAM_NAME}" >/dev/null 2>&1
echo "Remove systemd service..."
rm -f "${SYSTEMD_DIR}/${PROGRAM_NAME}.service"
echo "Remove system user and group..."
userdel ${PROGRAM_NAME} >/dev/null 2>&1
groupdel ${PROGRAM_NAME} >/dev/null 2>&1
echo "Reload systemd..."
systemctl daemon-reload >/dev/null 2>&1
echo "Show netstat..."
${NETSTAT_BIN} -ltupn | grep LISTEN | grep ${PROGRAM_NAME}
