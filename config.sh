#!/usr/bin/env bash
set -euo pipefail
set -x 

check_root () {
    if [[ "$EUID" -ne 0 ]]; then
       echo "You must be root to do this." 1>&2
       exit 1
    fi
}

check_steamos () {
    . /etc/os-release
    if [ "$ID" != "steamos" ]; then
        echo -e "This script for SteamOS only! Exiting..."
        exit 1
    fi

}

disable_ro () {
    # check if system is ro and remount to rw
    echo "Checking fs ro/rw..."
    if [ "$(steamos-readonly status)" = "enabled" ]; then
        steamos-readonly disable
        echo "steamos rw enabled"
    fi
}
############################
## TO DO: 
## update pacman.conf from repo
## add pacman-key --init
##     pacman-key --populate
############################

check_fakeroot_files () {
    # clean fakeroot install
    fakeroot_conf="/etc/ld.so.conf.d/fakeroot.conf"
    if [ -f "${fakeroot_conf}" ]; then
        rm -f "${fakeroot_conf}"
    fi
}

install_devel () {
    # install minimal devel deps
    echo "installing base-devel package..."
    pacman -S --needed --noconfirm --disable-download-timeout base-devel
}

disable_passwd () {
    echo "Temporary disabling passwd check..."
    SUDO_PATH="/etc/sudoers.d/wheel"
    WHEEL_OLD="%wheel ALL=(ALL) ALL"
    WHEEL_NEW="%wheel ALL=(ALL:ALL) NOPASSWD: ALL"
    # avoid asking password
    sed -i "s/$WHEEL_OLD/$WHEEL_NEW/g" "$SUDO_PATH"
}

install_yay () {
    echo "Installing yay..."
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
#         yes | yay -Syu --devel && \
         yay -Y --devel --save && \
         yay --editmenu --nodiffmenu --save"
}

install_programs () {
    echo "Installing additional apps..."
    # my programs
    # need to reinstall glibc for correct generating locales
    for mc_files in "/etc/mc/mc.default.keymap" "/etc/mc/mc.emacs.keymap"; do
        if [ -f "$mc_files" ]; then
            rm -f "$mc_files"
        fi
    done 
    su - "$SUDO_USER" -c "echo y | LANG=C yay -S \
         --noprovides \
         --needed \
         --answerdiff None \
         --answerclean None \
         --mflags \"--noconfirm\" btop dust duf bat micro lsd gdu fd mc"   
}

# deprecated
# in steamos => 3.5.5 many locales added by default
add_locale () {
    # add locale
    su - "$SUDO_USER" -c "echo y | LANG=C yay -S \
         --noprovides \
         --answerdiff None \
         --answerclean None \
         --mflags \"--noconfirm\" glibc"
    sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' /etc/locale.gen
    sed -i 's/#ru_RU.UTF-8 UTF-8/ru_RU.UTF-8 UTF-8/g' /etc/locale.gen
    locale-gen
}

enable_passwd () {
    echo "Enabling asking passwd..."
    # enable asking password
    sed -i "s/$WHEEL_NEW/$WHEEL_OLD/g" "$SUDO_PATH"
}

check_mitigations () {
    echo "Checking mitigations status..."
    # check mitigations=off
    # if not - adding option to kernel command line to disable mitigations
    grep . /sys/devices/system/cpu/vulnerabilities/*
    if grep -q "mitigations=off" /boot/efi/EFI/steamos ; then 
        echo -e "\nmitigations=off in /boot/efi/EFI/steamos exist !\n"
    else
        while true; do
            read -p "Mitigation not found in grub config. enable mitigations=off ?" answer
            case $answer in
                [Yy]* ) sed -i 's/\bGRUB_CMDLINE_LINUX_DEFAULT="/&mitigations=off /' /etc/default/grub
                        grub-mkconfig -o /boot/efi/EFI/steamos/grub.cfg
                        break;;
                [Nn]* ) break;;
                * ) echo "Please answer yes or no.";;
            esac
        done
    fi
}

main () {
    check_root
    disable_ro
    check_fakeroot_files
    install_devel
    disable_passwd
    install_yay
    install_programs
# deprecated
#    add_locale
    check_mitigations
    enable_passwd
    echo "Done"
}

main
