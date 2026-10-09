/* SPDX-License-Identifier: GPL-2.0 */
/*
 * rogmouse: ROG mouse settings over USB HID, from user space (no kext).
 *
 * Protocol (64-byte reports on the vendor interface, usage page 0xFF01; the
 * mouse answers each command with a report that starts with the same bytes)
 * as G-Helper's app/Peripherals/Mouse/AsusMouse.cs documents it. Byte numbers
 * here are G-Helper's minus one: macOS reports carry no report-ID byte.
 *
 *   rogmouse                               read everything
 *   rogmouse dpi <slot 1-4> <dpi>          DPI of a slot
 *   rogmouse slot <1-4>                    active DPI slot
 *   rogmouse poll <125|250|500|1000>       polling rate
 *   rogmouse snap <0|1>                    angle snapping
 *   rogmouse light <logo|wheel|all> <static|breathe|cycle|react|off> [rrggbb] [brightness 0-100]
 *   rogmouse raw <hex bytes...>            send one packet, print the answer
 *
 * Every change is followed by "save" (50 03), as G-Helper does, so it stays in
 * the mouse.
 */
#include <IOKit/hid/IOHIDManager.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define REPORT 64

struct Model {
	uint16_t vid, pid;
	const char *name;
	int dpiSlots, maxDPI, minDPI, dpiStep;
	int zones;                  /* lighting zones in read order (logo, wheel, ...) */
	const char *zoneNames[3];
	uint8_t zoneIds[3];         /* zone byte in the write packet */
};

static const struct Model kModels[] = {
	{ 0x0B05, 0x1A88, "ROG Strix Impact III", 4, 12000, 100, 50,
	  2, { "logo", "wheel" }, { 0x00, 0x01 } },
};

static const struct Model *model;
static IOHIDDeviceRef dev;
static uint8_t inbuf[REPORT];
static uint8_t answer[REPORT];
static int gotAnswer;
static uint8_t want[3];
static int wantLen;

static void onReport(void *ctx, IOReturn r, void *sender, IOHIDReportType type,
                     uint32_t id, uint8_t *report, CFIndex len)
{
	(void)ctx; (void)r; (void)sender; (void)type; (void)id;
	if (len < wantLen || memcmp(report, want, wantLen) != 0)
		return;     /* something left over from earlier: keep waiting */
	memset(answer, 0, sizeof(answer));
	memcpy(answer, report, len > REPORT ? REPORT : len);
	gotAnswer = 1;
}

/* Send one command; wait for the answer that echoes its first `match` bytes. */
static int command(const uint8_t *pkt, int n, int match, uint8_t *out)
{
	uint8_t buf[REPORT] = { 0 };
	memcpy(buf, pkt, n);
	memcpy(want, buf, match);     /* from the padded buffer: pkt may be shorter */
	wantLen = match;
	for (int tries = 0; tries < 3; tries++) {
		gotAnswer = 0;
		IOReturn r = IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 0, buf, REPORT);
		if (r != kIOReturnSuccess) {
			fprintf(stderr, "write failed: 0x%x\n", r);
			return -1;
		}
		CFAbsoluteTime end = CFAbsoluteTimeGetCurrent() + 0.4;
		while (!gotAnswer && CFAbsoluteTimeGetCurrent() < end)
			CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.02, true);
		if (gotAnswer) {
			if (answer[0] == 0xFF && answer[1] == 0xAA) {
				fprintf(stderr, "the mouse refused the command (FF AA)\n");
				return -1;
			}
			if (out)
				memcpy(out, answer, REPORT);
			return 0;
		}
	}
	fprintf(stderr, "no answer from the mouse\n");
	return -1;
}

static int save(void)
{
	static const uint8_t p[] = { 0x50, 0x03 };
	return command(p, sizeof(p), 2, NULL);
}

static int openMouse(void)
{
	IOHIDManagerRef mgr = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
	CFMutableDictionaryRef m = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,
	                                                     &kCFTypeDictionaryValueCallBacks);
	int page = 0xFF01;
	CFNumberRef n = CFNumberCreate(NULL, kCFNumberIntType, &page);
	CFDictionarySetValue(m, CFSTR(kIOHIDPrimaryUsagePageKey), n);
	CFRelease(n);
	IOHIDManagerSetDeviceMatching(mgr, m);
	CFRelease(m);
	IOHIDManagerOpen(mgr, kIOHIDOptionsTypeNone);

	CFSetRef set = IOHIDManagerCopyDevices(mgr);
	if (!set) {
		fprintf(stderr, "no ROG mouse found\n");
		return -1;
	}
	CFIndex count = CFSetGetCount(set);
	const void **devs = calloc(count, sizeof(void *));
	CFSetGetValues(set, devs);
	for (CFIndex i = 0; i < count && !dev; i++) {
		IOHIDDeviceRef d = (IOHIDDeviceRef)devs[i];
		int vid = 0, pid = 0;
		CFNumberRef v = IOHIDDeviceGetProperty(d, CFSTR(kIOHIDVendorIDKey));
		CFNumberRef p = IOHIDDeviceGetProperty(d, CFSTR(kIOHIDProductIDKey));
		if (v) CFNumberGetValue(v, kCFNumberIntType, &vid);
		if (p) CFNumberGetValue(p, kCFNumberIntType, &pid);
		for (size_t k = 0; k < sizeof(kModels) / sizeof(kModels[0]); k++)
			if (kModels[k].vid == vid && kModels[k].pid == pid) {
				model = &kModels[k];
				dev = d;
			}
	}
	free(devs);
	if (!dev) {
		fprintf(stderr, "no supported ROG mouse found\n");
		return -1;
	}
	CFRetain(dev);
	CFRelease(set);
	IOReturn r = IOHIDDeviceOpen(dev, kIOHIDOptionsTypeNone);
	if (r != kIOReturnSuccess) {
		fprintf(stderr, "could not open %s: 0x%x%s\n", model->name, r,
		        r == kIOReturnNotPermitted ? " (allow Input Monitoring for this app/Terminal)" : "");
		return -1;
	}
	IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
	IOHIDDeviceRegisterInputReportCallback(dev, inbuf, sizeof(inbuf), onReport, NULL);
	return 0;
}

static const char *modeName(uint8_t m)
{
	switch (m) {
	case 0x00: return "static";
	case 0x01: return "breathe";
	case 0x02: return "cycle";
	case 0x03: return "rainbow";
	case 0x04: return "react";
	case 0x05: return "comet";
	case 0xF0: return "off";
	default:   return "?";
	}
}

static void hexdump(const char *label, const uint8_t *b)
{
	printf("  %-8s", label);
	for (int i = 0; i < 24; i++)
		printf(" %02x", b[i]);
	printf("\n");
}

static int status(int verbose)
{
	uint8_t r[REPORT];
	static const uint8_t pProfile[] = { 0x12, 0x00 };
	static const uint8_t pDPI[] = { 0x12, 0x04, 0x00 };

	printf("%s\n", model->name);
	if (command(pProfile, 2, 3, r) == 0) {
		if (verbose) hexdump("12 00", r);
		printf("  profile         %u\n", r[10]);
		printf("  DPI slot        %u\n", r[11]);
	}
	if (command(pDPI, 3, 3, r) == 0) {
		if (verbose) hexdump("12 04 00", r);
		printf("  DPI            ");
		for (int i = 0; i < model->dpiSlots; i++) {
			unsigned v = (unsigned)(r[4 + i * 2] | r[5 + i * 2] << 8);
			printf(" %u", v * model->dpiStep + model->dpiStep);
		}
		printf("\n");
		static const int rates[] = { 125, 250, 500, 1000, 2000, 4000, 8000 };
		int pr = r[12] & 0x07;
		printf("  polling         %d Hz\n", pr < 7 ? rates[pr] : 0);
		printf("  angle snapping  %s\n", r[16] == 1 ? "on" : "off");
	}
	for (int z = 0; z < model->zones; z++) {
		uint8_t p[] = { 0x12, 0x03, (uint8_t)z };
		/* the answer does not repeat the zone byte */
		if (command(p, 3, 2, r) == 0) {
			if (verbose) hexdump("12 03", r);
			printf("  light %-9s %-8s %02x%02x%02x  brightness %u\n",
			       model->zoneNames[z], modeName(r[4]), r[6], r[7], r[8], r[5]);
		}
	}
	return 0;
}

static int parseMode(const char *s, uint8_t *m)
{
	if (!strcmp(s, "static"))  { *m = 0x00; return 0; }
	if (!strcmp(s, "breathe")) { *m = 0x01; return 0; }
	if (!strcmp(s, "cycle"))   { *m = 0x02; return 0; }
	if (!strcmp(s, "react"))   { *m = 0x04; return 0; }
	if (!strcmp(s, "off"))     { *m = 0xF0; return 0; }
	return -1;
}

static int setLight(int zoneIdx, uint8_t mode, unsigned rgb, int brightness)
{
	uint8_t zone = zoneIdx < 0 ? 0x03 : model->zoneIds[zoneIdx];   /* 03 = all */
	uint8_t p[] = { 0x51, 0x28, zone, 0x00, mode, (uint8_t)brightness,
	                (uint8_t)(rgb >> 16), (uint8_t)(rgb >> 8), (uint8_t)rgb, 0, 0, 0 };
	return command(p, sizeof(p), 2, NULL);
}

static int usage(void)
{
	fprintf(stderr,
	        "usage: rogmouse [-v]                      read settings\n"
	        "       rogmouse dpi <slot 1-4> <dpi>\n"
	        "       rogmouse slot <1-4>\n"
	        "       rogmouse poll <125|250|500|1000>\n"
	        "       rogmouse snap <0|1>\n"
	        "       rogmouse light <logo|wheel|all> <static|breathe|cycle|react|off> [rrggbb] [0-100]\n"
	        "       rogmouse raw <hex bytes...>\n");
	return 2;
}

int main(int argc, char **argv)
{
	if (openMouse())
		return 1;
	if (argc < 2 || !strcmp(argv[1], "-v"))
		return status(argc >= 2);

	const char *cmd = argv[1];
	int rc;
	if (!strcmp(cmd, "dpi") && argc >= 4) {
		int slot = atoi(argv[2]), dpi = atoi(argv[3]);
		if (slot < 1 || slot > model->dpiSlots || dpi < model->minDPI || dpi > model->maxDPI ||
		    dpi % model->dpiStep) {
			fprintf(stderr, "slot 1-%d, DPI %d-%d in steps of %d\n", model->dpiSlots,
			        model->minDPI, model->maxDPI, model->dpiStep);
			return 2;
		}
		unsigned v = (unsigned)(dpi - model->dpiStep) / model->dpiStep;
		uint8_t p[] = { 0x51, 0x31, (uint8_t)(slot - 1), 0x00, (uint8_t)v, (uint8_t)(v >> 8) };
		rc = command(p, sizeof(p), 2, NULL);
	} else if (!strcmp(cmd, "slot") && argc >= 3) {
		int slot = atoi(argv[2]);
		if (slot < 1 || slot > model->dpiSlots)
			return usage();
		uint8_t p[] = { 0x51, 0x31, 0x09, 0x00, (uint8_t)slot };
		rc = command(p, sizeof(p), 2, NULL);
	} else if (!strcmp(cmd, "poll") && argc >= 3) {
		int hz = atoi(argv[2]), code;
		switch (hz) {
		case 125: code = 0; break;
		case 250: code = 1; break;
		case 500: code = 2; break;
		case 1000: code = 3; break;
		default: return usage();
		}
		uint8_t p[] = { 0x51, 0x31, 0x04, 0x00, (uint8_t)code };
		rc = command(p, sizeof(p), 2, NULL);
	} else if (!strcmp(cmd, "snap") && argc >= 3) {
		uint8_t p[] = { 0x51, 0x31, 0x06, 0x00, (uint8_t)(atoi(argv[2]) != 0) };
		rc = command(p, sizeof(p), 2, NULL);
	} else if (!strcmp(cmd, "light") && argc >= 4) {
		int zone = -2;
		if (!strcmp(argv[2], "all"))
			zone = -1;
		for (int z = 0; z < model->zones; z++)
			if (!strcmp(argv[2], model->zoneNames[z]))
				zone = z;
		uint8_t mode;
		if (zone == -2 || parseMode(argv[3], &mode))
			return usage();
		unsigned rgb = argc >= 5 ? (unsigned)strtoul(argv[4], NULL, 16) : 0xFFFFFF;
		int br = argc >= 6 ? atoi(argv[5]) : 100;
		if (br < 0 || br > 100)
			return usage();
		rc = setLight(zone, mode, rgb, br);
	} else if (!strcmp(cmd, "raw") && argc >= 3) {
		uint8_t p[REPORT] = { 0 }, r[REPORT];
		int n = 0;
		for (int i = 2; i < argc && n < REPORT; i++)
			p[n++] = (uint8_t)strtoul(argv[i], NULL, 16);
		if (command(p, n, n < 2 ? n : 2, r))
			return 1;
		hexdump("answer", r);
		return 0;
	} else {
		return usage();
	}
	if (rc == 0)
		rc = save();
	if (rc == 0)
		return status(0);
	return 1;
}
