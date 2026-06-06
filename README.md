# 🚀 Sovol SV08 Scripts

This repository hosts helper scripts for maintaining SV08's running mainline klipper remotely. Instead of hunting down unique `/dev/serial/by-id/*` paths over SSH every time Klipper pushes an update, these scripts automatically detect your mainboard, toolhead, and installed eddy sensor paths to flash them completely remotely.

**Coverage:**
1. Klipper updates
  - Automate compiling and flashing Klipper firmware updates for mainline Sovol SV08 machines. 
1. Eddy-ng and BTT-eddy updates
  - Automate compiling and flashing eddy-ng firmware updates.

## ⚠️ Disclaimer
**Use at your own risk.** Flashing hardware microcontrollers carries inherent risks. 
* The author is not responsible for bricked mainboards, un-synchronized toolheads, or physical machine damage.
* Ensure your SV08 heaters are completely cold and no active print jobs are running before continuing.

---

## 🛠️ How It Works

### Updating Klipper and SV08 Hardware

To prevent you from needing to look up paths manually, the script follows this remote-execution flow:
1. **Stops Klipper:** Clears the serial communication channels so the hardware isn't locked.
1. **Interactive Configuration:** Drops you straight into Klipper's native `make menuconfig` so you can verify settings.
1. **Hardware Auto-Detection:** Scans system serial busses to dynamically extract the device paths.
1. **Builds & Flashes:** Compiles the fresh binaries and auto-targets the exact detected ports remotely.
  - [Optional] **Updates Eddy sensor:** Compiles the fresh binaries and auto-targets the Eddy sensor.
      **Note:** Currently only supports eddy-ng, https://github.com/vvuk/eddy-ng, and, more specifically, btt-eddy, https://github.com/vvuk/eddy-ng/wiki/BTT-Eddy.
---

## 📖 Step-by-Step Guide

### Step 1: SSH and Clone this Repo
SSH into your SV08 host device (e.g., BigTreeTech CB1)

```bash
ssh biqu:biqu@<machineaddress>
```
**Note:** This is based on the default user and password after following Rappetor's SV08 mainline conversion, https://github.com/Rappetor/Sovol-SV08-Mainline, if you created a user or changed the password connect accordingly

Clone this repository:

```bash
git clone https://github.com/Stevoni/sv08-scripts
cd sv08-scripts
chmod +x update_mcu.sh
```

### Step 2: Configure Your Boards
Run the script to begin the menu configuration. 
```bash
./update_mcu.sh --config
```
* **For Mainboard:** Ensure your target matches the SV08 architecture (e.g., `STM32F103`, `8KiB bootloader`, `USB communication`). Save and exit.
* **For Toolhead:** Repeat for your explicit toolhead chip profile.

### Step 3: Run the Auto-Flash
Execute the automation script to let it handle device detection and firmware flashing:
```bash
./update_mcu.sh --flash
```

---

## 🔄 Tracking Updates & History
Because this code is hosted as a Git repository, any optimizations made to the flashing loops, dynamic search queries, or new SV08 toolhead board expansions will be safely logged in our commit history. If an update ever breaks a custom board, you can instantly roll back to an older, proven script state:
```bash
git log --oneline
git checkout <commit-hash>
```

---

## 🤝 Contributing
Have an improved method for detecting Katapult bootloaders or handling CANbus toolheads on the SV08? Pull requests are welcome! Please submit an issue first to discuss your planned changes.
