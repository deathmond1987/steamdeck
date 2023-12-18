#!/usr/bin/env bash
########### opts ###########
set -euo pipefail
# set -x 
reset=$(tput sgr0)

red=$(tput setaf 1)
green=$(tput setaf 2)
tan=$(tput setaf 3)

success() { printf "${green}    ✔ %s${reset}\n" "$@"
}
error() { printf "${red}    ✖ %s${reset}\n" "$@"
}
warn() { printf "${tan}    ➜ %s${reset}\n" "$@"
}

########### BODY ############

check_root () {
    if [[ "$EUID" -ne 0 ]]; then
       error "You must be root to do this." 1>&2
       exit 1
    fi
}

check_steamos () {
    . /etc/os-release
    if [ "$ID" != "steamos" ]; then
        error "This script for SteamOS only! Exiting..."
        exit 1
    fi

}

disable_ro () {
    # check if system is ro and remount to rw
    warn "Checking fs ro/rw..."
    if [ "$(steamos-readonly status)" = "enabled" ]; then
        steamos-readonly disable
        success "steamos rw enabled"
    fi
}
############################
## TO DO: 
## update pacman.conf from repo
############################

init_pacman () {
    warn "initializing pacman DB"
    pacman-key --init
    pacman-key --populate
    pacman -Sy
    success "Done"
}

install_devel () {
    # install minimal devel deps
    warn "installing base-devel package..."
    pacman -S --needed --noconfirm --disable-download-timeout base-devel
    success "Done"
}

disable_passwd () {
    warn "Temporary disabling passwd check..."
    SUDO_PATH="/etc/sudoers.d/wheel"
    WHEEL_OLD="%wheel ALL=(ALL) ALL"
    WHEEL_NEW="%wheel ALL=(ALL:ALL) NOPASSWD: ALL"
    # avoid asking password
    sed -i "s/$WHEEL_OLD/$WHEEL_NEW/g" "$SUDO_PATH"
}

enable_passwd () {
    warn "Enabling asking passwd..."
    # enable asking password
    sed -i "s/$WHEEL_NEW/$WHEEL_OLD/g" "$SUDO_PATH"
}

install_yay () {
    if ! command -v yay >/dev/null 2>&1 ; then 
        warn "Installing yay..."
        yay_git="\"$HOME\"/yay-bin"
        # clean yay install
        if [ -d "${yay_git}" ]; then
            rm -rf "${yay_git}"
        fi
        # yay install
        su - "$SUDO_USER" -c "git clone https://aur.archlinux.org/yay-bin && \
            cd yay-bin && \
            yes | makepkg -si && \
            cd .. && \
            rm -rf yay-bin && \
            yay -Y --gendb && \
            yay -Y --devel --save && \
            yay --editmenu --nodiffmenu --save"
        rm -rf "$yay_git"
        success "Done"
    else
        success "yay already installed. Skipping..."
    fi
}

install_programs () {
    warn "Installing additional apps..."
    # my programs
    # THIS IS ALSO BAD IDEA 
    #for mc_files in "/etc/mc/mc.default.keymap" "/etc/mc/mc.emacs.keymap"; do
    #    if [ -f "$mc_files" ]; then
    #        rm -f "$mc_files"
    #    fi
    #done 
    su - "$SUDO_USER" -c "echo y | LANG=C yay -S \
         --provides=false \
         --needed \
         --answerdiff None \
         --answerclean None \
         --mflags \"--noconfirm\" btop dust duf bat micro lsd gdu fd mc"   
    success "Done"
}

check_mitigations () {
    warn "Checking mitigations status..."
    # check mitigations=off
    # if not - adding option to kernel command line to disable mitigations
    #grep . /sys/devices/system/cpu/vulnerabilities/*
    GRUB_CONF=/boot/efi/EFI/steamos/grub.cfg
    if grep -q "mitigations=off" "$GRUB_CONF" ; then 
        success "mitigations=off in "$GRUB_CONF" exist !"
    else
        while true; do
            read -p "Mitigation not found in grub config. enable mitigations=off ? " answer
            case $answer in
                [Yy]* ) sed -i 's/\bGRUB_CMDLINE_LINUX_DEFAULT="/&mitigations=off /' /etc/default/grub
                        grub-mkconfig -o "$GRUB_CONF"
                        break;;
                [Nn]* ) break;;
                * ) error "Please answer yes or no.";;
            esac
        done
    fi
    success "Done"
}

main () {
    check_root
    disable_ro
    init_pacman
    install_devel
    disable_passwd
    trap 'enable_passwd' ERR
    install_yay
    install_programs
    enable_passwd
    trap '' ERR
    check_mitigations
}

main
