# AsusWMIControl: ASUS laptop controls (keyboard light, fans, GPU) for macOS
#
#   make probe        build/out/AsusWMIProbe.kext (read-only survey)
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

.PHONY: all probe clean
all: probe

PROBE_SRC    := $(PROJ_ROOT)/src/probe
PROBE_OBJS   := $(BUILD_DIR)/probe/AsusWMIProbe.o $(BUILD_DIR)/probe/kmod_info.o
PROBE_BUNDLE := $(BUILD_DIR)/out/AsusWMIProbe.kext

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
	@echo "  LD   AsusWMIProbe.kext"
	@$(CXX) $(ARCH) $(MINOS) -isysroot $(SDK) -nostdlib -Xlinker -kext \
	    -L$(MKSDK)/Library/x86_64 $(PROBE_OBJS) -lkmod -lcc_kext \
	    -o $(PROBE_BUNDLE)/Contents/MacOS/AsusWMIProbe
	@codesign --force --sign - $(PROBE_BUNDLE) 2>/dev/null || true
	@echo "built $(PROBE_BUNDLE)"

clean:
	rm -rf $(BUILD_DIR)

-include $(PROBE_OBJS:.o=.d)
