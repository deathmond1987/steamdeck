#!/usr/bin/env bash
set -euo pipefail
set -x 

# check if system is ro and remount to rw
if [ "$(steamos-readonly status)" = "enabled" ]; then
    steamos-readonly disable
fi
# clean fakeroot install
fakeroot_conf="/etc/ld.so.conf.d/fakeroot.conf"
if [ -f "${fakeroot_conf}" ]; then
    rm -f "${fakeroot_conf}"
fi

# install minimal devel deps
pacman -S --needed --noconfirm --disable-download-timeout base-devel

# clean yay install
yay_git="/home/deck/yay-bin"
if [ -d "${yay_git}" ]; then
    rm -rf "${yay_git}"
fi
# avoid asking password
sed -i 's/%wheel ALL=(ALL) ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/g' /etc/sudoers.d/wheel

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
# my programs
su - deck -c "echo y | LANG=C yay -S \
            --noprovides \
            --answerdiff None \
            --answerclean None \
            --mflags \"--noconfirm\" btop dust duf bat micro lsd gdu fd mc"

# enable asking password
sed -i 's/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL) ALL/g' /etc/sudoers.d/wheel
exit 
