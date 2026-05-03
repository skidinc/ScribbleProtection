#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin


ok()      { printf "[  OK  ] %s\n" "$1"; }
warn()    { printf "[ WARN ] %s\n" "$1"; }
err()     { printf "[ FAIL ] %s\n" "$1"; }
info()    { printf "[ INFO ] %s\n" "$1"; }
sep()     { printf "$(printf -- '-%.0s' $(seq 1 58))\n"; }
pause()   { printf "\n[enter to continue]"; read -r _; }
confirm() {
    printf "%s [y/N]: " "$1"
    read -r _a
    [ "$_a" = "y" ] || [ "$_a" = "Y" ]
}

if [ "$EUID" -ne 0 ]; then
    err "Please run as root!"
    exit 1
fi

# Arrow-key menu helper
arrow_menu() {
    local _title="$1"; shift
    local _items=("$@")
    local _n=${#_items[@]}
    local _sel=0
    local _key _esc _br

    printf '\033[?25l'
    trap 'printf "\033[?25h"; stty echo icanon 2>/dev/null' RETURN
    stty -echo -icanon min 1 time 0 2>/dev/null

    while true; do
        clear
        printf ""
        cat <<'LOGO'
  ____  ____
 / ___||  _ \
 \___ \| |_) |
  ___) |  __/
 |____/|_|
LOGO
        printf ""
        printf "  Scribble Protection  |  WP Assistant\n"
        sep
        printf "\n  %s\n\n" "$_title"
        printf "  arrows to move, enter to select\n\n"

        local _i=0
        while [ $_i -lt $_n ]; do
            if [ $_i -eq $_sel ]; then
                printf "    %-50s  \n" "${_items[$_i]}"
            else
                printf "    %-50s  \n" "${_items[$_i]}"
            fi
            _i=$((_i+1))
        done
        printf "\n"

        _esc=""; _key=""
        IFS= read -r -s -n1 _key
        if [ "$_key" = $'\033' ]; then
            IFS= read -r -s -n1 -t 0.05 _esc || true
            if [ "$_esc" = "[" ]; then
                IFS= read -r -s -n1 -t 0.05 _br || true
                case "$_br" in
                    A) _sel=$((_sel-1)); [ $_sel -lt 0 ] && _sel=$((_n-1)) ;;
                    B) _sel=$((_sel+1)); [ $_sel -ge $_n ] && _sel=0 ;;
                esac
            else
                ARROW_RESULT=-1
                printf '\033[?25h'
                stty echo icanon 2>/dev/null
                return
            fi
        elif [ "$_key" = "" ]; then
            ARROW_RESULT=$_sel
            printf '\033[?25h'
            stty echo icanon 2>/dev/null
            return
        fi
    done
}

# Step screen header
step_header() {
    clear
    printf ""
    cat <<'LOGO'
  ____  ____
 / ___||  _ \
 \___ \| |_) |
  ___) |  __/
 |____/|_|
LOGO
    printf ""
    printf "  Scribble Protection  |  WP Assistant\n"
    sep
    printf "\n  %s\n\n" "$1"
    sep
    printf "\n"
}

# GSC detection and WP read
detect_gsc() {
    local _r="unknown"
    if command -v gsctool >/dev/null 2>&1; then
        local _o
        _o=$(gsctool -a -I 2>/dev/null)
        if [ -n "$_o" ]; then
            if echo "$_o" | grep -qw 'AllowUnverifiedRo'; then
                _r="ti50"
            else
                _r="cr50"
            fi
        fi
    fi
    # Sysfs / devnode fallbacks for environments without working gsctool
    [ "$_r" = "unknown" ] && ls /dev/ti50* >/dev/null 2>&1 && _r="ti50"
    [ "$_r" = "unknown" ] && ls /dev/cr50* >/dev/null 2>&1 && _r="cr50"
    [ "$_r" = "unknown" ] && [ -d /sys/bus/platform/devices/ti50 ] && _r="ti50"
    [ "$_r" = "unknown" ] && [ -d /sys/bus/platform/devices/cr50 ] && _r="cr50"
    if [ "$_r" = "unknown" ] && [ -f /sys/class/tpm/tpm0/device/description ]; then
        grep -qi 'ti50' /sys/class/tpm/tpm0/device/description 2>/dev/null && _r="ti50"
        grep -qi 'cr50' /sys/class/tpm/tpm0/device/description 2>/dev/null && _r="cr50"
    fi
    echo "$_r"
}

check_wp() {
    crossystem wpsw_cur 2>/dev/null
}

# CR50 - Battery disconnect screen
cr50_battery_disconnect() {
    step_header "CR50 - Battery Disconnect"
    printf "  WP on CR50 is tied to battery presence. Pull the battery,\n"
    printf "  run on AC only, and wpsw_cur drops to 0.\n\n"
    printf "  1. Full power off - hold power button until dead.\n\n"
    printf "  2. Open the bottom cover.\n\n"
    printf "  3. Disconnect the battery connecto.\n"
    printf "     Pull straight up, don't yank the wires.\n\n"
    printf "  4. Plug in AC power.\n\n"
    printf "  5. Boot into VT2 and verify:\n"
    printf "     crossystem wpsw_cur  ->  0\n\n"
    sep
    printf "\n"
    warn "Do all flash ops before reconnecting the battery."
    printf "\n"

    local _wp
    _wp=$(check_wp)
    if [ "$_wp" = "0" ]; then
        ok "wpsw_cur=0  WP is off"
    else
        warn "wpsw_cur=${_wp}  WP still on - disconnect the battery first"
    fi
    printf "\n"
    pause
}

# CR50 - CCD via SuzyQ screen
cr50_ccd_suzyq() {
    step_header "CR50 - CCD via SuzyQ"
    printf "  Needs a SuzyQable and a second machine.\n"
    printf "  Debug port is usually the left USB-C, furthest from power.\n\n"
    printf "  1. Plug SuzyQ into the debug port.\n\n"
    printf "  2. On the host:\n"
    printf "     ls /dev/ttyUSB*\n"
    printf "     ttyUSB0=AP  ttyUSB1=EC  ttyUSB2=CR50\n\n"
    printf "  3. Open CR50 console on host:\n"
    printf "     minicom -D /dev/ttyUSB2 -b 115200\n\n"
    printf "  4. In CR50 console:\n"
    printf "     ccd             check current state\n"
    printf "     ccd open        start 5min PP window\n\n"
    printf "  5. Press power button on target when CR50 asks.\n\n"
    printf "  6. After open:\n"
    printf "     wp disable atboot    persists across reboots\n"
    printf "     wp disable           current session only\n\n"
    printf "  7. Verify on target:\n"
    printf "     crossystem wpsw_cur  ->  0\n\n"
    sep
    printf "\n"
    warn "CCD open resets on 'ccd lock' or factory reset."
    printf "\n"
    pause
}

# CR50 - CCD via gsctool screen
cr50_ccd_gsctool() {
    step_header "CR50 - CCD via gsctool"
    printf "  No cable needed. Uses the internal AP to CR50 path.\n\n"
    printf "  1. Check state:\n"
    printf "     gsctool -a -I\n\n"
    printf "  2. Start CCD open:\n"
    printf "     gsctool -a -o\n\n"
    printf "  3. Press power button when prompted. 5min window.\n"
    printf "     Device may reboot - that's not bad, come back to VT2.\n\n"
    printf "  4. Set flags:\n"
    printf "     gsctool -a -I AllowUnverifiedRo:always\n"
    printf "  5. Kill WP:\n"
    printf "     gsctool -a -w 0\n\n"
    printf "  6. Verify:\n"
    printf "     crossystem wpsw_cur  ->  0\n\n"
    sep
    printf "\n"

    local _wp
    _wp=$(check_wp)
    if [ "$_wp" = "0" ]; then
        ok "wpsw_cur=0  WP is off"
    else
        warn "wpsw_cur=${_wp}  WP on"
        printf "\n"
        if confirm "Run gsctool -a -o now?"; then
            warn "Device may reboot. Re-run ScribbleProtection.sh after."
            gsctool -a -o 2>&1 | while IFS= read -r l; do printf "  %s\n" "$l"; done
        fi
    fi
    printf "\n"
    pause
}

# CR50 menu
menu_cr50() {
    while true; do
        arrow_menu "CR50 - WP Method" \
            "Battery disconnect" \
            "CCD via SuzyQ (needs 2nd machine + cable)" \
            "CCD via gsctool" \
            "Check WP status" \
            "Back"

        case "$ARROW_RESULT" in
            0) cr50_battery_disconnect ;;
            1) cr50_ccd_suzyq ;;
            2) cr50_ccd_gsctool ;;
            3)
                step_header "WP Status"
                local _wp
                _wp=$(check_wp)
                sep
                printf "  wpsw_cur = %s\n\n" "$_wp"
                [ "$_wp" = "0" ] && ok "WP off" || warn "WP on"
                printf "\n"
                if command -v gsctool >/dev/null 2>&1; then
                    gsctool -a -I 2>/dev/null | grep -i 'wp\|write\|state' | while IFS= read -r l; do
                        printf "  %s\n" "$l"
                    done
                fi
                sep
                pause
                ;;
            4|-1) return ;;
        esac
    done
}

# TI50 - CCD via gsctool screen
ti50_ccd_gsctool() {
    step_header "TI50 - CCD via gsctool"
    printf "  Battery disconnect does NOT work on TI50.\n"
    printf "  CCD open via gsctool is the main path.\n\n"
    printf "  1. Confirm TI50:\n"
    printf "     gsctool -a -v   look for dauntless or 0.2.x\n\n"
    printf "  2. Check state:\n"
    printf "     gsctool -a -I\n\n"
    printf "  3. Start CCD open:\n"
    printf "     gsctool -a -o\n\n"
    printf "  4. Press power button as TI50 asks. 5min window.\n"
    printf "     Device will reboot. Come back to VT2 after.\n\n"
    printf "  5. Confirm open:\n"
    printf "     gsctool -a -I   look for State: Open\n\n"
    printf "  6. Set flags:\n"
    printf "     gsctool -a -I AllowUnverifiedRo:always\n"
    printf "  7. Kill WP:\n"
    printf "     gsctool -a -w 0\n\n"
    printf "  ${BOLD}8.${RST} Verify:\n"
    printf "     crossystem wpsw_cur  ->  0\n\n"
    sep
    printf "\n"

    local _wp
    _wp=$(check_wp)
    if [ "$_wp" = "0" ]; then
        ok "wpsw_cur=0  WP is off"
        printf "\n"
        gsctool -a -I 2>/dev/null | grep -i 'state\|ccd' | while IFS= read -r l; do printf "  %s\n" "$l"; done
    else
        warn "wpsw_cur=${_wp}  WP on"
        printf "\n"
        if confirm "Run gsctool -a -o now?"; then
            warn "Device will reboot. Re-run ScribbleProtection.sh after."
            gsctool -a -o 2>&1 | while IFS= read -r l; do printf "  %s\n" "$l"; done
        fi
    fi
    printf "\n"
    pause
}

# TI50 - CCD via SuzyQ screen
ti50_ccd_suzyq() {
    step_header "TI50 - CCD via SuzyQ"
    printf "  Same cable as CR50. Same port. Connects to Ti50 serial.\n\n"
    printf "  1. Plug SuzyQ into the debug USB-C port.\n"
    printf "     Check mrchromebox.tech for your board's port location.\n\n"
    printf "  2. On host:\n"
    printf "     ls /dev/ttyUSB*   ttyUSB2 = GSC console\n\n"
    printf "  3. Connect:\n"
    printf "     minicom -D /dev/ttyUSB2 -b 115200\n\n"
    printf "  4. In TI50 console:\n"
    printf "     ccd              check state\n"
    printf "     ccd open         start PP window\n\n"
    printf "  5. Press power button on target when asked.\n\n"
    printf "  6. After open:\n"
    printf "     wp disable atboot\n"
    printf "     ccd set AllowUnverifiedRo always\n"
    sep
    printf "\n"
    pause
}

# TI50 - Verify state screen
ti50_verify() {
    step_header "TI50 - Verify State"
    sep

    local _wp
    _wp=$(check_wp)
    printf "  wpsw_cur = ${BOLD}%s${RST}\n" "$_wp"
    [ "$_wp" = "0" ] && ok "WP off" || warn "WP on"
    printf "\n"

    if command -v gsctool >/dev/null 2>&1; then
        info "gsctool -a -I:"
        gsctool -a -I 2>/dev/null | while IFS= read -r l; do printf "  %s\n" "$l"; done
        printf "\n"
        info "gsctool -a -v:"
        gsctool -a -v 2>/dev/null | while IFS= read -r l; do printf "  %s\n" "$l"; done
    else
        warn "gsctool not found"
    fi
    sep
    pause
}

# TI50 menu
menu_ti50() {
    while true; do
        arrow_menu "TI50 - WP Method" \
            "CCD via gsctool" \
            "CCD via SuzyQ (needs 2nd machine + SuzyQable)" \
            "Verify CCD + WP state" \
            "TI50 vs CR50 differences" \
            "Back"

        case "$ARROW_RESULT" in
            0) ti50_ccd_gsctool ;;
            1) ti50_ccd_suzyq ;;
            2) ti50_verify ;;
            3)
                step_header "TI50 vs CR50"
                sep
                printf "  %-26s %s\n" "Battery disconnect WP"  "${R}NO - does not work on TI50${RST}"
                printf "  %-26s %s\n" "CCD open"               "same - gsctool -a -o or console"
                printf "  %-26s %s\n" "Physical presence"      "still needed (power button)"
                printf "  %-26s %s\n" "Reboot during open"     "TI50 reboots - expected"
                printf "  %-26s %s\n" "Version prefix"         "0.2.x=TI50  0.6.x=CR50"
                printf "  %-26s %s\n" "Device node"            "/dev/ti50  vs  /dev/cr50"
                printf "  %-26s %s\n" "gsctool flags"          "same flags, same syntax"
                printf "  %-26s %s\n" "SuzyQ"                  "same cable, same process"
                sep
                printf "\n"
                pause
                ;;
            4|-1) return ;;
        esac
    done
}

GSC_TYPE=""

# Startup detection screen
startup_detect() {
    step_header "Detecting GSC..."
    GSC_TYPE=$(detect_gsc)
    local _wp
    _wp=$(check_wp)

    if [ "$GSC_TYPE" = "cr50" ]; then
        ok "CR50 (H1)"
    elif [ "$GSC_TYPE" = "ti50" ]; then
        ok "TI50"
    else
        warn "GSC not detected - you'll pick manually"
    fi

    printf "\n"
    if [ "$_wp" = "0" ]; then
        ok "wpsw_cur=0  WP already off"
    else
        warn "wpsw_cur=${_wp:-?}  WP on"
    fi
    printf "\n"
    sleep 1
    pause
}

# Main menu
main() {
    startup_detect

    while true; do
        if [ "$GSC_TYPE" = "cr50" ]; then
            arrow_menu "Scribble Protection  [CR50]" \
                "CR50 write-protect methods" \
                "Exit"
            case "$ARROW_RESULT" in
                0) menu_cr50 ;;
                1|-1) break ;;
            esac
        elif [ "$GSC_TYPE" = "ti50" ]; then
            arrow_menu "Scribble Protection  [TI50]" \
                "TI50 write-protect methods" \
                "Exit"
            case "$ARROW_RESULT" in
                0) menu_ti50 ;;
                1|-1) break ;;
            esac
        else
            arrow_menu "Scribble Protection  [select chip]" \
                "CR50" \
                "TI50" \
                "Exit"
            case "$ARROW_RESULT" in
                0) GSC_TYPE="cr50"; menu_cr50 ;;
                1) GSC_TYPE="ti50"; menu_ti50 ;;
                2|-1) break ;;
            esac
        fi
    done

    clear
    printf "\n"
}

main
