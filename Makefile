
OPENOCD           ?= openocd
OPENOCD_INTERFACE ?= interface/stlink.cfg
OPENOCD_CMDS      ?=

PYTHON            ?= python3
DFU_UTIL          ?= dfu-util

CLOAD_SCRIPT      ?= $(PYTHON) -m cfloader
CLOAD_CMDS        ?=
CLOAD_ARGS        ?=

ARCH := stm32f4
SRCARCH := stm32f4

ARCH_CFLAGS += -mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16
ARCH_CFLAGS += -fno-math-errno -DARM_MATH_CM4 -D__FPU_PRESENT=1 -mfp16-format=ieee
ARCH_CFLAGS += -Wno-address-of-packed-member
ARCH_CFLAGS += -DSTM32F4XX -DSTM32F40_41xxx -DHSE_VALUE=8000000 -DUSE_STDPERIPH_DRIVER

FREERTOS = $(srctree)/vendor/FreeRTOS
PORT = $(FREERTOS)/portable/GCC/ARM_CM4F
LIB = $(srctree)/src/lib
PROCESSOR = -mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16
PROG = cf2
LINKER_DIR = $(srctree)/tools/make/F405/linker

LDFLAGS += --specs=nosys.specs --specs=nano.specs $(PROCESSOR)
image_LDFLAGS += -Wl,-Map=$(PROG).map,--cref,--gc-sections,--undefined=uxTopUsedPriority
image_LDFLAGS += -L$(srctree)/tools/make/F405/linker
image_LDFLAGS += -T $(LINKER_DIR)/FLASH_CLOAD.ld

INCLUDES += -I$(srctree)/vendor/CMSIS/CMSIS/Core/Include -I$(srctree)/vendor/CMSIS/CMSIS/DSP/Include
INCLUDES += -I$(srctree)/vendor/libdw1000/inc
INCLUDES += -I$(FREERTOS)/include -I$(PORT)
INCLUDES += -I$(srctree)/src/config
INCLUDES += -I$(srctree)/src/platform
INCLUDES += -I$(srctree)/src/deck/interface -I$(srctree)/src/deck/drivers/interface
INCLUDES += -I$(srctree)/src/drivers/interface -I$(srctree)/src/drivers/bosch/interface
INCLUDES += -I$(srctree)/src/hal/interface
INCLUDES += -I$(srctree)/src/modules/interface -I$(srctree)/src/modules/interface/kalman_core -I$(srctree)/src/modules/interface/lighthouse
INCLUDES += -I$(srctree)/src/utils/interface -I$(srctree)/src/utils/interface/kve -I$(srctree)/src/utils/interface/lighthouse -I$(srctree)/src/utils/interface/tdoa
INCLUDES += -I$(LIB)/FatFS
INCLUDES += -I$(LIB)/CMSIS/STM32F4xx/Include
INCLUDES += -I$(LIB)/STM32_USB_Device_Library/Core/inc
INCLUDES += -I$(LIB)/STM32_USB_OTG_Driver/inc
INCLUDES += -I$(LIB)/STM32F4xx_StdPeriph_Driver/inc
INCLUDES += -I$(LIB)/vl53l1 -I$(LIB)/vl53l1/core/inc
INCLUDES += -I$(srctree)/include/generated

# Here we tell Kbuild where to look for Kbuild files which will tell the
# buildsystem which sources to build
objs-y += src
objs-y += vendor

# This is for building libmath_arm.a
libs-y += vendor

PLATFORM  ?= cf2
PROG ?= $(PLATFORM)

MEM_SIZE_FLASH_K = 1008
MEM_SIZE_RAM_K = 128
MEM_SIZE_CCM_K = 64

-include include/config/auto.conf

ifeq ($(CONFIG_PLATFORM_CF2),y)
PLATFORM="CF2 platform"
endif

ifeq ($(CONFIG_PLATFORM_TAG),y)
PLATFORM="Tag platform"
endif

ifdef CONFIG_DEBUG
ARCH_CFLAGS	+= -Os -Wconversion
else
ARCH_CFLAGS   += -Os -Werror
endif

all: src/utils/src/version.c $(PROG).hex $(PROG).bin
	@echo "Build for the $(PLATFORM)!"
	@$(PYTHON) $(srctree)/tools/make/versionTemplate.py --crazyflie-base $(srctree) --print-version
	@$(PYTHON) $(srctree)/tools/make/size.py $(SIZE) $(PROG).elf $(MEM_SIZE_FLASH_K) $(MEM_SIZE_RAM_K) $(MEM_SIZE_CCM_K)

include tools/make/targets.mk

check_config:
	[ -e .config ] || $(MAKE) -C $(srctree) defconfig

size:
	@$(PYTHON) $(srctree)/tools/make/size.py $(SIZE) $(PROG).elf $(MEM_SIZE_FLASH_K) $(MEM_SIZE_RAM_K) $(MEM_SIZE_CCM_K)

# Radio bootloader
CLOAD ?= 1
cload:
ifeq ($(CLOAD), 1)
	$(CLOAD_SCRIPT) $(CLOAD_CMDS) flash $(CLOAD_ARGS) $(PROG).bin stm32-fw
else
	@echo "Only cload build can be bootloaded. Launch build and cload with CLOAD=1"
endif

#Flash the stm.
flash:
	$(OPENOCD) -d2 -f $(OPENOCD_INTERFACE) $(OPENOCD_CMDS) -f $(OPENOCD_TARGET) -c init -c targets -c "reset halt" \
                 -c "flash write_image erase $(PROG).bin $(LOAD_ADDRESS) bin" \
                 -c "verify_image $(PROG).bin $(LOAD_ADDRESS) bin" -c "reset run" -c shutdown

#verify only
flash_verify:
	$(OPENOCD) -d2 -f $(OPENOCD_INTERFACE) $(OPENOCD_CMDS) -f $(OPENOCD_TARGET) -c init -c targets -c "reset halt" \
                 -c "verify_image $(PROG).bin $(LOAD_ADDRESS) bin" -c "reset run" -c shutdown

flash_dfu:
	$(DFU_UTIL) -a 0 -D $(PROG).dfu

#STM utility targets
halt:
	$(OPENOCD) -d0 -f $(OPENOCD_INTERFACE) $(OPENOCD_CMDS) -f $(OPENOCD_TARGET) -c init -c targets -c "halt" -c shutdown

reset:
	$(OPENOCD) -d0 -f $(OPENOCD_INTERFACE) $(OPENOCD_CMDS) -f $(OPENOCD_TARGET) -c init -c targets -c "reset" -c shutdown

openocd:
	$(OPENOCD) -d2 -f $(OPENOCD_INTERFACE) $(OPENOCD_CMDS) -f $(OPENOCD_TARGET) -c init -c targets -c "\$$_TARGETNAME configure -rtos auto"

trace:
	$(OPENOCD) -d2 -f $(OPENOCD_INTERFACE) $(OPENOCD_CMDS) -f $(OPENOCD_TARGET) -c init -c targets -f tools/trace/enable_trace.cfg

rtt:
	$(OPENOCD) -d2 -f $(OPENOCD_INTERFACE) $(OPENOCD_CMDS) -f $(OPENOCD_TARGET) -c init -c targets \
	           -c "rtt setup 0x20000000 262144 \"SEGGER RTT\"" -c "rtt start" -c "rtt server start 2000 0"

gdb: $(PROG).elf
	$(GDB) -ex "target remote localhost:3333" -ex "monitor reset halt" $^

erase:
	$(OPENOCD) -d2 -f $(OPENOCD_INTERFACE) -f $(OPENOCD_TARGET) -c init -c targets -c "halt" -c "stm32f4x mass_erase 0" -c shutdown

#Print preprocessor #defines
prep:
	@$(CC) $(CFLAGS) -dM -E - < /dev/null

check_submodules:
	@cd $(srctree); $(PYTHON) tools/make/check-for-submodules.py

# Give control over to Kbuild
-include Makefile.kbuild

# Some special handling for the version c.file
src/utils/src/version.c: src/utils/src/version.vtpl
	$(PYTHON) $(srctree)/tools/make/versionTemplate.py --crazyflie-base $(srctree) $< $@
