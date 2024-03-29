include application.mk

ifndef NM_SDK
    $(error NM_SDK location not defined)
endif

ifndef AMBIQ_SDK
    $(error AmbiqSuite SDK location not defined)
endif

ifndef CORDIO
    $(error ARM BLE Cordio Stack location not defined)
endif

ifndef UECC
    $(error Micro ECC library location not defined)
endif

ifndef FREERTOS
    $(error FreeRTOS location not defined)
endif

ifndef LORAMAC
    $(error LoRaMAC Node library location not defined)
endif

include makedefs/nm_common.mk
include makedefs/nm_application.mk
include makedefs/nm_cordio.mk
include makedefs/nm_loramac.mk

LDSCRIPT := ./ldscript.ld
ifdef DEBUG
    BUILDDIR := ./debug
    BSP_LIB  := -lam_bsp-dev
else
    BUILDDIR := ./release
    BSP_LIB  := -lam_bsp
endif

BSP_C := $(BSP_DIR)/am_bsp_pins.c
BSP_H := $(BSP_DIR)/am_bsp_pins.h

INCLUDES += -I$(BSP_DIR)
INCLUDES += -I$(NM_SDK)/bsp/devices
INCLUDES += -I$(NM_SDK)/platform

INCLUDES += -I$(CORDIO_PROFILES)/sources/apps
INCLUDES += -I$(CORDIO_PROFILES)/sources/apps/app
INCLUDES += -I$(CORDIO_PROFILES)/sources/apps/app/common

INCLUDES += -I.

VPATH += $(NM_SDK)/platform
VPATH += .

SRC += startup_gcc.c
SRC += main.c
SRC += build_timestamp.c

CSRC = $(filter %.c, $(SRC))
ASRC = $(filter %.s, $(SRC))

OBJS  = $(CSRC:%.c=$(BUILDDIR)/%.o)
OBJS += $(ASRC:%.s=$(BUILDDIR)/%.o)

DEPS  = $(CSRC:%.c=$(BUILDDIR)/%.d)
DEPS += $(ASRC:%.s=$(BUILDDIR)/%.d)

CFLAGS += $(INCLUDES)
CFLAGS += $(DEFINES)

LFLAGS += -Wl,--start-group
LFLAGS += -L$(AMBIQ_SDK)/CMSIS/ARM/Lib/ARM
LFLAGS += -L$(NM_SDK)/build
LFLAGS += -L$(BSP_DIR)/$(BUILDDIR)
LFLAGS += -larm_cortexM4lf_math
LFLAGS += -lm
LFLAGS += -lc
LFLAGS += -lgcc
LFLAGS += $(LIBS)
LFLAGS += $(BSP_LIB)
LFLAGS += --specs=nano.specs
LFLAGS += --specs=nosys.specs
LFLAGS += -Wl,--end-group

all: directories bsp $(BUILDDIR)/$(TARGET).bin

ota: directories bsp $(BUILDDIR)/$(TARGET_OTA).bin

wire: directories bsp $(BUILDDIR)/$(TARGET_WIRE).bin

directories: $(BUILDDIR)

$(BUILDDIR):
	@$(MKDIR) $@

bsp:
	$(MAKE) -C $(BSP_DIR) AMBIQ_SDK=$(AMBIQ_SDK)

$(BSP_C): bsp

$(BSP_H): bsp

$(BUILDDIR)/%.o: %.c $(BUILDDIR)/%.d $(INCS) $(BSP_C) $(BSP_H)
	@echo "Compiling $(COMPILERNAME) $<"
	$(CC) -c $(CFLAGS) $< -o $@

$(BUILDDIR)/%.o: %.s $(BUILDDIR)/%.d $(INCS) $(BSP_C) $(BSP_H)
	@echo "Assembling $(COMPILERNAME) $<"
	$(CC) -c $(CFLAGS) $< -o $@

$(BUILDDIR)/$(TARGET).axf: $(OBJS)
	@echo "Linking $@"
	$(CC) -Wl,-T,$(LDSCRIPT) -o $@ $(OBJS) $(LFLAGS)

$(BUILDDIR)/$(TARGET).bin: $(BUILDDIR)/$(TARGET).axf
	$(OCP) $(OCPFLAGS) $< $@
	$(OD) $(ODFLAGS) $< > $(BUILDDIR)/$(TARGET).lst

$(BUILDDIR)/$(TARGET_OTA).bin: $(BUILDDIR)/$(TARGET).bin
	@echo "Generating OTA image $@"
	$(PYTHON) ./tools/create_cust_image_blob.py --bin $< --load-address 0xc000 --magic-num 0xcb -o $(BUILDDIR)/$(TARGET_OTA)_temp --version $(TARGET_VERSION)
	$(PYTHON) ./tools/ota_binary_converter.py --appbin $(BUILDDIR)/$(TARGET_OTA)_temp.bin -o $(BUILDDIR)/$(TARGET_OTA)
	@$(RM) -rf $(BUILDDIR)/$(TARGET_OTA)_temp.bin

$(BUILDDIR)/$(TARGET_WIRE).bin: $(BUILDDIR)/$(TARGET).bin
	@echo "Generating UART wire image $@"
	$(PYTHON) ./tools/create_cust_image_blob.py --bin $< --load-address 0xc000 --magic-num 0xcb -o $(BUILDDIR)/$(TARGET_WIRE)_temp --version 0x0
	$(PYTHON) ./tools/create_cust_wireupdate_blob.py --load-address 0x20000 --bin $(BUILDDIR)/$(TARGET_WIRE)_temp.bin -i 6 -o $(BUILDDIR)/$(TARGET_WIRE) --options 0x1
	@$(RM) -rf $(BUILDDIR)/$(TARGET_WIRE)_temp.bin


clean:
	@echo "Cleaning..."
	$(RM) -f $(OBJS) $(DEPS) $(BUILDDIR)/$(TARGET).a
	$(RM) -rf $(BUILDDIR)
	$(MAKE) -C $(BSP_DIR) AMBIQ_SDK=$(AMBIQ_SDK) clean

$(BUILDDIR)/%.d: ;

-include $(DEPS)

