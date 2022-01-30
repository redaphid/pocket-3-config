#!/usr/bin/env bash

UMPC="gpd-pocket3"
XORG_CONF_PATH="/usr/share/X11/xorg.conf.d"
INTEL_CONF="${XORG_CONF_PATH}/20-${UMPC}-intel.conf"
MODPROBE_CONF="/etc/modprobe.d/alsa-${UMPC}.conf"
TRACKPOINT_CONF="${XORG_CONF_PATH}/80-${UMPC}-trackpoint.conf"
BRCM4356_CONF="/lib/firmware/brcm/brcmfmac4356-pcie.txt"
CONSOLE_CONF="/etc/default/console-setup"
EDID="/lib/firmware/edid/${UMPC}-edid.bin"
HWDB_CONF="/etc/udev/hwdb.d/61-${UMPC}-sensor-local.hwdb"

# Copy file from /data to it's intended location
function inject_data() {
  local SOURCE_FILE=""
  local TARGET_FILE="${1}"
  local TARGET_DIR=$(dirname "${TARGET_FILE}")
  if [ -n "${2}" ] && [ -f "${2}" ]; then
    SOURCE_FILE="${2}"
  else
    SOURCE_FILE="data/$(basename "${TARGET_FILE}")"
  fi

  if [ -f "${SOURCE_FILE}" ]; then
    echo " - Injecting ${TARGET_FILE}"
    if [ ! -d "${TARGET_DIR}" ]; then
      mkdir -p "${TARGET_DIR}"
    fi
    cp "${SOURCE_FILE}" "${TARGET_FILE}"
  fi
}

function enable_umpc_config() {
  # Enable Intel SNA, DRI3 and TearFree.
  inject_data "${INTEL_CONF}"

  # Scroll while holding down the right track point button
  inject_data "${TRACKPOINT_CONF}"

  # Configure kernel modules
  inject_data "${MODPROBE_CONF}"

  # Device specific tweaks
  # Increase console font size
  sed -i 's/FONTSIZE="8x16"/FONTSIZE="16x32"/' "${CONSOLE_CONF}"

  inject_data "${HWDB_CONF}"
  systemd-hwdb update
  udevadm trigger -v -p DEVNAME=/dev/iio:device0
  systemctl restart iio-sensor-proxy.service
  
  kernelstub -a fbcon=rotate:1
  kernelstub -a video=DSI-1:panel_orientation=right_side_up
  kernelstub -a mem_sleep_default=s2idle
  
  echo "UMPC hardware configuration is applied. Please reboot to complete the setup."
}

function disable_umpc_config() {
  # Remove the UMPC Pocket hardware configuration
  for CONFIG in ${TRACKPOINT_CONF} ${EDID} ${BRCM4356_CONF}; do
    if [ -f "${CONFIG}" ]; then
      rm -fv "${CONFIG}"
    fi
  done

  # Restore tty font size
  sed -i 's/FONTSIZE=16x32"/FONTSIZE="8x16"/' "${CONSOLE_CONF}"
  
  kernelstub -d fbcon=rotate:1
  kernelstub -d video=DSI-1:panel_orientation=right_side_up
  kernelstub -d mem_sleep_default=s2idle

  echo "UMPC hardware configuration is removed. Please reboot to complete the setup."
}

function usage() {
    echo
    echo "Usage"
    echo "  ${0} enable || disable"
    echo ""
    echo "You must supply one of the following modes of operation"
    echo "  enable  : apply the ${MODEL} hardware configuration"
    echo "  disable : remove the ${MODEL} hardware configuration"
    echo "  help    : This help."
    echo
    exit 1
}

# Make sure we are not running on Wayland
if [ "${XDG_SESSION_TYPE}" == "wayland" ]; then
  echo "ERROR! This script is only designed to configure Xorg (X11). Please choose an alternative desktop session that uses Xorg (X11)."
  exit 1
fi

# Make sure we are root.
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR! You must be root to run $(basename $0)"
  exit 1
fi

# Display usage instructions if we've not been given an action. If an action
# has been provided store it in lowercase.
if [ -z "${1}" ]; then
  usage
else
  MODE=$(echo "${1}" | tr '[:upper:]' '[:lower:]')
fi

if [ -z "${UMPC}" ]; then
    echo "ERROR! You must supply the name of the device you want to apply modifications for."
    usage
fi

case "${UMPC}" in
  gpd-pocket3) true;;
  *) echo "ERROR! Unknown device name given."
     usage;;
esac

case "${MODE}" in
  -d|--disable|disable)
    disable_umpc_config;;
  -e|--enable|enable)
    enable_umpc_config;;
  -h|--h|-help|--help|-?|help)
    usage;;
  *)
    echo "ERROR! \"${MODE}\" is not a supported parameter."
    usage;;
esac
