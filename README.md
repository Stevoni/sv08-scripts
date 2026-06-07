# 🚀 Sovol SV08 Scripts

This repository hosts helper scripts for maintaining SV08 printers running mainline Klipper remotely after following Rappetor's SV08 mainline conversion: https://github.com/Rappetor/Sovol-SV08-Mainline.

Instead of hunting down unique `/dev/serial/by-id/*` paths over SSH every time Klipper pushes an update, these scripts read your configured mainboard, toolhead, and installed Eddy sensor paths to flash them remotely.

**Coverage:**
1. Klipper updates
  - Automate compiling and flashing Klipper firmware updates for mainline Sovol SV08 machines using the Rappetor conversion layout.
1. Eddy-ng and BTT-eddy updates
  - Automate compiling and flashing eddy-ng firmware updates.

## ⚠️ Disclaimer
**Use at your own risk.** Flashing hardware microcontrollers carries inherent risks. 
* The author is not responsible for bricked mainboards, un-synchronized toolheads, or physical machine damage.
* Ensure your SV08 heaters are completely cold and no active print jobs are running before continuing.
* Read the displayed MCU paths before confirming any flash operation.

---

## ✅ Supported Baseline & Prerequisites

These scripts are written for printers converted with Rappetor's SV08 mainline conversion. Other conversion layouts may use different service names, config paths, MCU section names, or firmware expectations and are not currently covered.

The conversion provides the base Klipper environment. This repository additionally expects:

* Klipper source at `~/klipper`.
* Printer config at `~/printer_data/config/printer.cfg`.
* MCU sections named `[mcu]` for the mainboard and `[mcu extra_mcu]` for the toolhead.
* Permission to stop and start `klipper` and `moonraker` with `sudo systemctl`.
* Moonraker reachable on the printer host at `http://localhost:7125` so the script can send the guarded homing and Z lift command before stopping services.
* `curl` available on the printer host for Moonraker G-code requests.
* If using Eddy, an `[mcu eddy]` section in `printer.cfg` and eddy-ng installed at `~/eddy-ng`.
* For Eddy updates, Python's `serial` module must be available so the script can put the RP2040 into bootloader mode.

## 🛠️ How It Works

### Updating Klipper and SV08 Hardware

To prevent you from needing to look up paths manually, the script follows this remote-execution flow:
1. **Configured Device Discovery:** Reads the configured MCU serial paths from `printer.cfg` and active included config files.
1. **Confirmation:** Prints the mainboard, toolhead, and optional Eddy paths before any flashing workflow begins.
1. **Toolhead Safety Positioning:** Prompts you to home and move to Z=20 mm, skip positioning, or cancel. If skipped, the script warns that Eddy calibration expects the toolhead at Z=20 mm and asks you to confirm the skip.
1. **Stops Klipper and Moonraker:** Clears the serial communication channels so the hardware isn't locked.
1. **Updates Klipper safely:** Fetches upstream changes and runs `git pull --ff-only` in `~/klipper`. If your Klipper checkout has diverged, the script stops instead of discarding local changes.
1. **Interactive Configuration:** Drops you straight into Klipper's native `make menuconfig` so you can verify settings.
1. **Builds & Flashes:** Compiles the fresh binaries and prompts before each flash command so you can run, skip, or cancel.
  - [Optional] **Updates Eddy sensor:** Compiles the fresh binaries and auto-targets the Eddy sensor.
      **Note:** Currently only supports eddy-ng, https://github.com/vvuk/eddy-ng, and, more specifically, btt-eddy, https://github.com/vvuk/eddy-ng/wiki/BTT-Eddy.
---

## 📖 Step-by-Step Guide

### Step 1: SSH and Clone this Repo
SSH into your SV08 host device (e.g., BigTreeTech CB1)

```bash
ssh biqu:biqu@<machineaddress>
```
**Note:** This is based on the default user and password after following Rappetor's SV08 mainline conversion. If you created a user or changed the password, connect accordingly.

Clone this repository:

```bash
git clone https://github.com/Stevoni/sv08-scripts
cd sv08-scripts
chmod +x scripts/update_printer.sh
```

### Step 2: Review Your Configured MCU Paths
Before flashing, confirm these sections exist in `~/printer_data/config/printer.cfg` and point to the expected hardware:

```ini
[mcu]
serial: /dev/serial/by-id/...

[mcu extra_mcu]
serial: /dev/serial/by-id/...

[mcu eddy]
serial: /dev/serial/by-id/...
```

The Eddy section is optional. If it is not present, the script skips the Eddy update.

### Step 3: Run the Update and Flash Script
Run the script to begin the update, configuration, confirmation, and flash flow.

```bash
./scripts/update_printer.sh
```
Before Klipper and Moonraker are stopped, the script asks whether to home the printer and move the toolhead to 20 mm above the plate. If you choose to run positioning, it sends this G-code through Moonraker:

```gcode
G28
G90
G1 Z20 F600
```

You may skip positioning, but the script will ask for a second confirmation because Eddy calibration expects the toolhead to be positioned at Z=20 mm.

* **For Mainboard:** Ensure your target matches the SV08 architecture (e.g., `STM32F103`, `8KiB bootloader`, `USB communication`). Save and exit.
* **For Toolhead:** Repeat for your explicit toolhead chip profile.
* **For Eddy:** If configured, verify the RP2040 Eddy firmware settings when the second menu opens.

---

## 🔄 Tracking Updates & History
Because this code is hosted as a Git repository, any optimizations made to the flashing loops, dynamic search queries, or new SV08 toolhead board expansions will be safely logged in our commit history. If an update ever breaks a custom board, you can instantly roll back to an older, proven script state:
```bash
git log --oneline
git checkout <commit-hash>
```

---

## 🤖 Development Transparency
This project may use AI-assisted coding agents for implementation help, issue investigation, documentation edits, and maintenance guidance. Agent output should be reviewed by a human maintainer before use, especially for hardware-flashing behavior. Responsibility for testing, accepting, and running changes remains with the human operator.

---

## 🤝 Contributing
Have an improved method for detecting Katapult bootloaders or handling CANbus toolheads on the SV08? Pull requests are welcome! Please submit an issue first to discuss your planned changes.
