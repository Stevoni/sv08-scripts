#!/bin/bash

CONFIG_FILE=~/printer_data/config/printer.cfg
CONFIG_DIR=${CONFIG_FILE%/*}
KLIPPER_DIR=~/klipper
EDDY_NG_DIR=~/eddy-ng
EDDY_BOOTLOADER_USB_ID=2e8a:0003
MOONRAKER_URL=http://localhost:7125
ACTIVE_CONFIG_FILES=()
FIND_MCU_SERIAL_VALUE=""
FIND_MCU_SERIAL_SOURCE=""

trim_whitespace() {
    local value=$1

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

add_active_config_file() {
    local config_file=$1
    local active_file

    for active_file in "${ACTIVE_CONFIG_FILES[@]}"; do
        if [ "$active_file" = "$config_file" ]; then
            return
        fi
    done

    ACTIVE_CONFIG_FILES+=("$config_file")
}

resolve_include_path() {
    local include_path=$1
    local include_pattern
    local include_match
    local matched=0

    if [[ "$include_path" = /* ]]; then
        include_pattern=$include_path
    else
        include_pattern=$CONFIG_DIR/$include_path
    fi

    if [[ "$include_pattern" == *[\*\?\[]* ]]; then
        while IFS= read -r include_match; do
            [ -e "$include_match" ] || continue
            add_active_config_file "$include_match"
            matched=1
        done < <(compgen -G "$include_pattern")
    elif [ -e "$include_pattern" ]; then
        add_active_config_file "$include_pattern"
        matched=1
    fi

    if [ "$matched" -eq 0 ]; then
        echo "Error: active include did not match any config file: $include_path"
        echo "Resolved from: $CONFIG_FILE"
        exit 1
    fi
}

resolve_active_config_files() {
    local scan_index=0
    local config_file
    local line
    local active_line
    local include_path

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Error: root Klipper config not found: $CONFIG_FILE"
        exit 1
    fi

    add_active_config_file "$CONFIG_FILE"

    while [ "$scan_index" -lt "${#ACTIVE_CONFIG_FILES[@]}" ]; do
        config_file=${ACTIVE_CONFIG_FILES[$scan_index]}
        scan_index=$((scan_index + 1))

        if [ ! -f "$config_file" ]; then
            echo "Error: active config file not found: $config_file"
            exit 1
        fi

        while IFS= read -r line || [ -n "$line" ]; do
            active_line=${line%%#*}
            if [[ "$active_line" =~ ^[[:space:]]*\[[[:space:]]*include[[:space:]]+([^]]*[^[:space:]])[[:space:]]*\][[:space:]]*$ ]]; then
                include_path=$(trim_whitespace "${BASH_REMATCH[1]}")
                resolve_include_path "$include_path"
            fi
        done < "$config_file"
    done
}

find_mcu_serial() {
    local section_name=$1
    local config_file
    local line
    local active_line
    local header_name
    local in_section=0
    local section_count=0
    local serial_value=""
    local section_files=()
    local section_serials=()
    local duplicate_file

    FIND_MCU_SERIAL_VALUE=""
    FIND_MCU_SERIAL_SOURCE=""

    for config_file in "${ACTIVE_CONFIG_FILES[@]}"; do
        in_section=0
        while IFS= read -r line || [ -n "$line" ]; do
            active_line=${line%%#*}

            if [[ "$active_line" =~ ^[[:space:]]*\[([^]]+)\][[:space:]]*$ ]]; then
                header_name=$(trim_whitespace "${BASH_REMATCH[1]}")
                if [ "$header_name" = "$section_name" ]; then
                    in_section=1
                    section_count=$((section_count + 1))
                    section_files+=("$config_file")
                    section_serials+=("")
                else
                    in_section=0
                fi
                continue
            fi

            if [ "$in_section" -eq 1 ] && [[ "$active_line" =~ ^[[:space:]]*serial[[:space:]]*:[[:space:]]*(.*[^[:space:]])[[:space:]]*$ ]]; then
                serial_value=$(trim_whitespace "${BASH_REMATCH[1]}")
                section_serials[section_count - 1]=$serial_value
            fi
        done < "$config_file"
    done

    if [ "$section_count" -eq 0 ]; then
        return
    fi

    if [ "$section_count" -gt 1 ]; then
        echo "Error: duplicate active [$section_name] sections found:"
        for duplicate_file in "${section_files[@]}"; do
            echo "  - $duplicate_file"
        done
        echo "Refusing to continue because the flash target is ambiguous."
        exit 1
    fi

    if [ -z "${section_serials[0]}" ]; then
        echo "Error: active [$section_name] section has no serial: value:"
        echo "  - ${section_files[0]}"
        echo "Refusing to continue because the flash target is incomplete."
        exit 1
    fi

    FIND_MCU_SERIAL_VALUE=${section_serials[0]}
    FIND_MCU_SERIAL_SOURCE=${section_files[0]}
}

print_serial_summary() {
    local label=$1
    local serial=$2
    local source=$3
    local missing_message=$4

    if [ -n "$serial" ]; then
        echo "$label: $serial (from $source)"
    else
        echo "$label: ${missing_message:-NOT FOUND}"
    fi
}

format_command() {
    local command_text=""
    local quoted_arg
    local arg

    for arg in "$@"; do
        printf -v quoted_arg '%q' "$arg"
        command_text+="${command_text:+ }$quoted_arg"
    done

    printf '%s' "$command_text"
}

prompt_and_run_flash_command() {
    local target_name=$1
    local command_text
    local flash_confirm

    shift
    command_text=$(format_command "$@")

    while true; do
        echo "$target_name flash command:"
        echo "  $command_text"
        read -r -p "Run, skip, or cancel? (r/y/s/c): " flash_confirm

        case "$flash_confirm" in
            [rR]|[rR][uU][nN]|[yY]|[yY][eE][sS])
                "$@"
                return
                ;;
            [sS]|[sS][kK][iI][pP])
                echo "Skipped: $target_name flash command."
                return
                ;;
            [cC]|[cC][aA][nN][cC][eE][lL])
                echo "User cancelled before running: $command_text"
                exit 1
                ;;
            *)
                echo "Please enter 'r' or 'y' to run, 's' to skip, or 'c' to cancel."
                ;;
        esac
    done
}

preflight_klipper_update() {
    local changed_files
    local dirty_confirm
    local upstream
    local local_rev
    local upstream_rev
    local base_rev

    if [ ! -d "$KLIPPER_DIR/.git" ]; then
        echo "Error: Klipper Git checkout not found: $KLIPPER_DIR"
        exit 1
    fi

    changed_files=$(git -C "$KLIPPER_DIR" status --porcelain --untracked-files=no)
    if [ -n "$changed_files" ]; then
        if [ -n "$EDDY_SERIAL" ]; then
            echo "Warning: Klipper has local tracked changes:"
            printf '%s\n' "$changed_files" | sed 's/^/  /'
            echo ""
            echo "This can be expected when eddy-ng has patched the Klipper checkout."
            echo "Do not continue if you do not recognize these changes."
            read -r -p "Continue with the dirty Klipper checkout? (y/n): " dirty_confirm

            if [[ "$dirty_confirm" = [yY] || "$dirty_confirm" = [yY][eE][sS] ]]; then
                echo "Continuing with existing Klipper changes."
            else
                echo "User aborted because Klipper has local tracked changes."
                exit 1
            fi
        else
        echo "Error: Klipper has local tracked changes that could be overwritten by update:"
        printf '%s\n' "$changed_files" | sed 's/^/  /'
        echo ""
        echo "Inspect these changes on the printer host before rerunning:"
        echo "  cd $KLIPPER_DIR"
        echo "  git status --short"
        echo "  git diff"
        echo ""
        echo "Commit, stash, or intentionally discard the local Klipper changes before continuing."
        exit 1
        fi
    fi

    echo "Fetching Klipper updates..."
    git -C "$KLIPPER_DIR" fetch origin

    if ! upstream=$(git -C "$KLIPPER_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); then
        echo "Error: Klipper checkout has no upstream branch configured."
        echo "Run this on the printer host to inspect it:"
        echo "  cd $KLIPPER_DIR"
        echo "  git branch -vv"
        exit 1
    fi

    local_rev=$(git -C "$KLIPPER_DIR" rev-parse HEAD)
    upstream_rev=$(git -C "$KLIPPER_DIR" rev-parse "$upstream")
    base_rev=$(git -C "$KLIPPER_DIR" merge-base HEAD "$upstream")

    if [ "$local_rev" != "$upstream_rev" ] &&
        [ "$base_rev" != "$local_rev" ] &&
        [ "$base_rev" != "$upstream_rev" ]; then
        echo "Error: Klipper branch has diverged from $upstream and cannot be updated with --ff-only."
        echo "Resolve the Klipper Git history on the printer host before rerunning:"
        echo "  cd $KLIPPER_DIR"
        echo "  git status"
        echo "  git log --oneline --decorate --graph --max-count=20 --all"
        exit 1
    fi
}

send_gcode_script() {
    local gcode_script=$1
    local request_body
    local response

    if ! command -v curl >/dev/null 2>&1; then
        echo "Error: curl is required to send G-code through Moonraker."
        exit 1
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        echo "Error: python3 is required to prepare and validate Moonraker requests."
        exit 1
    fi

    request_body=$(printf '{"script":%s}' "$(printf '%s' "$gcode_script" | python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))')")

    if ! response=$(curl --fail --silent --show-error \
        -X POST "$MOONRAKER_URL/printer/gcode/script" \
        -H "Content-Type: application/json" \
        --data "$request_body"); then
        echo "Error: Moonraker rejected the G-code request. Aborting before update or flash."
        exit 1
    fi

    if ! printf '%s' "$response" | python3 -c '
import json
import sys

try:
    payload = json.load(sys.stdin)
except json.JSONDecodeError as exc:
    print(f"Error: Moonraker returned invalid JSON: {exc}", file=sys.stderr)
    sys.exit(1)

if isinstance(payload, dict) and "error" in payload:
    error = payload["error"]
    if isinstance(error, dict):
        message = error.get("message") or error.get("error") or json.dumps(error, sort_keys=True)
    else:
        message = str(error)
    print(f"Error: Moonraker returned an error response: {message}", file=sys.stderr)
    sys.exit(1)
'; then
        echo "Aborting before update or flash."
        exit 1
    fi
}

confirm_and_position_toolhead() {
    local position_confirm
    local skip_confirm
    local position_gcode

    position_gcode=$'G28\nG90\nG1 Z20 F600'

    while true; do
        echo "========================================================="
        echo "           TOOLHEAD POSITION SAFETY CONFIRMATION         "
        echo "========================================================="
        echo "The script can home the printer and move the toolhead to Z=20mm."
        echo "Only run this if the bed is clear, no print is active, and homing is safe."
        echo ""
        echo "G-code to send through Moonraker:"
        printf '%s\n' "$position_gcode" | sed 's/^/  /'
        echo "========================================================="

        read -r -p "Home and move to Z=20mm, skip, or cancel? (y/s/c): " position_confirm
        case "$position_confirm" in
            [yY]|[yY][eE][sS]|[rR]|[rR][uU][nN])
                echo "Homing printer and moving toolhead to Z=20mm..."
                send_gcode_script "$position_gcode"
                return
                ;;
            [sS]|[sS][kK][iI][pP])
                echo "Eddy calibration expects the toolhead to be positioned at Z=20mm."
                echo "If you skip this step, you must position the toolhead correctly before recalibrating Eddy."
                read -r -p "Are you OK with skipping toolhead positioning? (y/n): " skip_confirm
                if [[ "$skip_confirm" = [yY] || "$skip_confirm" = [yY][eE][sS] ]]; then
                    echo "Skipped: Toolhead positioning."
                    return
                fi
                ;;
            [cC]|[cC][aA][nN][cC][eE][lL])
                echo "User cancelled before homing or moving the toolhead."
                exit 1
                ;;
            *)
                echo "Please enter 'y' to home and move, 's' to skip, or 'c' to cancel."
                ;;
        esac
    done
}

is_eddy_bootloader_mode() {
    if ! command -v lsusb >/dev/null 2>&1; then
        echo "Error: lsusb is required to detect the Eddy RP2040 bootloader."
        exit 1
    fi

    lsusb -d "$EDDY_BOOTLOADER_USB_ID" >/dev/null 2>&1
}

wait_for_eddy_bootloader() {
    local checks=$1
    local check_number

    for ((check_number = 1; check_number <= checks; check_number++)); do
        if is_eddy_bootloader_mode; then
            echo "Eddy RP2040 bootloader detected."
            return 0
        fi

        echo "Eddy bootloader not detected yet. Check $check_number of $checks."
        sleep 2
    done

    return 1
}

kick_eddy_bootloader() {
    echo "Kicking Eddy into bootloader..."
    python3 -c "import serial; s=serial.Serial('$EDDY_SERIAL', 1200); s.close()"
}

set_eddy_serial_hupcl() {
    if ! command -v stty >/dev/null 2>&1; then
        echo "Warning: stty is not available; cannot set HUPCL on $EDDY_SERIAL."
        return
    fi

    echo "Setting HUPCL on $EDDY_SERIAL before retrying bootloader kick..."
    sudo stty -F "$EDDY_SERIAL" hupcl || true
}

release_eddy_serial_holders() {
    if ! command -v fuser >/dev/null 2>&1; then
        echo "Warning: fuser is not available; cannot kill processes holding $EDDY_SERIAL."
        return
    fi

    echo "Killing processes that still hold $EDDY_SERIAL..."
    sudo fuser -k "$EDDY_SERIAL" >/dev/null 2>&1 || true
}

prompt_eddy_bootloader_failure() {
    local bootloader_confirm

    echo "Failed to detect the Eddy RP2040 bootloader after retries."
    while true; do
        read -r -p "Quit the script or skip the Eddy update? (q/s): " bootloader_confirm

        case "$bootloader_confirm" in
            [qQ]|[qQ][uU][iI][tT])
                echo "User quit after Eddy bootloader detection failed."
                exit 1
                ;;
            [sS]|[sS][kK][iI][pP])
                echo "Skipped: Eddy update."
                return 1
                ;;
            *)
                echo "Please enter 'q' to quit or 's' to skip the Eddy update."
                ;;
        esac
    done
}

prepare_eddy_bootloader() {
    if is_eddy_bootloader_mode; then
        echo "Eddy is already in RP2040 bootloader mode."
        return 0
    fi

    kick_eddy_bootloader
    if wait_for_eddy_bootloader 3; then
        return 0
    fi

    echo "Retrying Eddy bootloader kick..."
    kick_eddy_bootloader
    if wait_for_eddy_bootloader 3; then
        return 0
    fi

    set_eddy_serial_hupcl
    kick_eddy_bootloader
    if wait_for_eddy_bootloader 3; then
        return 0
    fi

    release_eddy_serial_holders
    kick_eddy_bootloader
    if wait_for_eddy_bootloader 3; then
        return 0
    fi

    prompt_eddy_bootloader_failure
}

update_eddy_ng_patch() {
    if [ -z "$EDDY_SERIAL" ]; then
        return
    fi

    if [ ! -d "$EDDY_NG_DIR" ]; then
        echo "Error: Eddy is configured, but eddy-ng was not found: $EDDY_NG_DIR"
        exit 1
    fi

    echo "Updating and applying eddy-ng patch..."
    if [ -d "$EDDY_NG_DIR/.git" ]; then
        git -C "$EDDY_NG_DIR" pull --ff-only
    fi

    cd "$EDDY_NG_DIR" || exit
    ./install.sh
}

# ---------------------------------------------------------
# PHASE 1: DYNAMIC DEVICE DISCOVERY & CONFIRMATION
# ---------------------------------------------------------
resolve_active_config_files

find_mcu_serial "mcu"
MAINBOARD_SERIAL=$FIND_MCU_SERIAL_VALUE
MAINBOARD_SERIAL_SOURCE=$FIND_MCU_SERIAL_SOURCE

find_mcu_serial "mcu extra_mcu"
TOOLHEAD_SERIAL=$FIND_MCU_SERIAL_VALUE
TOOLHEAD_SERIAL_SOURCE=$FIND_MCU_SERIAL_SOURCE

find_mcu_serial "mcu eddy"
EDDY_SERIAL=$FIND_MCU_SERIAL_VALUE
EDDY_SERIAL_SOURCE=$FIND_MCU_SERIAL_SOURCE

echo "========================================================="
echo "         FIRMWARE FLASH SUMMARY & CONFIRMATION           "
echo "========================================================="
print_serial_summary "Mainboard" "$MAINBOARD_SERIAL" "$MAINBOARD_SERIAL_SOURCE" "NOT FOUND"
print_serial_summary "Toolhead " "$TOOLHEAD_SERIAL" "$TOOLHEAD_SERIAL_SOURCE" "NOT FOUND"
print_serial_summary "Eddy     " "$EDDY_SERIAL" "$EDDY_SERIAL_SOURCE" "NOT FOUND (Will skip Eddy update)"
echo "========================================================="
echo ""

read -r -p "Do these paths look correct? Proceed with flashing? (y/n): " confirm

if [[ "$confirm" != [yY] && "$confirm" != [yY][eE][sS] ]]; then
    echo "User aborted. Exiting script without flashing."
    exit 1
fi

preflight_klipper_update
confirm_and_position_toolhead

# ---------------------------------------------------------
# PHASE 2: PREP & UPDATE
# ---------------------------------------------------------
echo "Stopping Klipper and Moonraker..."
sudo systemctl stop klipper moonraker

echo "Cleaning previous Klipper installation and updating..."
cd "$KLIPPER_DIR" || exit
git pull --ff-only
update_eddy_ng_patch
cd "$KLIPPER_DIR" || exit
make clean

# ---------------------------------------------------------
# PHASE 3: CONFIGURE & COMPILE STM32 (Mainboard & Toolhead)
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
# PHASE 4: FLASH STM32 BOARDS
# ---------------------------------------------------------
if [ -n "$MAINBOARD_SERIAL" ]; then
    prompt_and_run_flash_command "Mainboard" make flash "FLASH_DEVICE=$MAINBOARD_SERIAL"
else
    echo "Skipped: No Mainboard serial found."
fi

if [ -n "$TOOLHEAD_SERIAL" ]; then
    prompt_and_run_flash_command "Toolhead" make flash "FLASH_DEVICE=$TOOLHEAD_SERIAL"
else
    echo "Skipped: No Toolhead serial found."
fi

# ---------------------------------------------------------
# PHASE 5: CONFIGURE & FLASH RP2040 (BTT Eddy - Optional)
# ---------------------------------------------------------
if [ -n "$EDDY_SERIAL" ] && prepare_eddy_bootloader; then
    make clean

    echo "========================================================="
    echo "           STEP 2: CONFIGURE RP2040 (BTT Eddy)           "
    echo "========================================================="
    echo "When the menu opens, please set the exact following options:"
    echo ""
    echo "  - Micro-controller Architecture: Raspberry Pi RP2040/RP235X"
    echo "  - Bootloader offset: No bootloader"
    echo "  - Flash chip: GENERIC_03H with CLKDIV 4"
    echo "  - Communication interface: USBSERIAL"
    echo ""
    echo "---------------------------------------------------------"
    echo "Press 'Q' to exit and 'Y' to save when finished."
    echo "Press any key to open the configuration menu..."
    read -n1 -s -r

    make menuconfig

    echo "Compiling Eddy firmware..."
    make -j4
    prompt_and_run_flash_command "Eddy" make flash "FLASH_DEVICE=$EDDY_BOOTLOADER_USB_ID"
fi

echo "Starting Klipper and Moonraker..."
sudo systemctl start klipper moonraker

echo "Update and Flash Complete!"
