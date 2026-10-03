/* SPDX-License-Identifier: GPL-2.0 */
/*
 * ASUS WMI method and device IDs.
 *
 * Values from Linux include/linux/platform_data/x86/asus-wmi.h and
 * drivers/platform/x86/asus-wmi.c (torvalds/linux master, fetched 2026-10-03).
 * Shared by the kext and the app, so plain C with no kernel headers.
 */
#ifndef ASUS_WMI_IDS_H
#define ASUS_WMI_IDS_H

/* The management GUID; its method is found through _WDG (WMNB on ASUS). */
#define ASUS_WMI_MGMT_GUID_STR      "97845ED0-4E6D-11DE-8A39-0800200C9A66"

/* Method IDs (Arg1 of WMxx) */
#define ASUS_WMI_METHODID_SPEC      0x43455053
#define ASUS_WMI_METHODID_SFUN      0x4E554653
#define ASUS_WMI_METHODID_INIT      0x54494E49
#define ASUS_WMI_METHODID_DCTS      0x53544344  /* _UID "ASUSWMI" */
#define ASUS_WMI_METHODID_DSTS      0x53545344  /* _UID "ATK" */
#define ASUS_WMI_METHODID_DEVS      0x53564544
#define ASUS_WMI_UNSUPPORTED_METHOD 0xFFFFFFFE

/* DSTS result bits */
#define ASUS_WMI_DSTS_STATUS_BIT    0x00000001
#define ASUS_WMI_DSTS_PRESENCE_BIT  0x00010000

/* Lighting */
#define ASUS_WMI_DEVID_KBD_BACKLIGHT        0x00050021
#define ASUS_WMI_DEVID_TUF_RGB_MODE         0x00100056
#define ASUS_WMI_DEVID_TUF_RGB_MODE2        0x0010005A
#define ASUS_WMI_DEVID_TUF_RGB_STATE        0x00100057
#define ASUS_WMI_DEVID_LIGHTBAR             0x00050025

/* Display */
#define ASUS_WMI_DEVID_PANEL_OD             0x00050019
#define ASUS_WMI_DEVID_PANEL_HD             0x0005001C
#define ASUS_WMI_DEVID_MINI_LED_MODE        0x0005001E
#define ASUS_WMI_DEVID_MINI_LED_MODE2       0x0005002E

/* Thermal / fans */
#define ASUS_WMI_DEVID_FAN_BOOST_MODE       0x00110018
#define ASUS_WMI_DEVID_THROTTLE_THERMAL_POLICY      0x00120075
#define ASUS_WMI_DEVID_THROTTLE_THERMAL_POLICY_VIVO 0x00110019
#define ASUS_WMI_DEVID_CPU_FAN_CTRL         0x00110013
#define ASUS_WMI_DEVID_GPU_FAN_CTRL         0x00110014
#define ASUS_WMI_DEVID_MID_FAN_CTRL         0x00110031
#define ASUS_WMI_DEVID_CPU_FAN_CURVE        0x00110024
#define ASUS_WMI_DEVID_GPU_FAN_CURVE        0x00110025
#define ASUS_WMI_DEVID_MID_FAN_CURVE        0x00110032

/* Thermal policy values: TUF/ROG order, then the Vivobook order */
#define ASUS_THERMAL_POLICY_BALANCED        0
#define ASUS_THERMAL_POLICY_TURBO           1
#define ASUS_THERMAL_POLICY_SILENT          2
#define ASUS_THERMAL_POLICY_BALANCED_VIVO   0
#define ASUS_THERMAL_POLICY_SILENT_VIVO     1
#define ASUS_THERMAL_POLICY_TURBO_VIVO      2

/* GPU */
#define ASUS_WMI_DEVID_DGPU                 0x00090020  /* 1 = dGPU off (Eco) */
#define ASUS_WMI_DEVID_GPU_MUX              0x00090016  /* 0 = dGPU only: never from macOS */
#define ASUS_WMI_DEVID_GPU_MUX_VIVO         0x00090026
#define ASUS_WMI_DEVID_EGPU                 0x00090019
#define ASUS_WMI_DEVID_EGPU_CONNECTED       0x00090018
#define ASUS_WMI_DEVID_DGPU_BASE_TGP        0x00120099
#define ASUS_WMI_DEVID_DGPU_SET_TGP         0x00120098
#define ASUS_WMI_DEVID_NV_DYN_BOOST         0x001200C0
#define ASUS_WMI_DEVID_NV_THERM_TARGET      0x001200C2

/* Power limits (AMD and Intel) */
#define ASUS_WMI_DEVID_PPT_PL2_SPPT         0x001200A0
#define ASUS_WMI_DEVID_PPT_PL1_SPL          0x001200A3
#define ASUS_WMI_DEVID_PPT_APU_SPPT         0x001200B0
#define ASUS_WMI_DEVID_PPT_PLAT_SPPT        0x001200B1
#define ASUS_WMI_DEVID_PPT_PL3_FPPT         0x001200C1

/* Battery and misc */
#define ASUS_WMI_DEVID_RSOC                 0x00120057  /* charge limit, percent */
#define ASUS_WMI_DEVID_CHARGE_MODE          0x0012006C
#define ASUS_WMI_DEVID_FNLOCK               0x00100023
#define ASUS_WMI_DEVID_CAMERA               0x00060013
#define ASUS_WMI_DEVID_BOOT_SOUND           0x00130022
#define ASUS_WMI_DEVID_MCU_POWERSAVE        0x001200E2
#define ASUS_WMI_DEVID_APU_MEM              0x000600C1

#endif /* ASUS_WMI_IDS_H */
