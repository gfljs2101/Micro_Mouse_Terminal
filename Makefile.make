# Makefile for building MMT.img from NASM assembly files in /src/

# NASM assembler
ASM = nasm
ASMFLAGS = -f bin

# Directories
SRC_DIR   = src
BUILD_DIR = build

# Source files
BOOTLOADER_SRC = $(SRC_DIR)/bootloader/Bootloader.asm
KERNEL_SRC     = $(SRC_DIR)/Kernel.asm

# Output binaries
BOOTLOADER_BIN = $(BUILD_DIR)/bootloader.bin
KERNEL_BIN     = $(BUILD_DIR)/kernel.bin

# Final floppy image
IMG = $(BUILD_DIR)/MMT.img

# Default target
all: $(IMG)

# Compile bootloader
$(BOOTLOADER_BIN): $(BOOTLOADER_SRC)
	mkdir -p $(BUILD_DIR)
	$(ASM) $(ASMFLAGS) $< -o $@

# Compile kernel
$(KERNEL_BIN): $(KERNEL_SRC)
	mkdir -p $(BUILD_DIR)
	$(ASM) $(ASMFLAGS) -I$(SRC_DIR)/ $(KERNEL_SRC) -o $@

# Create floppy image using Python script
$(IMG): $(BOOTLOADER_BIN) $(KERNEL_BIN) create_image.py example.txt
	python3 create_image.py

# Clean generated files
.PHONY: clean all
clean:
	rm -f $(BUILD_DIR)/*.bin $(IMG)
