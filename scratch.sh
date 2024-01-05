#!/bin/bash

# Rebuild the kernel for 3 partition layout

# make gentoo directory if not at mnt gentoo
if [ ! -d "/mnt/gentoo" ]; then
    mkdir /mnt/gentoo
fi

DRIVE="sda"

mount /dev/${DRIVE}3 /mnt/gentoo
mount /dev/${DRIVE}1 /mnt/gentoo/efi/
swapon "/dev/${DRIVE}2"

mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run 