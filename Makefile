# MHelper: ASUS laptop controls (keyboard light, fans, GPU) for macOS
#
#   make              kext + mhelper + app
#   make kext         build/out/MHelper.kext
#   make mhelper      build/out/mhelper (command-line client)
#   make app          build/out/MHelper.app (menu-bar app)
#   make probe        build/out/MHelperProbe.kext (read-only survey)
#   make clean
#
# Loading a kext is never done from here: a person runs sudo tools/load.sh.

PROJ_ROOT := .
MKSDK     := $(PROJ_ROOT)/third_party/MacKernelSDK
BUILD_DIR := $(PROJ_ROOT)/build
SDK       := $(shell xcrun --show-sdk-path 2>/dev/null)
ARCH      := -arch x86_64
MINOS     := -mmacosx-version-min=11.0
CC        := xcrun clang
CXX       := xcrun clang++

KEXT_CXXFLAGS := $(ARCH) $(MINOS) -isysroot $(SDK) -nostdinc \
                 -std=gnu++17 -O2 -mkernel -fapple-kext -fno-rtti -fno-exceptions \
                 -fno-builtin -fno-common -fno-stack-protector \
                 -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT \
                 -I$(MKSDK)/Headers -I$(PROJ_ROOT)/include -Wall -Werror -MMD -MP
KMOD_CFLAGS   := $(ARCH) $(MINOS) -isysroot $(SDK) -nostdinc -mkernel \
                 -fno-builtin -fno-common -fno-stack-protector -DKERNEL \
                 -I$(MKSDK)/Headers -Wall

.PHONY: all probe kext mhelper app release clean
all: kext mhelper app

PROBE_SRC    := $(PROJ_ROOT)/src/probe
PROBE_OBJS   := $(BUILD_DIR)/probe/AsusWMIProbe.o $(BUILD_DIR)/probe/kmod_info.o
PROBE_BUNDLE := $(BUILD_DIR)/out/MHelperProbe.kext

$(BUILD_DIR)/probe/%.o: $(PROBE_SRC)/%.cpp
	@mkdir -p $(dir $@)
	@echo "  CXX  probe/$*.cpp"
	@$(CXX) $(KEXT_CXXFLAGS) -c $< -o $@

$(BUILD_DIR)/probe/%.o: $(PROBE_SRC)/%.c
	@mkdir -p $(dir $@)
	@echo "  CC   probe/$*.c"
	@$(CC) $(KMOD_CFLAGS) -c $< -o $@

probe: $(PROBE_OBJS) $(PROBE_SRC)/Info.plist
	@rm -rf $(PROBE_BUNDLE)
	@mkdir -p $(PROBE_BUNDLE)/Contents/MacOS
	@cp $(PROBE_SRC)/Info.plist $(PROBE_BUNDLE)/Contents/Info.plist
	@echo "  LD   MHelperProbe.kext"
	@$(CXX) $(ARCH) $(MINOS) -isysroot $(SDK) -nostdlib -Xlinker -kext \
	    -L$(MKSDK)/Library/x86_64 $(PROBE_OBJS) -lkmod -lcc_kext \
	    -o $(PROBE_BUNDLE)/Contents/MacOS/MHelperProbe
	@codesign --force --sign - $(PROBE_BUNDLE) 2>/dev/null || true
	@echo "built $(PROBE_BUNDLE)"

KEXT_SRC    := $(PROJ_ROOT)/src/kext
KEXT_OBJS   := $(BUILD_DIR)/kext/AsusWMIControl.o $(BUILD_DIR)/kext/AsusWMIUserClient.o \
               $(BUILD_DIR)/kext/kmod_info.o
KEXT_BUNDLE := $(BUILD_DIR)/out/MHelper.kext

$(BUILD_DIR)/kext/%.o: $(KEXT_SRC)/%.cpp
	@mkdir -p $(dir $@)
	@echo "  CXX  kext/$*.cpp"
	@$(CXX) $(KEXT_CXXFLAGS) -c $< -o $@

$(BUILD_DIR)/kext/%.o: $(KEXT_SRC)/%.c
	@mkdir -p $(dir $@)
	@echo "  CC   kext/$*.c"
	@$(CC) $(KMOD_CFLAGS) -c $< -o $@

kext: $(KEXT_OBJS) $(KEXT_SRC)/Info.plist
	@rm -rf $(KEXT_BUNDLE)
	@mkdir -p $(KEXT_BUNDLE)/Contents/MacOS
	@cp $(KEXT_SRC)/Info.plist $(KEXT_BUNDLE)/Contents/Info.plist
	@echo "  LD   MHelper.kext"
	@$(CXX) $(ARCH) $(MINOS) -isysroot $(SDK) -nostdlib -Xlinker -kext \
	    -L$(MKSDK)/Library/x86_64 $(KEXT_OBJS) -lkmod -lcc_kext \
	    -o $(KEXT_BUNDLE)/Contents/MacOS/MHelper
	@codesign --force --sign - $(KEXT_BUNDLE) 2>/dev/null || true
	@echo "built $(KEXT_BUNDLE)"

mhelper: $(BUILD_DIR)/out/mhelper
$(BUILD_DIR)/out/mhelper: tools/mhelper.c include/asus_wmi_uc.h
	@mkdir -p $(dir $@)
	@echo "  CC   mhelper"
	@$(CC) -O2 -Wall -Werror $(MINOS) -Iinclude tools/mhelper.c -framework IOKit -framework CoreFoundation -o $@

APP_SRCS   := $(wildcard app/Sources/*.swift)
APP_BUNDLE := $(BUILD_DIR)/out/MHelper.app
app: $(APP_SRCS) app/Info.plist include/asus_wmi_uc.h
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@cp app/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@echo "  SWIFT MHelper.app"
	@xcrun swiftc -O -swift-version 5 -target x86_64-apple-macos13.0 -sdk $(SDK) \
	    -import-objc-header include/asus_wmi_uc.h $(APP_SRCS) \
	    -o $(APP_BUNDLE)/Contents/MacOS/MHelper
	@codesign --force --sign - $(APP_BUNDLE) 2>/dev/null || true
	@echo "built $(APP_BUNDLE)"

VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' app/Info.plist)
RELEASE := MHelper-$(VERSION)
REL_DIR := $(BUILD_DIR)/release/$(RELEASE)
# One folder for users: the app, the kext, how to install; the rest in Extras/.
# The .dmg adds an Applications link to drag the app onto.
release: all probe
	@rm -rf $(BUILD_DIR)/release
	@mkdir -p $(REL_DIR)/Extras
	@cp -R $(APP_BUNDLE) $(KEXT_BUNDLE) $(REL_DIR)/
	@cp "docs/How to install.txt" $(REL_DIR)/
	@cp -R $(PROBE_BUNDLE) $(REL_DIR)/Extras/
	@cp $(BUILD_DIR)/out/mhelper tools/load.sh tools/unload.sh README.md LICENSE $(REL_DIR)/Extras/
	@cd $(BUILD_DIR)/release && ditto -c -k --keepParent $(RELEASE) $(RELEASE).zip
	@echo "built $(BUILD_DIR)/release/$(RELEASE).zip"
	@ln -s /Applications $(REL_DIR)/Applications
	@hdiutil create -quiet -volname "$(RELEASE)" -srcfolder $(REL_DIR) -fs HFS+ \
	    -format UDZO -ov $(BUILD_DIR)/release/$(RELEASE).dmg
	@rm $(REL_DIR)/Applications
	@echo "built $(BUILD_DIR)/release/$(RELEASE).dmg"

clean:
	rm -rf $(BUILD_DIR)

-include $(PROBE_OBJS:.o=.d) $(KEXT_OBJS:.o=.d)
