#!/usr/bin/env bash
set -euo pipefail
set -x 

disable_ro () {
# check if system is ro and remount to rw
    if [ "$(steamos-readonly status)" = "enabled" ]; then
        steamos-readonly disable
    fi
}

check_fakeroot_files () {
    # clean fakeroot install
    fakeroot_conf="/etc/ld.so.conf.d/fakeroot.conf"
    if [ -f "${fakeroot_conf}" ]; then
        rm -f "${fakeroot_conf}"
    fi
}

install_devel () {
    # install minimal devel deps
    pacman -S --needed --noconfirm --disable-download-timeout base-devel
}

disable_passwd () {
    # avoid asking password
    sed -i 's/%wheel ALL=(ALL) ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/g' /etc/sudoers.d/wheel
}

install_yay () {
    # clean yay install
    yay_git="/home/deck/yay-bin"
    if [ -d "${yay_git}" ]; then
        rm -rf "${yay_git}"
    fi
    # yay install
    su - deck -c "git clone https://aur.archlinux.org/yay-bin && \
         cd yay-bin && \
         yes | makepkg -si && \
         cd .. && \
         rm -rf yay-bin && \
         yay -Y --gendb && \
         yes | yay -Syu --devel && \
         yay -Y --devel --save && \
         yay --editmenu --nodiffmenu --save"
}

install_programs () {
    # my programs
    # need to reinstall glibc for correct generating locales
    su - deck -c "echo y | LANG=C yay -S \
         --noprovides \
         --answerdiff None \
         --answerclean None \
         --mflags \"--noconfirm\" btop dust duf bat micro lsd gdu fd mc glibc"
}

add_locale () {
    # add locale
    sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' /etc/locale.gen
    locale-gen
}

enable_passwd () {
    # enable asking password
    sed -i 's/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL) ALL/g' /etc/sudoers.d/wheel
}

main () {
     disable_ro
     check_fakeroot_files
     install_devel
     disable_passwd
     install_yay
     install_programs
     add_locale
     enable_passwd
}

main
