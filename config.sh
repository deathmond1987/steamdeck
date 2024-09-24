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

# or maybe just use user env. maybe brew or nix...
disable_ro () {
    # check if system is ro and remount to rw
    warn "Checking fs ro/rw..."
    fs_status=$(steamos-readonly status || true)
    if [ "$fs_status" = "enabled" ]; then
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
    pacman -Sy --noconfirm --needed archlinux-keyring
    success "Done"

#    if [ ! -f $HOME/pacman.conf ]; then
#        # vavle playing with repo links. enshure that we have latest repo links
#        warn "pacman.conf not found in $HOME dir"
#        warn "Downloading latest pacman package config..."
#        rm -rf /var/cache/pacman/pkg/*
#        pacman -Sw --noconfirm pacman
#        tar -xf /var/cache/pacman/pkg/pacman*.pkg.tar.zst \
#            etc/pacman.conf \
#            -C /home/"$SUDO_USER" \
#            --strip-components 1 \
#            --numeric-owner
#        mv /etc/pacman.conf /etc/pacman.conf.old
#        cp /home/"$SUDO_USER"/pacman.conf /etc/
#        success "Done"
#    fi
    
}

install_devel () {
    # install minimal devel deps
    warn "installing base-devel package..."
    pacman -S --needed --noconfirm --disable-download-timeout --overwrite \* base-devel
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

init_yay () {
    warn "Installing yay..."
    ## yay install
    ## check alpm so exist. if old - then installing old yay
    alpm_version=$(pacman -V | grep libalpm | cut -f3 -d "v" | cut -f1 -d".")
    if [ "${alpm_version}" -ge "15" ] ; then
        warn "Libalpm.so.14 not found. Installing modern yay"
        yay_git=$HOME/yay-bin
        # clean yay install    
        if [ -d "${yay_git}" ]; then
            rm -rf "${yay_git}"
        fi
        su - "$SUDO_USER" -c "git clone https://aur.archlinux.org/yay-bin && \
            cd ${yay_git} && \
            yes | makepkg -si && \
            cd .. && \
            rm -rf ${yay_git} && \
            yay -Y --gendb && \
            yay -Y --devel --save"
    else
        warn "Libalpm.so.14 found. install yay 12.3.1"
        yay_git=$HOME/yay
        pacman -S go --needed --noconfirm
        # clean yay install    
        if [ -d "${yay_git}" ]; then
            rm -rf "${yay_git}"
        fi
        su - "$SUDO_USER" -c "git clone https://github.com/Jguer/yay --branch=v12.3.1 && \
            cd ${yay_git} && \
            yes | makepkg -si && \
            cd .. && \
            rm -rf ${yay_git} && \
            yay -Y --gendb && \
            yay -Y --devel --save"
        pacman -R --noconfirm go
    fi
    rm -rf "$yay_git"
    success "Done"
}

install_yay () {
    if ! command -v yay >/dev/null 2>&1 ; then 
        init_yay
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
         --mflags \"--noconfirm\" --overwrite \* btop dust duf bat micro lsd gdu fd mc"   
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
    # check_root disable_ro and init_pacman can be replaced by steamos-devmode enable
    # also steamos_devmode reinstalls all installed packages by 
    ## pacman --noconfirm -S $(pacman -Qnkq | cut -d' ' -f1 | sort | uniq)
    # this return to system prunned package headers
    check_root
    check_steamos
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
