#!/bin/bash
# Fail the build if a kernel option the 83N3 relies on is missing or has the
# wrong value. Options marked "y" must be built in (needed before the root
# filesystem is mounted); "m" accepts module or built-in.
# Usage: kernel/check-config.sh <.config>
set -uo pipefail
cfg=$1
fail=0

need() { # option, y|m, reason
	local v
	v=$(grep -E "^$1=" "$cfg" | cut -d= -f2)
	case "$2:$v" in
	y:y|m:m|m:y) printf 'ok   %-28s %-2s %s\n' "$1" "$v" "$3" ;;
	*) printf 'FAIL %-28s %-2s %s (need %s)\n' "$1" "${v:-unset}" "$3" "$2"; fail=1 ;;
	esac
}

forbid() { # option, reason: must be unset, "n" or 0
	local v
	v=$(grep -E "^$1=" "$cfg" | cut -d= -f2)
	case "$v" in
	''|n|0) printf 'ok   %-28s %-2s %s\n' "$1" "${v:-unset}" "$2" ;;
	*) printf 'FAIL %-28s %-2s %s (must be off)\n' "$1" "$v" "$2"; fail=1 ;;
	esac
}

# Boot path
need CONFIG_EFI_ZBOOT            y "GRUB 2.12 only boots PE kernel images"
need CONFIG_PCIE_QCOM            y "NVMe root on pcie6a"
need CONFIG_BLK_DEV_NVME         y "NVMe root"
need CONFIG_SQUASHFS             y "live medium"
need CONFIG_OVERLAY_FS           y "live medium"
need CONFIG_FB_EFI               y "early console"
need CONFIG_FW_LOADER_COMPRESS   y "compressed distro firmware"
need CONFIG_FW_LOADER_COMPRESS_ZSTD y "Ubuntu .zst firmware"
# Display, brightness, HDMI
need CONFIG_DRM_MSM              m "display"
need CONFIG_DRM_PANEL_EDP        m "eDP panel"
need CONFIG_BACKLIGHT_PWM        m "backlight"
need CONFIG_LEDS_QCOM_LPG        m "pmk8550 PWM (backlight)"
need CONFIG_DRM_SIMPLE_BRIDGE    m "DP-to-HDMI bridge"
need CONFIG_DRM_DISPLAY_CONNECTOR m "HDMI connector"
need CONFIG_PHY_QCOM_QMP_COMBO   m "DP PHY for HDMI"
need CONFIG_DRM_MSM_DP           y "msm DisplayPort controllers (eDP, HDMI)"
need CONFIG_DRM_AUX_BRIDGE       m "PHY -> HDMI bridge link (aux_bridge)"
# Input
need CONFIG_I2C_HID_OF           m "keyboard, touchpad, touchscreen"
need CONFIG_HID_MULTITOUCH       m "touchpad, touchscreen"
need CONFIG_I2C_QCOM_GENI        m "I2C buses"
# Camera
need CONFIG_USB_DWC3_QCOM        m "usb_2 controller"
need CONFIG_PHY_NXP_PTN3222      m "camera eUSB2 repeater"
need CONFIG_USB_VIDEO_CLASS      m "UVC camera 13d3:54bf"
# Audio (headset + mics by default; speaker amps on the -speakers board)
need CONFIG_SND_SOC_X1E80100     m "sound card"
need CONFIG_SND_SOC_QDSP6_APM    m "AudioReach DSP audio"
need CONFIG_QCOM_Q6V5_PAS        m "ADSP loader"
need CONFIG_QCOM_PD_MAPPER       m "ADSP protection domains"
need CONFIG_SOUNDWIRE_QCOM       m "SoundWire controllers"
need CONFIG_SND_SOC_WCD938X_SDW  m "WCD9385 headset codec"
need CONFIG_SND_SOC_LPASS_RX_MACRO m "headphone path"
need CONFIG_SND_SOC_LPASS_TX_MACRO m "headset mic path"
need CONFIG_SND_SOC_LPASS_VA_MACRO m "internal DMICs"
need CONFIG_SND_SOC_LPASS_WSA_MACRO m "speaker path (-speakers)"
need CONFIG_SND_SOC_WSA884X      m "speaker amps (-speakers)"
# Thermal and fan
need CONFIG_QCOM_TSENS           y "SoC temperature sensors"
need CONFIG_EC_QCOM_HAMOA        m "EC at i2c5 0x76 (fan)"
# Phone USB tethering
need CONFIG_USB_NET_RNDIS_HOST   m "Android USB tethering"
need CONFIG_USB_IPHETH           m "iPhone USB tethering"
# HDMI and crash diagnostics (series 3): report, never reboot by themselves
need CONFIG_DRM_DISPLAY_DP_AUX_CHARDEV y "read the HDMI converter's DPCD"
need CONFIG_SOFTLOCKUP_DETECTOR  y "report stuck CPUs"
need CONFIG_HARDLOCKUP_DETECTOR  y "report CPUs stuck with IRQs off"
need CONFIG_DETECT_HUNG_TASK     y "report hung tasks"
forbid CONFIG_BOOTPARAM_SOFTLOCKUP_PANIC "no panic on soft lockup"
forbid CONFIG_BOOTPARAM_HARDLOCKUP_PANIC "no panic on hard lockup"
forbid CONFIG_BOOTPARAM_HUNG_TASK_PANIC  "no panic on hung task"
forbid CONFIG_PANIC_ON_OOPS              "an oops must not reboot"
# Wi-Fi, Bluetooth
need CONFIG_ATH12K               m "WCN7850 Wi-Fi"
need CONFIG_BT_QCA               m "WCN7850 Bluetooth"

exit $fail
