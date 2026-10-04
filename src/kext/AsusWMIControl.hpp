/* SPDX-License-Identifier: GPL-2.0 */
#ifndef ASUS_WMI_CONTROL_HPP
#define ASUS_WMI_CONTROL_HPP

#include <IOKit/IOService.h>
#include <IOKit/IOUserClient.h>
#include <IOKit/IOLocks.h>
#include <IOKit/IOWorkLoop.h>
#include <IOKit/IOTimerEventSource.h>
#include <IOKit/acpi/IOACPIPlatformDevice.h>

#include "asus_wmi_ids.h"
#include "asus_wmi_uc.h"

/*
 * Owns the ASUS WMI method (WMNB on ATKD) next to AsusSMC. Nothing is written
 * to the firmware at load: features are detected with DSTS, and every DEVS
 * call comes from a client request or from reapplying a client's settings
 * after wake.
 */
class AsusWMIControl : public IOService {
	OSDeclareDefaultStructors(AsusWMIControl)

	IOACPIPlatformDevice *acpi = nullptr;
	IOLock *lock = nullptr;
	IOWorkLoop *workLoop = nullptr;
	IOTimerEventSource *wakeTimer = nullptr;
	IONotifier *sleepWakeNotifier = nullptr;

	char method[5] = {};
	UInt32 dstsId = ASUS_WMI_METHODID_DSTS;
	UInt32 features = 0;
	UInt32 rgbDev = 0;
	UInt32 thermalDev = 0;
	UInt32 muxDev = 0;

	/* What clients set; reapplied after wake. ASUS_UNKNOWN = never set. */
	UInt32 kbdLevel = ASUS_UNKNOWN;
	UInt32 thermalPolicy = ASUS_UNKNOWN;
	UInt32 chargeLimit = ASUS_UNKNOWN;
	UInt32 rgb[5] = { ASUS_UNKNOWN, 0, 0, 0, 0 };  /* mode r g b speed(0-2) */

	bool findMethod();
	void pickDsts();
	void detect();

	/* The WMI call; caller holds lock. False: ACPI failure or 0xFFFFFFFE. */
	bool call(UInt32 methodId, UInt32 a0, UInt32 a1, UInt32 a2, UInt32 *ret);
	bool present(UInt32 devId);
	/* Linux asus_wmi_get_devstate_bits with STATUS_BIT: 0/1, or -1 */
	int status(UInt32 devId);
	UInt32 fanRPM(UInt32 devId);

	IOReturn setRGBLocked(UInt32 mode, UInt32 r, UInt32 g, UInt32 b, UInt32 speed, bool save);
	IOReturn setThermalLocked(UInt32 policy);
	IOReturn setChargeLocked(UInt32 percent);
	IOReturn setKbdLocked(UInt32 level);

	static IOReturn sleepWakeHandler(void *target, void *refCon, UInt32 messageType,
	                                 IOService *provider, void *arg, vm_size_t argSize);
	static void wakeTimerFired(OSObject *owner, IOTimerEventSource *sender);
	void reapply();

public:
	bool start(IOService *provider) override;
	void stop(IOService *provider) override;
	void free() override;

	/* Called by AsusWMIUserClient */
	void getInfo(AsusWMIInfo *info);
	IOReturn setKbdBrightness(UInt32 level);
	IOReturn setRGB(UInt32 mode, UInt32 r, UInt32 g, UInt32 b, UInt32 speed, bool save);
	IOReturn setRGBState(bool boot, bool awake, bool sleep, bool keyboard, bool save);
	IOReturn setThermalPolicy(UInt32 policy);
	IOReturn setChargeLimit(UInt32 percent);
	IOReturn setPanelOD(UInt32 on);
	IOReturn setDGPUDisabled(UInt32 disable);
};

class AsusWMIUserClient : public IOUserClient {
	OSDeclareDefaultStructors(AsusWMIUserClient)

	AsusWMIControl *owner = nullptr;

	static IOReturn sGetInfo(OSObject *, void *, IOExternalMethodArguments *);
	static IOReturn sSetKbd(OSObject *, void *, IOExternalMethodArguments *);
	static IOReturn sSetRGB(OSObject *, void *, IOExternalMethodArguments *);
	static IOReturn sSetRGBState(OSObject *, void *, IOExternalMethodArguments *);
	static IOReturn sSetThermal(OSObject *, void *, IOExternalMethodArguments *);
	static IOReturn sSetCharge(OSObject *, void *, IOExternalMethodArguments *);
	static IOReturn sSetPanelOD(OSObject *, void *, IOExternalMethodArguments *);
	static IOReturn sSetDGPU(OSObject *, void *, IOExternalMethodArguments *);
	static const IOExternalMethodDispatch sMethods[kAsusSelCount];

public:
	bool start(IOService *provider) override;
	IOReturn clientClose() override;
	IOReturn externalMethod(uint32_t selector, IOExternalMethodArguments *args,
	                        IOExternalMethodDispatch *dispatch, OSObject *target,
	                        void *reference) override;
};

#endif
