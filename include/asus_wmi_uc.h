/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Interface between AsusWMIControl.kext (AsusWMIUserClient) and its clients
 * (tools/asusctl, the app). Plain C, shared by kernel and user space.
 */
#ifndef ASUS_WMI_UC_H
#define ASUS_WMI_UC_H

#include <stdint.h>

#define ASUS_WMI_SERVICE_CLASS "AsusWMIControl"

enum {
	kAsusSelGetInfo = 0,        /* out: struct AsusWMIInfo */
	kAsusSelSetKbdBrightness,   /* in: level 0-3 */
	kAsusSelSetRGB,             /* in: mode, r, g, b, speed 0-2, save 0/1 */
	kAsusSelSetRGBState,        /* in: boot, awake, sleep, keyboard, save */
	kAsusSelSetThermalPolicy,   /* in: ASUS_POLICY_* */
	kAsusSelSetChargeLimit,     /* in: percent 20-100 */
	kAsusSelSetPanelOD,         /* in: 0/1 */
	kAsusSelSetDGPUDisabled,    /* in: 0/1 (Eco) */
	kAsusSelCount
};

/* Feature bits in AsusWMIInfo.features: what DSTS reported present */
enum {
	kAsusFeatKbdBacklight = 1u << 0,
	kAsusFeatRGB          = 1u << 1,
	kAsusFeatRGBState     = 1u << 2,
	kAsusFeatThermal      = 1u << 3,
	kAsusFeatThermalVivo  = 1u << 4,
	kAsusFeatCPUFan       = 1u << 5,
	kAsusFeatGPUFan       = 1u << 6,
	kAsusFeatChargeLimit  = 1u << 7,
	kAsusFeatPanelOD      = 1u << 8,
	kAsusFeatDGPU         = 1u << 9,
	kAsusFeatGPUMux       = 1u << 10,
};

/* Policy values as the API sees them (TUF/ROG order); Vivo is mapped in the kext */
enum {
	ASUS_POLICY_BALANCED = 0,
	ASUS_POLICY_TURBO    = 1,
	ASUS_POLICY_SILENT   = 2,
};

#define ASUS_UNKNOWN 0xFFFFFFFFu   /* value not readable / not set yet */

struct AsusWMIInfo {
	uint32_t version;           /* 1 */
	uint32_t features;
	uint32_t kbdLevel;          /* 0-3, or ASUS_UNKNOWN */
	uint32_t thermalPolicy;     /* last set by us, or ASUS_UNKNOWN */
	uint32_t chargeLimit;       /* last set by us, or ASUS_UNKNOWN */
	uint32_t panelOD;           /* 0/1/ASUS_UNKNOWN */
	uint32_t dgpuDisabled;      /* 0/1/ASUS_UNKNOWN */
	uint32_t gpuMux;            /* 1 = hybrid, 0 = dGPU only, ASUS_UNKNOWN */
	uint32_t cpuFanRPM;         /* ASUS_UNKNOWN when unreadable */
	uint32_t gpuFanRPM;
	/* last RGB settings sent by us (rgbMode == ASUS_UNKNOWN: never set) */
	uint32_t rgbMode, rgbR, rgbG, rgbB, rgbSpeed;
	uint32_t reserved[8];
};

#endif /* ASUS_WMI_UC_H */
