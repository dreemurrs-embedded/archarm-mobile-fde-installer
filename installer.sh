#!/bin/bash

# Copyright 2020 - DanctNIX Community
#
# This script setup FDE on Arch Linux ARM for PinePhone
# and PineTab.
#
# Inspired by:
# https://github.com/sailfish-on-dontbeevil/flash-it

set +e

DOWNLOAD_SERVER="https://danctnix.arikawa-hi.me/rootfs/archarm-on-mobile"
TMPMOUNT=$(mktemp -p . -d)

# Parse arguments
# https://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash
POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -h|--help)
        echo "Arch Linux ARM for PP/PT Encrypted Setup"
        echo ""
        printf '%s\n' \
               "This script will download the latest encrypted image for the" \
               "PinePhone and PineTab. It downloads and create a image for the user" \
               "to flash on their device or SD card." \
               "" \
               "usage: $0 " \
               "" \
               "Options:" \
               "" \
               "	-h, --help		Print this help and exit." \
               "" \
               "This command requires: parted, curl, sudo, wget, tar, unzip," \
               "mkfs.ext4, mkfs.f2fs, losetup, unsquashfs." \
               ""

        exit 0
        shift
        ;;
    *) # unknown argument
        POSITIONAL+=("$1") # save it in an array for later
        shift # past argument
        ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

# Helper functions
# Error out if the given command is not found in PATH.
function check_dependency {
    dependency=$1
    hash $dependency >/dev/null 2>&1 || {
        echo >&2 "${dependency} not found. Please make sure it is installed and on your PATH."; exit 1;
    }
}

function error {
    echo -e "\e[41m\e[5mERROR:\e[49m\e[25m $1"
}

# Check dependencies
check_dependency "parted"
check_dependency "cryptsetup"
check_dependency "sudo"
check_dependency "wget"
check_dependency "tar"
check_dependency "unsquashfs"
check_dependency "mkfs.ext4"
check_dependency "mkfs.f2fs"
check_dependency "losetup"
check_dependency "zstd"
check_dependency "curl"

# Image selection
echo -e "\e[1mWhich image do you want to create?\e[0m"
select OPTION in "PinePhone" "PineTab"; do
    case $OPTION in
        "PinePhone" ) DEVICE="pinephone"; break;;
        "PineTab" ) DEVICE="pinetab"; break;;
    esac
done

echo -e "\e[1mWhich environment would you like to install?\e[0m"
select OPTION in "Phosh" "Barebone"; do
    case $OPTION in
        "Phosh" ) USR_ENV="phosh"; break;;
        "Barebone" ) USR_ENV="barebone"; break;;
    esac
done

SQFSROOT="archlinux-$DEVICE-$USR_ENV.sqfs"

# Filesystem selection
echo -e "\e[1mWhich filesystem would you like to use?\e[0m"
select OPTION in "ext4" "f2fs"; do
    case $OPTION in
        "ext4" ) FILESYSTEM="ext4"; break;;
        "f2fs" ) FILESYSTEM="f2fs"; break;;
    esac
done

# Select flash target
echo -e "\e[1mWhich SD card do you want to flash?\e[0m"
lsblk
read -p "Device node (/dev/sdX): " DISK_IMAGE
echo "Flashing image to: $DISK_IMAGE"
echo "WARNING: All data will be erased! You have been warned!"
echo "Some commands require root permissions, you might be asked to enter your sudo password."

# Make sure people won't pick the wrong thing and ultimately erase the disk
echo
echo -e "\e[31m\e[1mARE YOU SURE \e[5m\e[4m${DISK_IMAGE}\e[24m\e[25m IS WHAT YOU PICKED?\e[39m\e[0m"
read -p "Confirm device node: " CONFIRM_DISK_IMAGE
[ "$DISK_IMAGE" != "$CONFIRM_DISK_IMAGE" ] && error "The device node mismatched. Aborting." && exit 1
echo

# Downloading images
echo -e "\e[1mDownloading images...\e[0m"

wget --quiet --show-progress -c -O $SQFSROOT $DOWNLOAD_SERVER/$SQFSROOT || {
    error "Root filesystem image download failed. Aborting."
    exit 2
}

# Checksum check, make sure the root image is the real deal.
curl --silent --progress-meter $DOWNLOAD_SERVER/$SQFSROOT.sha512sum | sha512sum -c || { error "Checksum does not match. Aborting." && rm $SQFSROOT && exit 1; }

wget --quiet --show-progress -c -O arch-install-scripts.tar.zst "https://archlinux.org/packages/extra/any/arch-install-scripts/download/" || {
	error "arch-install-scripts download failed. Aborting."
	exit 2
}

tar --transform='s,^\([^/][^/]*/\)\+,,' -xf arch-install-scripts.tar.zst usr/bin/genfstab
chmod +x genfstab

[ ! -e "genfstab" ] && error "Failed to locate genfstab. Aborting." && exit 2

[ $FILESYSTEM = "ext4" ] && MKFS="mkfs.ext4"
[ $FILESYSTEM = "f2fs" ] && MKFS="mkfs.f2fs"

sudo parted -a optimal ${DISK_IMAGE} mklabel msdos --script
sudo parted -a optimal ${DISK_IMAGE} mkpart primary fat32 '0%' 256MB --script
sudo parted -a optimal ${DISK_IMAGE} mkpart primary ext4 256MB 100% --script
sudo parted ${DISK_IMAGE} set 1 boot on --script

# The first partition is the boot partition and the second one the root
PARTITIONS=$(lsblk $DISK_IMAGE -l | grep ' part ' | awk '{print $1}')
BOOTPART=/dev/$(echo "$PARTITIONS" | sed -n '1p')
ROOTPART=/dev/$(echo "$PARTITIONS" | sed -n '2p')

ENCRYNAME=$(basename $(mktemp -p /dev/mapper/ -u))
ENCRYPART="/dev/mapper/$ENCRYNAME"

echo "You'll now be asked to type in a new encryption key. DO NOT LOSE THIS!"

# Generating LUKS header on a modern computer would make the container slow to unlock
# on slower devices such as PinePhone.
#
# Unless you're happy with the phone taking an eternity to unlock, this is it for now.
sudo cryptsetup -q -y -v luksFormat --pbkdf-memory=20721 --pbkdf-parallel=4 --pbkdf-force-iterations=4 $ROOTPART
sudo cryptsetup open $ROOTPART $ENCRYNAME

[ ! -e /dev/mapper/${ENCRYNAME} ] && error "Failed to locate rootfs mapper. Aborting." && exit 1

sudo mkfs.vfat $BOOTPART
sudo $MKFS $ENCRYPART

sudo mount $ENCRYPART $TMPMOUNT
sudo mkdir $TMPMOUNT/boot
sudo mount $BOOTPART $TMPMOUNT/boot

sudo unsquashfs -f -d $TMPMOUNT $SQFSROOT

./genfstab -U $TMPMOUNT | grep UUID | grep -v "swap" | sudo tee -a $TMPMOUNT/etc/fstab
sudo sed -i "s:UUID=[0-9a-f-]*\s*/\s:/dev/mapper/cryptroot / :g" $TMPMOUNT/etc/fstab

sudo dd if=${TMPMOUNT}/boot/u-boot-sunxi-with-spl-${DEVICE}-552.bin of=${DISK_IMAGE} bs=8k seek=1

sudo umount -R $TMPMOUNT
sudo cryptsetup close $ENCRYNAME


echo -e "\e[1mCleaning up working directory...\e[0m"
sudo rm -f arch-install-scripts.tar.zst || true
sudo rm -f genfstab || true
sudo rm -rf $TMPMOUNT || true

echo -e "\e[32m\e[1mAll done! Please insert the card to your device and power on.\e[39m\e[0m"
