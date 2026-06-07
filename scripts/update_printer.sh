#!/bin/bash

# ---------------------------------------------------------
# PHASE 1: PREP & UPDATE
# ---------------------------------------------------------
echo "Stopping Klipper and Moonraker..."
sudo systemctl stop klipper moonraker

echo "Cleaning previous Klipper installation and updating..."
cd ~/klipper
git fetch origin
git pull --ff-only
make clean

# ---------------------------------------------------------
# PHASE 2: CONFIGURE & COMPILE STM32 (Mainboard & Toolhead)
# ---------------------------------------------------------
echo "========================================================="
echo "      STEP 1: CONFIGURE STM32 (Mainboard & Toolhead)     "
echo "========================================================="
echo "When the menu opens, please set the exact following options:"
echo ""
echo "  - Micro-controller Architecture: STMicroelectronics STM32"
echo "  - Processor model: STM32F103"
echo "  - Bootloader offset: 8KiB bootloader"
echo "  - Clock Reference: 8 MHz crystal"
echo "  - Communication interface: USB (on PA11/PA12)"
echo ""
echo "---------------------------------------------------------"
echo "Press 'Q' to exit and 'Y' to save when finished."
echo "Press any key to open the configuration menu..."
read -n1 -s -r

make menuconfig

echo "Compiling STM32 firmware..."
make -j4

# ---------------------------------------------------------
# PHASE 3: DYNAMIC DEVICE DISCOVERY & CONFIRMATION
# ---------------------------------------------------------
CONFIG_FILE=~/printer_data/config/printer.cfg

MAINBOARD_SERIAL=$(awk '/^\[mcu\]/{f=1} f && /^serial:/{print $2; exit}' "$CONFIG_FILE")
TOOLHEAD_SERIAL=$(awk '/^\[mcu extra_mcu\]/{f=1} f && /^serial:/{print $2; exit}' "$CONFIG_FILE")
EDDY_SERIAL=$(awk '/^\[mcu eddy\]/{f=1} f && /^serial:/{print $2; exit}' "$CONFIG_FILE")

echo "========================================================="
echo "         FIRMWARE FLASH SUMMARY & CONFIRMATION           "
echo "========================================================="
echo "Mainboard: ${MAINBOARD_SERIAL:-NOT FOUND}"
echo "Toolhead:  ${TOOLHEAD_SERIAL:-NOT FOUND}"

if [ -z "$EDDY_SERIAL" ]; then
    echo "Eddy:      NOT FOUND (Will skip Eddy update)"
else
    echo "Eddy:      $EDDY_SERIAL"
fi
echo "========================================================="
echo ""

read -p "Do these paths look correct? Proceed with flashing? (y/n): " confirm

if [[ "$confirm" != [yY] && "$confirm" != [yY][eE][sS] ]]; then
    echo "User aborted. Exiting script without flashing."
    exit 1
fi

# ---------------------------------------------------------
# PHASE 4: FLASH STM32 BOARDS
# ---------------------------------------------------------
if [ -n "$MAINBOARD_SERIAL" ]; then
    echo "Flashing Mainboard..."
    make flash FLASH_DEVICE="$MAINBOARD_SERIAL"
else
    echo "Skipped: No Mainboard serial found."
fi

if [ -n "$TOOLHEAD_SERIAL" ]; then
    echo "Flashing Toolhead..."
    make flash FLASH_DEVICE="$TOOLHEAD_SERIAL"
else
    echo "Skipped: No Toolhead serial found."
fi

# ---------------------------------------------------------
# PHASE 5: CONFIGURE & FLASH RP2040 (BTT Eddy - Optional)
# ---------------------------------------------------------
if [ -n "$EDDY_SERIAL" ]; then
    echo "Kicking Eddy into bootloader..."
    python3 -c "import serial; s=serial.Serial('$EDDY_SERIAL', 1200); s.close()"

    echo "Waiting for RP2040 bootloader to mount..."
    sleep 3

    make clean

    echo "========================================================="
    echo "           STEP 2: CONFIGURE RP2040 (BTT Eddy)           "
    echo "========================================================="
    echo "When the menu opens, please set the exact following options:"
    echo ""
    echo "  - Micro-controller Architecture: Raspberry Pi RP2040"
    echo "  - Bootloader offset: No bootloader"
    echo "  - Flash chip: W25Q080 with CLKDIV 2"
    echo "  - Communication interface: USB"
    echo ""
    echo "---------------------------------------------------------"
    echo "Press 'Q' to exit and 'Y' to save when finished."
    echo "Press any key to open the configuration menu..."
    read -n1 -s -r

    make menuconfig

    echo "Compiling and Flashing Eddy..."
    make -j4
    make flash FLASH_DEVICE=2e8a:0003
fi

# ---------------------------------------------------------
# PHASE 6: REAPPLY PATCH & RESTART
# ---------------------------------------------------------
echo "Reapplying eddy-ng patch..."
cd ~/eddy-ng
./install.sh

echo "Starting Klipper and Moonraker..."
sudo systemctl start klipper moonraker

echo "Update and Flash Complete!"
