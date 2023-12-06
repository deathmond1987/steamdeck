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
                       -netdev user,id=net0,hostfwd=tcp::55555-:22 --daemonize

    # if thin not first install we need to clear ssh known_hosts
    if grep "127.0.0.1]:55555" /home/"$USER"/.ssh/known_hosts; then
        echo "Detected old key in known_hosts. Removing"
        sed -i 's/.*127.0.0.1]:55555.*//g' /home/"$USER"/.ssh/known_hosts
    fi

    echo -e "SteamOS installer is loading\n"
    echo "In default qemu now opens new window with SteamOS"
    echo "In headless qemu you need external vnc to connect to 127.0.0.1:55555"
    echo  "You need change deck users passwd and enable sshd:"
    echo  "passwd <<--type password for default user"
    echo  "sudo systemctl enable --now sshd"
    echo ""
    # give some time to manipulate in vm
    read -n 1 -s -r -p "Press any key to connect ssh. After that agree with new key and enter password"
    echo ""

    # executing in vm
    ssh deck@127.0.0.1 -p 55555 <<-EOF
        set -ex
        # removing zenity from install script. We do not have graphical interface
        sed -i 's/.*zenity.*/true/g' /home/deck/tools/repair_device.sh
        # we does not want to reboot
        sed -i 's/.*cmd systemctl reboot.*/true/g' /home/deck/tools/repair_device.sh
        # creating sddm config overwrite
        echo -e '[Autologin]\nSession=plasma.desktop' > /home/deck/steamos.conf
        sudo chown root:root /home/deck/steamos.conf
        # executing install script
        /home/deck/tools/repair_reimage.sh
        # creating mountpoint
        mkdir /home/deck/mnt
        # mounting btrfs root A
        sudo mount -o rw /dev/nvme0n1p4 /home/deck/mnt
        # disabling btrfs ro property for A
        sudo btrfs property set /home/deck/mnt ro false
        # Copying new sddm config to side A
        sudo cp -a /home/deck/steamos.conf /home/deck/mnt/etc/sddm.conf.d/
        # unmounting side A
        sudo umount -l /home/deck/mnt
        # lazymount await
        sleep 3
        # for side B
        sudo mount -o rw /dev/nvme0n1p5 /home/deck/mnt
        sudo btrfs property set /home/deck/mnt ro false
        sudo cp -a /home/deck/steamos.conf /home/deck/mnt/etc/sddm.conf.d/
        sudo umount -l /home/deck/mnt
        sleep 3
######################################################################################################################################
## У steamdeck AB ro файловая система btrfs.
## За атомарное обновление отвечает rauc
## Так как режим игровой режим steam не работает из коробки - необходимо загружаться в kde
## Для этого нужно изменять /etc/sddm.conf.d/steamos.conf после каждого обновления в слоте который был обновлен
## У rauc для этого есть post-install.sh скрипт в котором происходит завершение обновления
## Можно попробовать внедрить туда код который будет после полного обновления:
## 1. обновлять на соседнем слоте post-install.sh скрипт чтобы при следующем обновлении заменить новый post-install.sh (survival mode)
## 2. обновлять на соседнем слоте /etc/sddm.conf.d/steamos.conf чтобы сессия менялась на kde
## 3. может быть включать sshd по умолчанию
## Суть проблемы в том что атомарное обновление затирает полностью все изменения в слоте.
## По умолчанию включается игровой режим который не может загрузиться в qemu и становится неработоспособной
## Необходимо либо патчить вышеуказанным образом либо включать sshd (который по умолчанию всегда выключен) и вносить правки в sddm вручную
######################################################################################################################################
        # without exit - this script is wailing with 255 code
        nohup sudo bash -c "sleep 3 && systemctl poweroff" &
        exit
EOF

    while ps -aux | grep qemu | grep steamos 2>&1 >/dev/null ; do
        echo -e "Looks like VM is not shutdown for now. Waiting to gracefully shutdown..."
        sleep 3
    done
    cp "$EDK_PATH"/OVMF_VARS.fd ./OVMF_VARS.fd
}

run_steamos () {
    qemu-system-x86_64 -enable-kvm -smp cores=4 -m 8G \
                       -device usb-ehci -device usb-tablet \
                       -device intel-hda -device hda-duplex \
                       -device VGA,xres=1280,yres=800 \
                       -drive if=pflash,format=raw,readonly=on,file="$EDK_PATH"/OVMF.fd \
                       -drive if=pflash,format=raw,file=./OVMF_VARS.fd \
                       -device nvme,drive=drive0,serial=badbeef \
                       -drive if=none,id=drive0,file=steamos.qcow2 \
#                       -drive if=virtio,file=steamos.qcow2 \
                       -device virtio-net-pci,netdev=net0 \
                       -netdev user,id=net0,hostfwd=tcp::55555-:22 --daemonize
}

if [ -f ./steamos.qcow2 ]; then
    run_steamos
else
    install_steamos
    run_steamos
fi
