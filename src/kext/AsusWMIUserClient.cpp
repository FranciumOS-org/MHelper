/* SPDX-License-Identifier: GPL-2.0 */
/* AsusWMIUserClient: the selectors in include/asus_wmi_uc.h. */
#include <IOKit/IOLib.h>
#include "AsusWMIControl.hpp"

OSDefineMetaClassAndStructors(AsusWMIUserClient, IOUserClient)

#define OWNER(t) (((AsusWMIUserClient *)(t))->owner)
#define IN(i)    ((UInt32)args->scalarInput[i])

const IOExternalMethodDispatch AsusWMIUserClient::sMethods[kAsusSelCount] = {
	/* function       scalarIn structIn scalarOut structOut */
	{ sGetInfo,       0, 0, 0, sizeof(AsusWMIInfo) },
	{ sSetKbd,        1, 0, 0, 0 },
	{ sSetRGB,        6, 0, 0, 0 },
	{ sSetRGBState,   5, 0, 0, 0 },
	{ sSetThermal,    1, 0, 0, 0 },
	{ sSetCharge,     1, 0, 0, 0 },
	{ sSetPanelOD,    1, 0, 0, 0 },
	{ sSetDGPU,       1, 0, 0, 0 },
};

bool AsusWMIUserClient::start(IOService *provider)
{
	owner = OSDynamicCast(AsusWMIControl, provider);
	return owner && IOUserClient::start(provider);
}

IOReturn AsusWMIUserClient::clientClose()
{
	terminate();
	return kIOReturnSuccess;
}

IOReturn AsusWMIUserClient::externalMethod(uint32_t selector, IOExternalMethodArguments *args,
                                           IOExternalMethodDispatch *dispatch,
                                           OSObject *target, void *reference)
{
	if (selector >= kAsusSelCount)
		return kIOReturnBadArgument;
	dispatch = (IOExternalMethodDispatch *)&sMethods[selector];
	return IOUserClient::externalMethod(selector, args, dispatch, this, reference);
}

IOReturn AsusWMIUserClient::sGetInfo(OSObject *t, void *, IOExternalMethodArguments *args)
{
	OWNER(t)->getInfo((AsusWMIInfo *)args->structureOutput);
	return kIOReturnSuccess;
}

IOReturn AsusWMIUserClient::sSetKbd(OSObject *t, void *, IOExternalMethodArguments *args)
{
	return OWNER(t)->setKbdBrightness(IN(0));
}

IOReturn AsusWMIUserClient::sSetRGB(OSObject *t, void *, IOExternalMethodArguments *args)
{
	return OWNER(t)->setRGB(IN(0), IN(1), IN(2), IN(3), IN(4), IN(5) != 0);
}

IOReturn AsusWMIUserClient::sSetRGBState(OSObject *t, void *, IOExternalMethodArguments *args)
{
	return OWNER(t)->setRGBState(IN(0), IN(1), IN(2), IN(3), IN(4));
}

IOReturn AsusWMIUserClient::sSetThermal(OSObject *t, void *, IOExternalMethodArguments *args)
{
	return OWNER(t)->setThermalPolicy(IN(0));
}

IOReturn AsusWMIUserClient::sSetCharge(OSObject *t, void *, IOExternalMethodArguments *args)
{
	return OWNER(t)->setChargeLimit(IN(0));
}

IOReturn AsusWMIUserClient::sSetPanelOD(OSObject *t, void *, IOExternalMethodArguments *args)
{
	return OWNER(t)->setPanelOD(IN(0));
}

IOReturn AsusWMIUserClient::sSetDGPU(OSObject *t, void *, IOExternalMethodArguments *args)
{
	return OWNER(t)->setDGPUDisabled(IN(0));
}
