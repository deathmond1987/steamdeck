#!/usr/bin/env bash

set -xe

#echo "./steamos.qcow2 file found. Loading SteamOS. If you need to reinstall SteamOs - remove ./steamos.qcow2 file"

# get pid of qemu
QEMU_PID=$(ps -aux | grep qemu | grep steamos | awk '{ print $2 }')

# kill that pid if exist
if [ ! -z "$QEMU_PID" ]; then
    echo "./steamos.qcow2 already in use. Killing qemu with $QEMU_PID pid"
    sudo kill "$QEMU_PID"
fi

# in arch linux OVMF in non standart path
EDK_PATH="/usr/share/edk2/x64"

install_steamos () {
    STEAMDECK_IMG_PATH="./steamdeck.img"
    STEAMDECK_BZ2_PATH="${STEAMDECK_IMG_PATH}.bz2"
    # if there is no bz2 archive and img - loading steamos.img.bz2
    if [ ! -f "$STEAMDECK_BZ2_PATH" ] && [ ! -f "$STEAMDECK_IMG_PATH" ]; then
        echo "Downloading SteamOS recovery image..."
        curl -o "$STEAMDECK_BZ2_PATH" https://steamdeck-images.steamos.cloud/recovery/steamdeck-recovery-4.img.bz2
    fi
    # unpacking bz2 if there is no img
    if [ ! -f "$STEAMDECK_IMG_PATH" ]; then
        echo "Unpacking SteamOS image..."
        cat "$STEAMDECK_BZ2_PATH" | bzcat > "$STEAMDECK_IMG_PATH"
    fi

    # creting qcow2 hdd
    qemu-img create -f qcow2 steamos.qcow2 64G
    # executing qemu with hdd and img
    # steamos need nvme for install
    qemu-system-x86_64 -enable-kvm -smp cores=4 -m 8G \
                       -device usb-ehci -device usb-tablet \
                       -device intel-hda -device hda-duplex \
                       -device VGA,xres=1280,yres=800 \
                       -drive if=pflash,format=raw,readonly=on,file="$EDK_PATH"/OVMF.fd \
                       -drive if=virtio,file="$STEAMDECK_IMG_PATH",driver=raw \
                       -device nvme,drive=drive0,serial=badbeef \
                       -drive if=none,id=drive0,file=steamos.qcow2 \
                       -device virtio-net-pci,netdev=net0 \
                       -netdev user,id=net0,hostfwd=tcp::55555-:22 & sleep 3

    # if thin not first install we need to clear ssh known_hosts
    if grep "127.0.0.1]:55555" /home/"$USER"/.ssh/known_hosts; then
        echo "Detected old key in known_hosts. Removing"
        sed -i 's/.*127.0.0.1]:55555.*//g' /home/"$USER"/.ssh/known_hosts
    fi

    echo -e "SteamOS installer is loading\n"
    echo -e "You need change deck users passwd and enable sshd:"
    echo -e "passwd deck"
    echo -e "sudo systemctl enable --now sshd"
    echo ""
    # give some time to manipulate in vm
    read -n 1 -s -r -p "Now you need wait till SteamOS is loaded and then press any key to continue"
    echo ""

    # executing in vm
    ssh deck@127.0.0.1 -p 55555 <<-EOF
        set -ex
        # removing zenity from install script. We do not have graphical interface
        sed -i 's/.*zenity.*/true/g' /home/deck/tools/repair_device.sh
        # we does not want to reboot
        sed -i 's/.*cmd systemctl reboot.*/true/g' /home/deck/tools/repair_device.sh
#  sudo steamos-readonly disable
#        sudo sed -i 's/.*mount -o ro.*/mount -o rw "$ROOTFS_DEVICE" $dir/g' /usr/bin/steamos-chroot
#        sudo cp -a /usr/bin/steamos-chroot /home/deck/
#sudo sed -i 's/.*mount -o ro.*/mount -o rw "$ROOTFS_DEVICE" $dir/g' /home/deck/steamos-chroot
#  sudo umount -l /etc
        echo -e '[Autologin]\nSession=plasma.desktop' > /home/deck/steamos.conf
        sudo chown root:root /home/deck/steamos.conf
#  sudo steamos-readonly enable
        # executing install script
        /home/deck/tools/repair_reimage.sh
        mkdir /home/deck/mnt
        sudo mount -o rw /dev/nvme0n1p4 /home/deck/mnt
        sudo cp -a /home/deck/steamos.conf /home/deck/mnt/etc/sddm.conf.d/
        sudo umount -l /home/deck/mnt
        sudo mount -o rw /dev/nvme0n1p5 /home/deck/mnt
        sudo cp -a /home/deck/steamos.conf /home/deck/mnt/etc/sddm.conf.d/
        sudo umount -l /home/deck/mnt
#        sudo /home/deck/steamos-chroot --disk /dev/nvme0n1 --partset A -- 'echo' '[Autologin]' > '/etc/sddm.conf.d/steamos.conf' && 'echo' 'Session=plasma.desktop' >> '/etc/sddm.conf.d/steamos.conf'
#        sudo /home/deck/steamos-chroot --disk /dev/nvme0n1 --partset B -- 'echo' '[Autologin]' '>' '/etc/sddm.conf.d/steamos.conf' '&&' 'echo' 'Session=plasma.desktop' '>>' '/etc/sddm.conf.d/steamos.conf'
#        sudo steamos-chroot --disk /dev/nvme0n1 --partset A -- 'echo' '[Autologin]' '>' '/etc/sddm.conf.d/steamos.conf'
#        sudo steamos-chroot --disk /dev/nvme0n1 --partset A -- 'echo' 'Session=plasma.desktop' '>>' '/etc/sddm.conf.d/steamos.conf'
#        sudo steamos-chroot --disk /dev/nvme0n1 --partset A -- "steamos-readonly enable'
#        sudo steamos-chroot --disk /dev/nvme0n1 --partset B -- 'mount' '-o' 'remount,rw' '/' '/'
#        sudo steamos-chroot --disk /dev/nvme0n1 --partset B -- 'echo' '[Autologin]' '>' '/etc/sddm.conf.d/steamos.conf'
#        sudo steamos-chroot --disk /dev/nvme0n1 --partset B -- 'echo' 'Session=plasma.desktop' '>>' '/etc/sddm.conf.d/steamos.conf'
#        sudo steamos-chroot --disk /dev/nvme0n1 --partset B -- "steamos-readonly enable"

echo "
sudo steamos-chroot --disk /dev/nvme0n1 --partset other -- \"steamos-readonly disable\"
sudo steamos-chroot --disk /dev/nvme0n1 --partset other -- \"echo [Autologin] > /etc/sddm.conf.d/steamos.conf\"
sudo steamos-chroot --disk /dev/nvme0n1 --partset other -- \"echo Session=plasma.desktop >> /etc/sddm.conf.d/steamos.conf\"
sudo steamos-chroot --disk /dev/nvme0n1 --partset other -- \"steamos-readonly enable" > /home/deck/post-install.sh

#       sudo systemctl poweroff
EOF


exit 1
    cp "$EDK_PATH"/OVMF_VARS.fd ./OVMF_VARS.fd
}

run_steamos () {
    qemu-system-x86_64 -enable-kvm -smp cores=4 -m 8G \
                       -device usb-ehci -device usb-tablet \
                       -device intel-hda -device hda-duplex \
                       -device VGA,xres=1280,yres=800 \
                       -drive if=pflash,format=raw,readonly=on,file="$EDK_PATH"/OVMF.fd \
                       -drive if=pflash,format=raw,file=./OVMF_VARS.fd \
                       -drive if=virtio,file=steamos.qcow2 \
                       -device virtio-net-pci,netdev=net0 \
                       -netdev user,id=net0,hostfwd=tcp::55555-:22
}

if [ -f ./steamos.qcow2 ]; then
    run_steamos
else
    install_steamos
    run_steamos
fi
    run_steamos
fi
