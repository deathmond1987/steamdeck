#!/usr/bin/env bash
########### opts ###########
set -eo pipefail
set -x
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
install_script () {
    script_path=/home/deck/install_from_aur.sh
        if [ ! -f "$script_path" ]; then
            warn "script not found. Downloading..."
            wget -qO "$script_path" https://raw.githubusercontent.com/deathmond1987/steamdeck/refs/heads/main/install_from_aur.sh
            success "done"
    fi
    if [ ! "$(stat -c %a "$script_path")" = "700" ]; then
        warn "script not executable. fixing..."
        chmod 700 "$script_path"
        success "done. re-run script with arg to install package from AUR"
        warn "example: sudo ./install_from_aur.sh spotify"
        exit 0
    fi
}

check_params () {
    while [ "$1" != "" ]; do
        case "$1" in
           install|-i) yay_opts="-S --noconfirm --overwrite \*"
                       shift
                       while [ "$1" != "" ]; do
                           package+=("$1")
                           shift
                       done
                       ;;
            remove|-r) yay_opts="-R"
                       shift
                       while [ "$1" != "" ]; do
                           package+=("$1")
                           shift
                       done
                       ;;
                    *) yay_opts="--answerdiff None --answerclean None --noconfirm --needed"
                       while [ "$1" != "" ]; do
                           package+=("$1")
                           shift
                       done
                       ;;
        esac
        package+=("$@")
    done
packages=${package[*]}
}

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
        success "steamos rw enabled. Done"
    else
        success "steamos already in rw. Done"
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
    steamos-readonly enable
}

init_yay () {
    alpm_version=$(pacman -V | grep libalpm | cut -f3 -d "v" | cut -f1 -d".")
    ## yay_version=$(yay --version | grep libalpm | cut -f3 -d "v" | cut -f1 -d".")
    yay_bin_dir=/home/deck/yay_bin
    if [ -d $yay_bin_dir ]; then
        rm -rf $yay_bin_dir
    fi
    ## currently steamos is very old.
    ##we need to find yay binary that linked to current libalpm
    case $alpm_version in
        13) git_head=96f9018
            ;;
        14) git_head=02b6d80
            ;;
        15) git_head=master
            ;;
        *) echo "script doesnt know nothing about libalpm version $alpm_version"
           exit 1
            ;;
    esac

    warn "alpm version: $alpm_version . selected yay git head: $git_head"
    su - "$SUDO_USER" -c "git clone https://aur.archlinux.org/yay-bin $yay_bin_dir
                          cd $yay_bin_dir &&\
                          git checkout $git_head &&\
                          makepkg -s --noconfirm"
    cd $yay_bin_dir
    ## biggest fuckup ever. makeself cant give parameters to pacman
    pacman -U --noconfirm --overwrite "/*" *.zst
    cd ..
    su - "$SUDO_USER" -c "yay -Y --gendb &&\
                          yay -Y --devel --save"
    rm -rf "$yay_bin_dir"
}

install_yay () {
    if ! command -v yay >/dev/null 2>&1 ; then
        init_yay
    else
        alpm_version=$(pacman -V | grep libalpm | cut -d "v" -f 3| tr -d '\n')
        yay_alpm_version=$(yay --version |cut -d"v" -f3| tr -d '\n')
        if [ ! "$yay_alpm_version" = "$alpm_version" ]; then
            init_yay
        else
            success "yay already installed. Skipping..."
        fi
    fi
}

install_programs () {
    warn "Work with selected package: $packages"
    su - "$SUDO_USER" -c "LANG=C yay $yay_opts $packages"
    success "Done"
}

main () {
    # check_root disable_ro and init_pacman can be replaced by steamos-devmode enable
    # also steamos_devmode reinstalls all installed packages by
    ## pacman --noconfirm -S $(pacman -Qnkq | cut -d' ' -f1 | sort | uniq)
    # this return to system prunned package headers
    install_script
    check_params "$@"
    check_root
    check_steamos
    disable_ro
    init_pacman
    install_devel
    disable_passwd
    trap 'enable_passwd' ERR INT
    install_yay
    install_programs "$@"
    enable_passwd
    trap '' ERR
}

main "$@"
