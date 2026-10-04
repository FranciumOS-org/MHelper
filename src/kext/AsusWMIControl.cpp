/* SPDX-License-Identifier: GPL-2.0 */
/*
 * AsusWMIControl: ASUS laptop controls through the firmware's WMI method.
 *
 * Protocol (IDs, argument packing, result checks) follows Linux
 * drivers/platform/x86/asus-wmi.c; the code is our own.
 */
#include <IOKit/IOLib.h>
#include <IOKit/IOMessage.h>
#include <IOKit/pwr_mgt/RootDomain.h>
#include <libkern/c++/OSData.h>
#include <libkern/c++/OSNumber.h>
#include <libkern/c++/OSString.h>

#include "AsusWMIControl.hpp"

#define LOG(fmt, ...) IOLog("AsusWMIControl: " fmt "\n", ##__VA_ARGS__)

#define ASUS_WMI_DSTS_UNKNOWN_BIT 0x00000002

struct BiosArgs { UInt32 arg[6]; } __attribute__((packed));

struct WdgBlock {
	UInt8 guid[16];
	char  object_id[2];
	UInt8 instance_count;
	UInt8 flags;
} __attribute__((packed));
static_assert(sizeof(WdgBlock) == 20, "_WDG entries are 20 bytes");

static const UInt8 kMgmtGuid[16] = {
	0xD0, 0x5E, 0x84, 0x97, 0x6D, 0x4E, 0xDE, 0x11,
	0x8A, 0x39, 0x08, 0x00, 0x20, 0x0C, 0x9A, 0x66,
};

OSDefineMetaClassAndStructors(AsusWMIControl, IOService)

/* ------------------------------------------------------------------ */
/* WMI                                                                 */
/* ------------------------------------------------------------------ */

bool AsusWMIControl::findMethod()
{
	OSObject *obj = nullptr;
	if (acpi->evaluateObject("_WDG", &obj) != kIOReturnSuccess || !obj)
		return false;
	bool found = false;
	if (OSData *wdg = OSDynamicCast(OSData, obj)) {
		const WdgBlock *b = (const WdgBlock *)wdg->getBytesNoCopy();
		unsigned n = wdg->getLength() / sizeof(WdgBlock);
		for (unsigned i = 0; i < n && !found; i++) {
			if (memcmp(b[i].guid, kMgmtGuid, sizeof(kMgmtGuid)) || !(b[i].flags & 0x2))
				continue;
			method[0] = 'W';
			method[1] = 'M';
			method[2] = b[i].object_id[0];
			method[3] = b[i].object_id[1];
			found = acpi->validateObject(method) == kIOReturnSuccess;
		}
	}
	obj->release();
	return found;
}

void AsusWMIControl::pickDsts()
{
	OSObject *obj = nullptr;
	if (acpi->evaluateObject("_UID", &obj) != kIOReturnSuccess || !obj)
		return;
	if (OSString *s = OSDynamicCast(OSString, obj))
		if (s->isEqualTo("ASUSWMI"))
			dstsId = ASUS_WMI_METHODID_DCTS;
	obj->release();
}

bool AsusWMIControl::call(UInt32 methodId, UInt32 a0, UInt32 a1, UInt32 a2, UInt32 *ret)
{
	BiosArgs args = {};
	args.arg[0] = a0;
	args.arg[1] = a1;
	args.arg[2] = a2;

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

	/* Like Linux asus_wmi_evaluate_method3: a result that is not an
	 * integer reads as 0; only an ACPI failure or 0xFFFFFFFE is an error. */
	UInt32 v = 0;
	if (rc == kIOReturnSuccess && result) {
		if (OSNumber *n = OSDynamicCast(OSNumber, result))
			v = n->unsigned32BitValue();
		else if (OSData *d = OSDynamicCast(OSData, result))
			if (d->getLength() >= 4)
				memcpy(&v, d->getBytesNoCopy(), 4);
	}
	if (result)
		result->release();
	if (ret)
		*ret = v;
	return rc == kIOReturnSuccess && v != ASUS_WMI_UNSUPPORTED_METHOD;
}

bool AsusWMIControl::present(UInt32 devId)
{
	UInt32 v;
	return call(dstsId, devId, 0, 0, &v) && v != ~0U && (v & ASUS_WMI_DSTS_PRESENCE_BIT);
}

int AsusWMIControl::status(UInt32 devId)
{
	UInt32 v;
	if (!call(dstsId, devId, 0, 0, &v) || v == ~0U || !(v & ASUS_WMI_DSTS_PRESENCE_BIT) ||
	    (v & ASUS_WMI_DSTS_UNKNOWN_BIT))
		return -1;
	return v & ASUS_WMI_DSTS_STATUS_BIT;
}

UInt32 AsusWMIControl::fanRPM(UInt32 devId)
{
	UInt32 v;
	if (!call(dstsId, devId, 0, 0, &v) || v == ~0U || !(v & ASUS_WMI_DSTS_PRESENCE_BIT))
		return ASUS_UNKNOWN;
	return (v & 0xFFFF) * 100;
}

void AsusWMIControl::detect()
{
	IOLockLock(lock);
	if (present(ASUS_WMI_DEVID_KBD_BACKLIGHT))
		features |= kAsusFeatKbdBacklight;
	if (present(ASUS_WMI_DEVID_TUF_RGB_MODE))
		rgbDev = ASUS_WMI_DEVID_TUF_RGB_MODE;
	else if (present(ASUS_WMI_DEVID_TUF_RGB_MODE2))
		rgbDev = ASUS_WMI_DEVID_TUF_RGB_MODE2;
	if (rgbDev)
		features |= kAsusFeatRGB;
	if (present(ASUS_WMI_DEVID_TUF_RGB_STATE))
		features |= kAsusFeatRGBState;
	if (present(ASUS_WMI_DEVID_THROTTLE_THERMAL_POLICY)) {
		thermalDev = ASUS_WMI_DEVID_THROTTLE_THERMAL_POLICY;
		features |= kAsusFeatThermal;
	} else if (present(ASUS_WMI_DEVID_THROTTLE_THERMAL_POLICY_VIVO)) {
		thermalDev = ASUS_WMI_DEVID_THROTTLE_THERMAL_POLICY_VIVO;
		features |= kAsusFeatThermal | kAsusFeatThermalVivo;
	}
	if (present(ASUS_WMI_DEVID_CPU_FAN_CTRL))
		features |= kAsusFeatCPUFan;
	if (present(ASUS_WMI_DEVID_GPU_FAN_CTRL))
		features |= kAsusFeatGPUFan;
	if (present(ASUS_WMI_DEVID_RSOC))
		features |= kAsusFeatChargeLimit;
	if (present(ASUS_WMI_DEVID_PANEL_OD))
		features |= kAsusFeatPanelOD;
	if (present(ASUS_WMI_DEVID_DGPU))
		features |= kAsusFeatDGPU;
	if (present(ASUS_WMI_DEVID_GPU_MUX))
		muxDev = ASUS_WMI_DEVID_GPU_MUX;
	else if (present(ASUS_WMI_DEVID_GPU_MUX_VIVO))
		muxDev = ASUS_WMI_DEVID_GPU_MUX_VIVO;
	if (muxDev)
		features |= kAsusFeatGPUMux;
	IOLockUnlock(lock);
}

/* ------------------------------------------------------------------ */
/* Lifecycle                                                           */
/* ------------------------------------------------------------------ */

bool AsusWMIControl::start(IOService *provider)
{
	acpi = OSDynamicCast(IOACPIPlatformDevice, provider);
	if (!acpi || !findMethod())
		return false;   /* another PNP0C14 device */
	if (!IOService::start(provider))
		return false;

	lock = IOLockAlloc();
	workLoop = IOWorkLoop::workLoop();
	if (workLoop)
		wakeTimer = IOTimerEventSource::timerEventSource(this, wakeTimerFired);
	if (!lock || !workLoop || !wakeTimer ||
	    workLoop->addEventSource(wakeTimer) != kIOReturnSuccess) {
		LOG("out of memory");
		stop(provider);
		return false;
	}

	pickDsts();
	detect();
	LOG("%s on %s, %s, features 0x%x", method, provider->getName(),
	    dstsId == ASUS_WMI_METHODID_DCTS ? "DCTS" : "DSTS", features);

	setProperty("Features", features, 32);
	sleepWakeNotifier = registerPrioritySleepWakeInterest(sleepWakeHandler, this);
	registerService();
	return true;
}

void AsusWMIControl::stop(IOService *provider)
{
	if (sleepWakeNotifier) {
		sleepWakeNotifier->remove();
		sleepWakeNotifier = nullptr;
	}
	if (wakeTimer) {
		wakeTimer->cancelTimeout();
		if (workLoop)
			workLoop->removeEventSource(wakeTimer);
		wakeTimer->release();
		wakeTimer = nullptr;
	}
	IOService::stop(provider);
}

void AsusWMIControl::free()
{
	if (workLoop) {
		workLoop->release();
		workLoop = nullptr;
	}
	if (lock) {
		IOLockFree(lock);
		lock = nullptr;
	}
	IOService::free();
}

IOReturn AsusWMIControl::sleepWakeHandler(void *target, void *, UInt32 messageType,
                                          IOService *, void *, vm_size_t)
{
	AsusWMIControl *self = (AsusWMIControl *)target;
	/* Out of the power-management path: the firmware wants a moment after wake. */
	if (messageType == kIOMessageSystemHasPoweredOn && self->wakeTimer)
		self->wakeTimer->setTimeoutMS(1500);
	return kIOReturnSuccess;
}

void AsusWMIControl::wakeTimerFired(OSObject *owner, IOTimerEventSource *)
{
	((AsusWMIControl *)owner)->reapply();
}

/* Only what a client set; a fresh load writes nothing. */
void AsusWMIControl::reapply()
{
	IOLockLock(lock);
	if (rgb[0] != ASUS_UNKNOWN)
		setRGBLocked(rgb[0], rgb[1], rgb[2], rgb[3], rgb[4], false);
	if (kbdLevel != ASUS_UNKNOWN)
		setKbdLocked(kbdLevel);
	if (thermalPolicy != ASUS_UNKNOWN)
		setThermalLocked(thermalPolicy);
	if (chargeLimit != ASUS_UNKNOWN)
		setChargeLocked(chargeLimit);
	IOLockUnlock(lock);
	LOG("settings reapplied after wake");
}

/* ------------------------------------------------------------------ */
/* Features                                                            */
/* ------------------------------------------------------------------ */

void AsusWMIControl::getInfo(AsusWMIInfo *info)
{
	bzero(info, sizeof(*info));
	info->version = 1;
	IOLockLock(lock);
	info->features = features;

	info->kbdLevel = ASUS_UNKNOWN;
	if (features & kAsusFeatKbdBacklight) {
		/* bits 0-2 level, bit 7 on; 0x8000 is "unknown" (Linux kbd_led_read) */
		UInt32 v;
		if (call(dstsId, ASUS_WMI_DEVID_KBD_BACKLIGHT, 0, 0, &v) &&
		    (v & ASUS_WMI_DSTS_PRESENCE_BIT))
			info->kbdLevel = ((v & 0xFFFF) == 0x8000) ? 0 : (v & 0x7);
	}
	info->thermalPolicy = thermalPolicy;
	info->chargeLimit = chargeLimit;

	int s;
	info->panelOD = (features & kAsusFeatPanelOD) && (s = status(ASUS_WMI_DEVID_PANEL_OD)) >= 0
	                ? (UInt32)s : ASUS_UNKNOWN;
	info->dgpuDisabled = (features & kAsusFeatDGPU) && (s = status(ASUS_WMI_DEVID_DGPU)) >= 0
	                     ? (UInt32)s : ASUS_UNKNOWN;
	info->gpuMux = muxDev && (s = status(muxDev)) >= 0 ? (UInt32)s : ASUS_UNKNOWN;
	info->cpuFanRPM = (features & kAsusFeatCPUFan) ? fanRPM(ASUS_WMI_DEVID_CPU_FAN_CTRL) : ASUS_UNKNOWN;
	info->gpuFanRPM = (features & kAsusFeatGPUFan) ? fanRPM(ASUS_WMI_DEVID_GPU_FAN_CTRL) : ASUS_UNKNOWN;

	info->rgbMode = rgb[0];
	info->rgbR = rgb[1];
	info->rgbG = rgb[2];
	info->rgbB = rgb[3];
	info->rgbSpeed = rgb[4];
	IOLockUnlock(lock);
}

IOReturn AsusWMIControl::setKbdLocked(UInt32 level)
{
	UInt32 ret;
	/* DEVS returns 0 on some machines; only a failed call counts. */
	if (!call(ASUS_WMI_METHODID_DEVS, ASUS_WMI_DEVID_KBD_BACKLIGHT, 0x80 | level, 0, &ret))
		return kIOReturnIOError;
	return kIOReturnSuccess;
}

IOReturn AsusWMIControl::setKbdBrightness(UInt32 level)
{
	if (!(features & kAsusFeatKbdBacklight))
		return kIOReturnUnsupported;
	if (level > 3)
		return kIOReturnBadArgument;
	IOLockLock(lock);
	IOReturn rc = setKbdLocked(level);
	if (rc == kIOReturnSuccess)
		kbdLevel = level;
	IOLockUnlock(lock);
	return rc;
}

/* Linux kbd_rgb_mode_store */
IOReturn AsusWMIControl::setRGBLocked(UInt32 mode, UInt32 r, UInt32 g, UInt32 b,
                                      UInt32 speed, bool save)
{
	static const UInt8 speeds[3] = { 0xe1, 0xeb, 0xf5 };
	UInt32 cmd = save ? 0xb4 : 0xb3;
	if (mode >= 12 || mode == 9)
		mode = 10;
	UInt32 a1 = cmd | (mode << 8) | (r << 16) | (g << 24);
	UInt32 a2 = b | ((UInt32)speeds[speed] << 8);
	if (!call(ASUS_WMI_METHODID_DEVS, rgbDev, a1, a2, nullptr))
		return kIOReturnIOError;
	return kIOReturnSuccess;
}

IOReturn AsusWMIControl::setRGB(UInt32 mode, UInt32 r, UInt32 g, UInt32 b, UInt32 speed, bool save)
{
	if (!(features & kAsusFeatRGB))
		return kIOReturnUnsupported;
	if (r > 255 || g > 255 || b > 255 || speed > 2 || mode > 255)
		return kIOReturnBadArgument;
	IOLockLock(lock);
	IOReturn rc = setRGBLocked(mode, r, g, b, speed, save);
	if (rc == kIOReturnSuccess) {
		rgb[0] = mode;
		rgb[1] = r;
		rgb[2] = g;
		rgb[3] = b;
		rgb[4] = speed;
	}
	IOLockUnlock(lock);
	return rc;
}

/* Linux kbd_rgb_state_store: 0xbd is required in the low byte */
IOReturn AsusWMIControl::setRGBState(bool boot, bool awake, bool sleep, bool keyboard, bool save)
{
	if (!(features & kAsusFeatRGBState))
		return kIOReturnUnsupported;
	UInt32 flags = (boot ? 1u << 1 : 0) | (awake ? 1u << 3 : 0) |
	               (sleep ? 1u << 5 : 0) | (keyboard ? 1u << 7 : 0);
	UInt32 cmd = save ? 1u << 2 : 0;
	IOLockLock(lock);
	bool ok = call(ASUS_WMI_METHODID_DEVS, ASUS_WMI_DEVID_TUF_RGB_STATE,
	               0xbd | (cmd << 8) | (flags << 16), 0, nullptr);
	IOLockUnlock(lock);
	return ok ? kIOReturnSuccess : kIOReturnIOError;
}

IOReturn AsusWMIControl::setThermalLocked(UInt32 policy)
{
	UInt32 value = policy;
	if (thermalDev == ASUS_WMI_DEVID_THROTTLE_THERMAL_POLICY_VIVO) {
		static const UInt32 vivo[3] = {
			ASUS_THERMAL_POLICY_BALANCED_VIVO,
			ASUS_THERMAL_POLICY_TURBO_VIVO,
			ASUS_THERMAL_POLICY_SILENT_VIVO,
		};
		value = vivo[policy];
	}
	/* Some machines return no result code; Linux ignores it too. */
	if (!call(ASUS_WMI_METHODID_DEVS, thermalDev, value, 0, nullptr))
		return kIOReturnIOError;
	return kIOReturnSuccess;
}

IOReturn AsusWMIControl::setThermalPolicy(UInt32 policy)
{
	if (!(features & kAsusFeatThermal))
		return kIOReturnUnsupported;
	if (policy > ASUS_POLICY_SILENT)
		return kIOReturnBadArgument;
	IOLockLock(lock);
	IOReturn rc = setThermalLocked(policy);
	if (rc == kIOReturnSuccess)
		thermalPolicy = policy;
	IOLockUnlock(lock);
	return rc;
}

IOReturn AsusWMIControl::setChargeLocked(UInt32 percent)
{
	UInt32 ret;
	if (!call(ASUS_WMI_METHODID_DEVS, ASUS_WMI_DEVID_RSOC, percent, 0, &ret) || ret != 1)
		return kIOReturnIOError;
	return kIOReturnSuccess;
}

IOReturn AsusWMIControl::setChargeLimit(UInt32 percent)
{
	if (!(features & kAsusFeatChargeLimit))
		return kIOReturnUnsupported;
	if (percent < 20 || percent > 100)
		return kIOReturnBadArgument;
	IOLockLock(lock);
	IOReturn rc = setChargeLocked(percent);
	if (rc == kIOReturnSuccess)
		chargeLimit = percent;
	IOLockUnlock(lock);
	return rc;
}

IOReturn AsusWMIControl::setPanelOD(UInt32 on)
{
	if (!(features & kAsusFeatPanelOD))
		return kIOReturnUnsupported;
	if (on > 1)
		return kIOReturnBadArgument;
	UInt32 ret;
	IOLockLock(lock);
	bool ok = call(ASUS_WMI_METHODID_DEVS, ASUS_WMI_DEVID_PANEL_OD, on, 0, &ret) && ret <= 1;
	IOLockUnlock(lock);
	return ok ? kIOReturnSuccess : kIOReturnIOError;
}

/* Linux dgpu_disable_store: never disable the dGPU while the MUX is in dGPU mode. */
IOReturn AsusWMIControl::setDGPUDisabled(UInt32 disable)
{
	if (!(features & kAsusFeatDGPU))
		return kIOReturnUnsupported;
	if (disable > 1)
		return kIOReturnBadArgument;
	IOLockLock(lock);
	IOReturn rc = kIOReturnSuccess;
	if (muxDev) {
		int mux = status(muxDev);
		if (mux < 0)
			rc = kIOReturnIOError;
		else if (mux == 0 && disable)
			rc = kIOReturnNotPermitted;
	}
	if (rc == kIOReturnSuccess) {
		UInt32 ret;
		if (!call(ASUS_WMI_METHODID_DEVS, ASUS_WMI_DEVID_DGPU, disable, 0, &ret) || ret > 1)
			rc = kIOReturnIOError;
	}
	IOLockUnlock(lock);
	if (rc == kIOReturnSuccess)
		LOG("dGPU %s", disable ? "disabled (Eco)" : "enabled");
	return rc;
}
