/* SPDX-License-Identifier: GPL-2.0 */
/*
 * AsusWMIProbe: read-only survey of the ASUS WMI interface.
 *
 * Attaches next to AsusSMC on the ASUS WMI device (its own IOMatchCategory),
 * finds the management method through _WDG like Linux's wmi bus does, then
 * asks DSTS for every device ID in include/asus_wmi_ids.h. Nothing is set:
 * only SPEC, SFUN and DSTS/DCTS are called, the same queries Linux asus-wmi
 * makes at probe. Results go to the log and to the "AsusWMI" registry property:
 *
 *   ioreg -r -c AsusWMIProbe -k AsusWMI -w0
 */
#include <IOKit/IOService.h>
#include <IOKit/IOLib.h>
#include <IOKit/acpi/IOACPIPlatformDevice.h>
#include <libkern/c++/OSData.h>
#include <libkern/c++/OSNumber.h>
#include <libkern/c++/OSString.h>
#include <libkern/c++/OSDictionary.h>

#include "asus_wmi_ids.h"

#define LOG(fmt, ...) IOLog("AsusWMIProbe: " fmt "\n", ##__VA_ARGS__)

/* Linux struct bios_args: six dwords, all of them always sent. */
struct BiosArgs {
	UInt32 arg[6];
} __attribute__((packed));

/* _WDG entry (Linux drivers/platform/x86/wmi.c, struct guid_block) */
struct WdgBlock {
	UInt8 guid[16];
	union {
		char  object_id[2];
		struct { UInt8 notify_id; UInt8 reserved; };
	};
	UInt8 instance_count;
	UInt8 flags;
} __attribute__((packed));
static_assert(sizeof(WdgBlock) == 20, "_WDG entries are 20 bytes");

#define WMI_FLAG_METHOD 0x2

/* 97845ED0-4E6D-11DE-8A39-0800200C9A66 as stored in _WDG (mixed endian) */
static const UInt8 kMgmtGuid[16] = {
	0xD0, 0x5E, 0x84, 0x97, 0x6D, 0x4E, 0xDE, 0x11,
	0x8A, 0x39, 0x08, 0x00, 0x20, 0x0C, 0x9A, 0x66,
};

struct DevName { UInt32 id; const char *name; };
static const DevName kDevices[] = {
	{ ASUS_WMI_DEVID_KBD_BACKLIGHT,  "KBD_BACKLIGHT" },
	{ ASUS_WMI_DEVID_TUF_RGB_MODE,   "TUF_RGB_MODE" },
	{ ASUS_WMI_DEVID_TUF_RGB_MODE2,  "TUF_RGB_MODE2" },
	{ ASUS_WMI_DEVID_TUF_RGB_STATE,  "TUF_RGB_STATE" },
	{ ASUS_WMI_DEVID_LIGHTBAR,       "LIGHTBAR" },
	{ ASUS_WMI_DEVID_PANEL_OD,       "PANEL_OD" },
	{ ASUS_WMI_DEVID_PANEL_HD,       "PANEL_HD" },
	{ ASUS_WMI_DEVID_MINI_LED_MODE,  "MINI_LED_MODE" },
	{ ASUS_WMI_DEVID_MINI_LED_MODE2, "MINI_LED_MODE2" },
	{ ASUS_WMI_DEVID_FAN_BOOST_MODE, "FAN_BOOST_MODE" },
	{ ASUS_WMI_DEVID_THROTTLE_THERMAL_POLICY,      "THROTTLE_THERMAL_POLICY" },
	{ ASUS_WMI_DEVID_THROTTLE_THERMAL_POLICY_VIVO, "THROTTLE_THERMAL_POLICY_VIVO" },
	{ ASUS_WMI_DEVID_CPU_FAN_CTRL,   "CPU_FAN_CTRL" },
	{ ASUS_WMI_DEVID_GPU_FAN_CTRL,   "GPU_FAN_CTRL" },
	{ ASUS_WMI_DEVID_MID_FAN_CTRL,   "MID_FAN_CTRL" },
	{ ASUS_WMI_DEVID_CPU_FAN_CURVE,  "CPU_FAN_CURVE" },
	{ ASUS_WMI_DEVID_GPU_FAN_CURVE,  "GPU_FAN_CURVE" },
	{ ASUS_WMI_DEVID_MID_FAN_CURVE,  "MID_FAN_CURVE" },
	{ ASUS_WMI_DEVID_DGPU,           "DGPU" },
	{ ASUS_WMI_DEVID_GPU_MUX,        "GPU_MUX" },
	{ ASUS_WMI_DEVID_GPU_MUX_VIVO,   "GPU_MUX_VIVO" },
	{ ASUS_WMI_DEVID_EGPU,           "EGPU" },
	{ ASUS_WMI_DEVID_EGPU_CONNECTED, "EGPU_CONNECTED" },
	{ ASUS_WMI_DEVID_DGPU_BASE_TGP,  "DGPU_BASE_TGP" },
	{ ASUS_WMI_DEVID_DGPU_SET_TGP,   "DGPU_SET_TGP" },
	{ ASUS_WMI_DEVID_NV_DYN_BOOST,   "NV_DYN_BOOST" },
	{ ASUS_WMI_DEVID_NV_THERM_TARGET,"NV_THERM_TARGET" },
	{ ASUS_WMI_DEVID_PPT_PL2_SPPT,   "PPT_PL2_SPPT" },
	{ ASUS_WMI_DEVID_PPT_PL1_SPL,    "PPT_PL1_SPL" },
	{ ASUS_WMI_DEVID_PPT_APU_SPPT,   "PPT_APU_SPPT" },
	{ ASUS_WMI_DEVID_PPT_PLAT_SPPT,  "PPT_PLAT_SPPT" },
	{ ASUS_WMI_DEVID_PPT_PL3_FPPT,   "PPT_PL3_FPPT" },
	{ ASUS_WMI_DEVID_RSOC,           "RSOC" },
	{ ASUS_WMI_DEVID_CHARGE_MODE,    "CHARGE_MODE" },
	{ ASUS_WMI_DEVID_FNLOCK,         "FNLOCK" },
	{ ASUS_WMI_DEVID_CAMERA,         "CAMERA" },
	{ ASUS_WMI_DEVID_BOOT_SOUND,     "BOOT_SOUND" },
	{ ASUS_WMI_DEVID_MCU_POWERSAVE,  "MCU_POWERSAVE" },
	{ ASUS_WMI_DEVID_APU_MEM,        "APU_MEM" },
};

class AsusWMIProbe : public IOService {
	OSDeclareDefaultStructors(AsusWMIProbe)

	IOACPIPlatformDevice *acpi = nullptr;
	char method[5] = {};        /* "WMNB" */
	UInt32 dstsId = ASUS_WMI_METHODID_DSTS;

	bool findMethod();
	void pickDsts();
	/* Returns false when the call failed or returned no integer. */
	bool call(UInt32 methodId, UInt32 a0, UInt32 a1, UInt32 *ret);

public:
	bool start(IOService *provider) override;
};

OSDefineMetaClassAndStructors(AsusWMIProbe, IOService)

bool AsusWMIProbe::findMethod()
{
	OSObject *obj = nullptr;
	if (acpi->evaluateObject("_WDG", &obj) != kIOReturnSuccess || !obj)
		return false;

	bool found = false;
	OSData *wdg = OSDynamicCast(OSData, obj);
	if (wdg) {
		const WdgBlock *b = (const WdgBlock *)wdg->getBytesNoCopy();
		unsigned n = wdg->getLength() / sizeof(WdgBlock);
		for (unsigned i = 0; i < n; i++) {
			if (memcmp(b[i].guid, kMgmtGuid, sizeof(kMgmtGuid)) != 0)
				continue;
			if (!(b[i].flags & WMI_FLAG_METHOD))
				continue;
			method[0] = 'W';
			method[1] = 'M';
			method[2] = b[i].object_id[0];
			method[3] = b[i].object_id[1];
			found = acpi->validateObject(method) == kIOReturnSuccess;
			break;
		}
	}
	obj->release();
	return found;
}

/* asus_wmi_platform_init: _UID "ASUSWMI" uses DCTS, everything else DSTS. */
void AsusWMIProbe::pickDsts()
{
	OSObject *obj = nullptr;
	if (acpi->evaluateObject("_UID", &obj) != kIOReturnSuccess || !obj)
		return;
	if (OSString *s = OSDynamicCast(OSString, obj)) {
		if (s->isEqualTo("ASUSWMI"))
			dstsId = ASUS_WMI_METHODID_DCTS;
		LOG("_UID \"%s\"", s->getCStringNoCopy());
	} else if (OSData *d = OSDynamicCast(OSData, obj)) {
		if (d->getLength() >= 7 && !memcmp(d->getBytesNoCopy(), "ASUSWMI", 7))
			dstsId = ASUS_WMI_METHODID_DCTS;
	}
	obj->release();
}

/* wmi_evaluate_method(guid, instance 0, methodId, bios_args) */
bool AsusWMIProbe::call(UInt32 methodId, UInt32 a0, UInt32 a1, UInt32 *ret)
{
	BiosArgs args = {};
	args.arg[0] = a0;
	args.arg[1] = a1;

	OSObject *params[3] = {
		OSNumber::withNumber(0ULL, 32),
		OSNumber::withNumber((unsigned long long)methodId, 32),
		OSData::withBytes(&args, sizeof(args)),
	};
	OSObject *result = nullptr;
	IOReturn rc = kIOReturnNoMemory;
	if (params[0] && params[1] && params[2])
		rc = acpi->evaluateObject(method, &result, params, 3);
	for (OSObject *p : params)
		if (p)
			p->release();

	bool ok = false;
	if (rc == kIOReturnSuccess && result) {
		if (OSNumber *n = OSDynamicCast(OSNumber, result)) {
			*ret = n->unsigned32BitValue();
			ok = true;
		} else if (OSData *d = OSDynamicCast(OSData, result)) {
			if (d->getLength() >= 4) {
				memcpy(ret, d->getBytesNoCopy(), 4);
				ok = true;
			}
		}
	}
	if (result)
		result->release();
	return ok;
}

bool AsusWMIProbe::start(IOService *provider)
{
	acpi = OSDynamicCast(IOACPIPlatformDevice, provider);
	if (!acpi || !findMethod())
		return false;   /* another PNP0C14 device, not the ASUS one */
	if (!IOService::start(provider))
		return false;

	pickDsts();
	LOG("management method %s on %s, status method %s", method,
	    provider->getName(), dstsId == ASUS_WMI_METHODID_DCTS ? "DCTS" : "DSTS");

	OSDictionary *dict = OSDictionary::withCapacity(64);
	if (!dict)
		return true;

	auto put = [dict](const char *key, const char *val) {
		if (OSString *s = OSString::withCString(val)) {
			dict->setObject(key, s);
			s->release();
		}
	};
	char line[64];
	UInt32 v;
	put("Method", method);
	if (call(ASUS_WMI_METHODID_SPEC, 0, 0x9, &v)) {
		snprintf(line, sizeof(line), "%u.%u (0x%08x)", v >> 16, v & 0xFF, v);
		LOG("SPEC %s", line);
		put("SPEC", line);
	}
	if (call(ASUS_WMI_METHODID_SFUN, 0, 0, &v)) {
		snprintf(line, sizeof(line), "0x%08x", v);
		put("SFUN", line);
	}

	unsigned present = 0;
	for (const DevName &d : kDevices) {
		bool ok = call(dstsId, d.id, 0, &v);
		bool has = ok && v != ASUS_WMI_UNSUPPORTED_METHOD && v != ~0U &&
		           (v & ASUS_WMI_DSTS_PRESENCE_BIT);
		/* Fan curve IDs return curve bytes (temperatures), not status bits. */
		if (d.id == ASUS_WMI_DEVID_CPU_FAN_CURVE || d.id == ASUS_WMI_DEVID_GPU_FAN_CURVE ||
		    d.id == ASUS_WMI_DEVID_MID_FAN_CURVE)
			has = ok && v != ASUS_WMI_UNSUPPORTED_METHOD && v != ~0U && v != 0;
		if (ok)
			snprintf(line, sizeof(line), "%s 0x%08x", has ? "present" : "absent", v);
		else
			snprintf(line, sizeof(line), "no result");
		LOG("0x%08x %-28s %s", d.id, d.name, line);
		put(d.name, line);
		present += has;
	}
	LOG("%u of %u device IDs present", present, (unsigned)(sizeof(kDevices) / sizeof(kDevices[0])));

	setProperty("AsusWMI", dict);
	dict->release();
	registerService();
	return true;
}
