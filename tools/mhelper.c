/* SPDX-License-Identifier: GPL-2.0 */
/*
 * mhelper: command-line client for MHelper.kext.
 *
 *   mhelper                           status
 *   mhelper kbd <0-3>                 keyboard brightness
 *   mhelper color <rrggbb> [mode] [speed] [--save]
 *                                     mode: static|breathe|cycle|strobe (or 0-11)
 *                                     speed: 0-2 (slow-fast); --save keeps it in firmware
 *   mhelper lights <boot> <awake> <sleep> <keyboard> [--save]   (each 0/1)
 *   mhelper mode <silent|balanced|turbo>
 *   mhelper charge <20-100>
 *   mhelper overdrive <0|1>
 *   mhelper eco <0|1>                 1 = dGPU off
 */
#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "asus_wmi_uc.h"

static io_connect_t conn;

static int open_service(void)
{
	io_service_t svc = IOServiceGetMatchingService(MACH_PORT_NULL,
	                                               IOServiceMatching(ASUS_WMI_SERVICE_CLASS));
	if (!svc) {
		fprintf(stderr, "MHelper.kext is not loaded\n");
		return -1;
	}
	kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &conn);
	IOObjectRelease(svc);
	if (kr != KERN_SUCCESS) {
		fprintf(stderr, "IOServiceOpen: 0x%x\n", kr);
		return -1;
	}
	return 0;
}

static int scalar(uint32_t sel, const uint64_t *in, uint32_t n)
{
	kern_return_t kr = IOConnectCallScalarMethod(conn, sel, in, n, NULL, NULL);
	switch (kr) {
	case KERN_SUCCESS:           return 0;
	case kIOReturnUnsupported:   fprintf(stderr, "not supported on this laptop\n"); break;
	case kIOReturnBadArgument:   fprintf(stderr, "value out of range\n"); break;
	case kIOReturnNotPermitted:  fprintf(stderr, "refused: the GPU MUX is in dGPU-only mode\n"); break;
	default:                     fprintf(stderr, "firmware call failed: 0x%x\n", kr); break;
	}
	return 1;
}

static void val(const char *name, uint32_t v, const char *unit)
{
	if (v == ASUS_UNKNOWN)
		printf("  %-18s -\n", name);
	else
		printf("  %-18s %u%s\n", name, v, unit);
}

static int status(void)
{
	struct AsusWMIInfo info;
	size_t size = sizeof(info);
	kern_return_t kr = IOConnectCallStructMethod(conn, kAsusSelGetInfo, NULL, 0, &info, &size);
	if (kr != KERN_SUCCESS) {
		fprintf(stderr, "GetInfo: 0x%x\n", kr);
		return 1;
	}
	static const char *policies[] = { "balanced", "turbo", "silent" };
	uint32_t f = info.features;
	printf("features 0x%x\n", f);
	if (f & kAsusFeatKbdBacklight) val("keyboard level", info.kbdLevel, "");
	if (f & kAsusFeatRGB) {
		if (info.rgbMode == ASUS_UNKNOWN)
			printf("  %-18s not set since load\n", "color");
		else
			printf("  %-18s %02x%02x%02x mode %u speed %u\n", "color",
			       info.rgbR, info.rgbG, info.rgbB, info.rgbMode, info.rgbSpeed);
	}
	if (f & kAsusFeatThermal)
		printf("  %-18s %s\n", "mode", info.thermalPolicy < 3 ? policies[info.thermalPolicy]
		                                                       : "not set since load");
	if (f & kAsusFeatCPUFan) val("CPU fan", info.cpuFanRPM, " rpm");
	if (f & kAsusFeatGPUFan) val("GPU fan", info.gpuFanRPM, " rpm");
	if (f & kAsusFeatChargeLimit) val("charge limit", info.chargeLimit, "%");
	if (f & kAsusFeatPanelOD) val("panel overdrive", info.panelOD, "");
	if (f & kAsusFeatDGPU) val("dGPU disabled", info.dgpuDisabled, "");
	if (f & kAsusFeatGPUMux)
		printf("  %-18s %s\n", "GPU MUX", info.gpuMux == 1 ? "hybrid" :
		                                  info.gpuMux == 0 ? "dGPU only" : "-");
	return 0;
}

static int has_save(int argc, char **argv)
{
	for (int i = 0; i < argc; i++)
		if (!strcmp(argv[i], "--save"))
			return 1;
	return 0;
}

static int usage(void)
{
	fprintf(stderr,
	        "usage: mhelper [kbd 0-3 | color rrggbb [static|breathe|cycle|strobe] [0-2] [--save] |\n"
	        "                lights boot awake sleep keyboard [--save] |\n"
	        "                mode silent|balanced|turbo | charge 20-100 | overdrive 0|1 | eco 0|1]\n");
	return 2;
}

int main(int argc, char **argv)
{
	if (open_service())
		return 1;
	if (argc < 2)
		return status();

	const char *cmd = argv[1];
	uint64_t in[6] = { 0 };

	if (!strcmp(cmd, "kbd") && argc >= 3) {
		in[0] = strtoul(argv[2], NULL, 0);
		return scalar(kAsusSelSetKbdBrightness, in, 1);
	}
	if (!strcmp(cmd, "color") && argc >= 3) {
		unsigned long rgb = strtoul(argv[2], NULL, 16);
		uint64_t mode = 0, speed = 1;
		if (argc >= 4 && strcmp(argv[3], "--save")) {
			if (!strcmp(argv[3], "static"))       mode = 0;
			else if (!strcmp(argv[3], "breathe")) mode = 1;
			else if (!strcmp(argv[3], "cycle"))   mode = 2;
			else if (!strcmp(argv[3], "strobe"))  mode = 10;
			else                                  mode = strtoul(argv[3], NULL, 0);
		}
		if (argc >= 5 && strcmp(argv[4], "--save"))
			speed = strtoul(argv[4], NULL, 0);
		in[0] = mode;
		in[1] = (rgb >> 16) & 0xff;
		in[2] = (rgb >> 8) & 0xff;
		in[3] = rgb & 0xff;
		in[4] = speed;
		in[5] = has_save(argc, argv);
		return scalar(kAsusSelSetRGB, in, 6);
	}
	if (!strcmp(cmd, "lights") && argc >= 6) {
		for (int i = 0; i < 4; i++)
			in[i] = strtoul(argv[2 + i], NULL, 0) != 0;
		in[4] = has_save(argc, argv);
		return scalar(kAsusSelSetRGBState, in, 5);
	}
	if (!strcmp(cmd, "mode") && argc >= 3) {
		if (!strcmp(argv[2], "balanced"))    in[0] = ASUS_POLICY_BALANCED;
		else if (!strcmp(argv[2], "turbo"))  in[0] = ASUS_POLICY_TURBO;
		else if (!strcmp(argv[2], "silent")) in[0] = ASUS_POLICY_SILENT;
		else return usage();
		return scalar(kAsusSelSetThermalPolicy, in, 1);
	}
	if (!strcmp(cmd, "charge") && argc >= 3) {
		in[0] = strtoul(argv[2], NULL, 0);
		return scalar(kAsusSelSetChargeLimit, in, 1);
	}
	if (!strcmp(cmd, "overdrive") && argc >= 3) {
		in[0] = strtoul(argv[2], NULL, 0);
		return scalar(kAsusSelSetPanelOD, in, 1);
	}
	if (!strcmp(cmd, "eco") && argc >= 3) {
		in[0] = strtoul(argv[2], NULL, 0);
		return scalar(kAsusSelSetDGPUDisabled, in, 1);
	}
	return usage();
}
