#!/bin/bash

###########################################################
##################### DISK CONFIG #########################
###########################################################

# Check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo or switch to root."
  exit 1
fi

# Target device
DEVICE="/dev/nvme0n1"

# Clear the screen for a cleaner display
clear

# Display a header for the script


echo "WARNING: This operation will destroy all data on $DEVICE."
read -p "Are you sure you want to continue? (y/N): " confirmation

# Convert confirmation to lowercase
confirmation=${confirmation,,} # Requires Bash 4+

# Check if the user confirmed
if [[ "$confirmation" != "y" && "$confirmation" != "yes" ]]; then
  echo "Operation aborted."
  exit 1
fi

# Create new partition table
echo "Creating new partition table and partitions on $DEVICE..."

# Use a subshell to group all fdisk commands
(
echo g # Create a new empty GPT partition table

echo n # Add a new partition (EFI System)
echo 1 # Partition number 1
echo 2048 # First sector (accept default: 2048)
echo +1G # Last sector (size), creating a 1G EFI partition
echo t # Change type
echo 1 # Set type to EFI System

echo n # Add a new partition (Linux swap)
echo 2 # Partition number 2
echo   # First sector (accept default, follows immediately after the previous partition)
echo +16G # Last sector (size), creating a 16G swap partition
echo t # Change type
echo 2 # Select partition 2
echo 19 # Set type to Linux swap

echo n # Add a new partition (Linux root (x86-64))
echo 3 # Partition number 3
echo   # First sector (accept default, follows immediately after the previous partition)
echo   # Last sector (accept default, use remaining disk space), for the root partition
echo t # Change type
echo 3 # Select partition 3
echo 23 # Set type to Linux root (x86-64)

echo w # Write changes
) | sudo fdisk $DEVICE

# Check the exit status of fdisk to determine if the operations were successful
if [ $? -eq 0 ]; then
  echo "Partition table and partitions on $DEVICE have been successfully created."
else
  echo "There was an error creating the partitions. Please check the output for details."
fi

###########################################################
##################### FILE SYSTEMS ########################
###########################################################
#!/bin/bash

# Partition identifiers
EFI_PARTITION="/dev/nvme0n1p1"
SWAP_PARTITION="/dev/nvme0n1p2"
ROOT_PARTITION="/dev/nvme0n1p3"

# Format the EFI partition as FAT32
echo "Formatting $EFI_PARTITION as FAT32..."
sudo mkfs.vfat -F 32 $EFI_PARTITION

# Setup the swap partition
echo "Setting up swap on $SWAP_PARTITION..."
sudo mkswap $SWAP_PARTITION
sudo swapon $SWAP_PARTITION

# Format the root partition as ext4
echo "Formatting $ROOT_PARTITION as ext4..."
sudo mkfs.ext4 -F $ROOT_PARTITION

echo "All partitions have been formatted and swap is active."

###########################################################
################## EXPLODE LINUX TARBALL ##################
###########################################################

#!/bin/bash

# Partition identifiers
EFI_PARTITION="/dev/nvme0n1p1"  # EFI partition, not used directly in this script
SWAP_PARTITION="/dev/nvme0n1p2" # Swap partition, not used directly in this script
ROOT_PARTITION="/dev/nvme0n1p3"

# Ensure the target mount point exists and mount the root partition
sudo mkdir -p /mnt/gentoo
sudo mount $ROOT_PARTITION /mnt/gentoo

# Synchronize time to ensure accurate timestamping for file operations
sudo chronyd -q

# Change to the target directory where the stage3 tarball will be extracted
cd /mnt/gentoo

# Define the URL to fetch the latest stage3 tarball
STAGE3_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-desktop-systemd.txt"

# Fetch the latest stage3 tarball URL using curl and grep
STAGE3_FILE=$(curl -s $STAGE3_URL | grep -m1 -oP '\d+T\d+Z/stage3-.*\.tar\.xz')

if [ -z "$STAGE3_FILE" ]; then
    echo "Failed to find the stage3 file URL. Please check the $STAGE3_URL content."
    exit 1
fi

FULL_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/$STAGE3_FILE"

# Download the latest stage3 tarball
echo "Downloading $FULL_URL..."
wget $FULL_URL

# Extract the stage3 tarball
echo "Extracting the stage3 tarball..."
sudo tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

echo "Stage3 tarball has been successfully extracted."

echo "Prepare environment step is next, ensure to properly chroot and configure your Gentoo system."


#!/bin/bash

# Partition identifiers
EFI_PARTITION="/dev/nvme0n1p1"
SWAP_PARTITION="/dev/nvme0n1p2"
ROOT_PARTITION="/dev/nvme0n1p3"

# Ensure the target mount points exist
sudo mkdir -p /mnt/gentoo/efi
sudo mkdir -p /mnt/gentoo/etc  # Ensure the etc directory exists for resolv.conf

# Mount the EFI partition
echo "Mounting $EFI_PARTITION on /mnt/gentoo/efi..."
if ! mountpoint -q /mnt/gentoo/efi; then
    sudo mount $EFI_PARTITION /mnt/gentoo/efi || echo "Failed to mount $EFI_PARTITION, it may already be mounted."
else
    echo "$EFI_PARTITION is already mounted."
fi

# Activate swap
echo "Swap already activated."

# Copy DNS settings
echo "Copying DNS settings..."
sudo cp /etc/resolv.conf /mnt/gentoo/etc/resolv.conf || echo "Failed to copy DNS settings."

# Mount necessary filesystems
echo "Mounting necessary filesystems..."
sudo mount --types proc /proc /mnt/gentoo/proc || echo "Proc already mounted or failed to mount."
sudo mount --rbind /sys /mnt/gentoo/sys
sudo mount --make-rslave /mnt/gentoo/sys
sudo mount --rbind /dev /mnt/gentoo/dev
sudo mount --make-rslave /mnt/gentoo/dev
sudo mount --rbind /run /mnt/gentoo/run
sudo mount --make-rslave /mnt/gentoo/run

echo "All setup complete. Ready to chroot."

###########################################################
############# CHROOT & STAGE 4 SETUP PARAMS ###############
###########################################################

sudo chroot /mnt/gentoo /bin/bash 
export PS1='(chroot) \[\033[0;31m\]\u\[\033[1;31m\]@\h \[\033[1;34m\]\w \$ \[\033[m\]'

emerge --sync

# Define the package and its USE flags
PACKAGE="x11-drivers/nvidia-drivers"
USE_FLAGS="modules strip X persistenced static-libs tools"

# Create package.use directory if it does not exist
[ -d /etc/portage/package.use ] || mkdir -p /etc/portage/package.use

# Apply the USE flag changes for the package
echo "${PACKAGE} ${USE_FLAGS}" >> /etc/portage/package.use/custom

# Install cpuid2cpuflags and apply CPU-specific USE flags

emerge --verbose --autounmask-continue=y app-portage/cpuid2cpuflags

# Create package.use directory if it does not exist

[ -d /etc/portage/package.use ] || mkdir -p /etc/portage/package.use

echo "*/* $(cpuid2cpuflags)" > /etc/portage/package.use/00cpu-flags

# Define additional necessary USE flag changes

USE_CHANGES=(
    "sys-kernel/installkernel-gentoo grub"
)

# Apply additional USE flag changes
for change in "${USE_CHANGES[@]}"; do
    echo "${change}" >> /etc/portage/package.use/custom
done

# Backup and update make.conf with optimized CPU flags

cp /etc/portage/make.conf /etc/portage/make.conf.bak2
OPTIMIZED_FLAGS="$(gcc -v -E -x c /dev/null -o /dev/null -march=native 2>&1 | grep /cc1 | sed -n 's/.*-march=\([a-z]*\)/-march=\1/p' | sed 's/-dumpbase null//')"

if [ -z "${OPTIMIZED_FLAGS}" ]; then
    echo "Failed to extract optimized CPU flags"
    exit 1
fi

# Remove trailing space in COMMON_FLAGS
COMMON_FLAGS=$(echo "${COMMON_FLAGS}" | sed 's/ *$//')

# Update COMMON_FLAGS in make.conf
sed -i "/^COMMON_FLAGS/c\COMMON_FLAGS=\"-O2 -pipe ${OPTIMIZED_FLAGS}\"" /etc/portage/make.conf
sed -i 's/COMMON_FLAGS="\(.*\)"/COMMON_FLAGS="\1"/;s/  */ /g' /etc/portage/make.conf

# Assign MAKEOPTS automatically
NUM_CORES=$(nproc)
MAKEOPTS_VALUE=$((NUM_CORES + 1))
echo "MAKEOPTS=\"-j${MAKEOPTS_VALUE}\"" >> /etc/portage/make.conf
echo 'ACCEPT_LICENSE="*"' >> /etc/portage/make.conf
echo 'VIDEO_CARDS="nvidia"' >> /etc/portage/make.conf
echo 'USE="X gtk -kde -qt5 gnome systemd"' >> /etc/portage/make.conf
echo 'ACCEPT_KEYWORDS="~amd64"' >> /etc/portage/make.conf
echo 'GRUB_PLATFORMS="efi-64"' >> /etc/portage/make.conf

cat /etc/portage/make.conf

echo "All Compiler Flag Updates & Use Changes Completed"
echo "Recompiling Packages with all Changes to get Base System Online"
emerge --verbose --update --deep --newuse @world
echo "Completed. Kernel Config Next."

###########################################################
################## SETUP KERNEL CONFIG ####################
###########################################################

#!/bin/bash

LOCALE="en_US.UTF-8 UTF-8"
echo $LOCALE >> /etc/locale.gen
locale-gen
eselect locale set en_US.utf8
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime

source /etc/profile
export PS1='(chroot) \[\033[0;31m\]\u\[\033[1;31m\]@\h \[\033[1;34m\]\w \$ \[\033[m\]'

# Emerge required packages

emerge sys-kernel/gentoo-sources
emerge sys-kernel/linux-firmware
eselect kernel set 1
emerge sys-kernel/genkernel
emerge --noreplace sys-firmware/intel-microcode
# manually generate the early intel microcode cpio archive
iucode_tool -S --write-earlyfw=/boot/early_ucode.cpio /lib/firmware/intel-ucode/*
genkernel --kernel-append-localversion=-trollfactory-28Apr24 --mountboot --microcode initramfs --install all


###########################################################
################## AUTOMATIC FSTAB GEN ####################
###########################################################

#!/bin/bash

# Hardcoded DRIVE variable
DRIVE="/dev/nvme0n1"

# Backup and generate fstab
echo "Backing up and generating fstab..."
cp /etc/fstab /etc/fstab.backup

# Generating the new fstab entries
echo "# /etc/fstab: static file system information." | tee /etc/fstab
echo "#" | tee -a /etc/fstab
echo "# See fstab(5) for details." | tee -a /etc/fstab
echo "#" | tee -a /etc/fstab
echo "# <file system> <mount point>   <type>  <options>       <dump>  <pass>" | tee -a /etc/fstab

# Generate and add fstab entries with echo messages

# /efi partition
EFI_UUID=$(blkid -o value -s UUID ${DRIVE}p1)
EFI_FSTAB_ENTRY="UUID=${EFI_UUID} /efi vfat defaults 0 2"
echo "$EFI_FSTAB_ENTRY" | tee -a /etc/fstab
echo "Adding /efi partition to fstab: $EFI_FSTAB_ENTRY"

# Swap partition
SWAP_UUID=$(blkid -o value -s UUID ${DRIVE}p2)
SWAP_FSTAB_ENTRY="UUID=${SWAP_UUID} none swap sw 0 0"
echo "$SWAP_FSTAB_ENTRY" | tee -a /etc/fstab
echo "Adding swap partition to fstab: $SWAP_FSTAB_ENTRY"

# Root partition
ROOT_UUID=$(blkid -o value -s UUID ${DRIVE}p3)
ROOT_FSTAB_ENTRY="UUID=${ROOT_UUID} / ext4 defaults 0 1"
echo "$ROOT_FSTAB_ENTRY" | tee -a /etc/fstab
echo "Adding / partition to fstab: $ROOT_FSTAB_ENTRY"

echo "Fstab generation complete."
echo "Contents of /etc/fstab:"
cat /etc/fstab

###########################################################
################## SYSTEM CONFIGURATION ###################
###########################################################

#!/bin/bash

set -e

# Set the hostname
echo "rogue-attack" > /etc/hostname

# Setup machine ID
systemd-machine-id-setup

# Set root password
passwd

# Enable essential services
systemctl preset-all --preset-mode=enable-only
systemctl enable sshd

# Install and enable NetworkManager for network management
emerge --verbose --autounmask-continue=y net-misc/networkmanager
systemctl enable NetworkManager.service

# Install networking and system tools
emerge --verbose --autounmask-continue=y net-misc/openssh
emerge --verbose --autounmask-continue=y sys-block/io-scheduler-udev-rules
emerge --verbose --autounmask-continue=y net-wireless/iw net-wireless/wpa_supplicant

# Install GRUB for boot management
emerge --verbose --autounmask-continue=y sys-boot/grub

# Install utilities for system administration
emerge --verbose --autounmask-continue=y app-admin/sudo

# Install Vim editor for file editing
emerge --verbose --autounmask-continue=y app-editors/vim

# Install bash completion for better shell experience
emerge --verbose --autounmask-continue=y app-shells/bash-completion

# Install developer tools and programming languages
emerge --verbose --autounmask-continue=y dev-util/git
emerge --verbose --autounmask-continue=y dev-util/cmake
emerge --verbose --autounmask-continue=y sys-devel/gcc
emerge --verbose --autounmask-continue=y dev-lang/python
emerge --verbose --autounask-continue=y dev-lang/rust
emerge --verbose --autounask-continue=y dev-lang/go

# Additional useful network tools
emerge --verbose --autounmask-continue=y net-analyzer/wireshark
emerge --verbose --autounask-continue=y net-analyzer/nmap

echo "Configuring sudoers file for wheel group..."
if grep -q "# %wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
    cp /etc/sudoers /etc/sudoers.bak && \
    sed -i '/# %wheel ALL=(ALL:ALL) ALL/s/^# //' /etc/sudoers && \
    echo "Wheel group has been granted sudo privileges."
else
    echo "Wheel group already has sudo privileges or the line does not exist."
fi

# Safety check: If sed fails, restore from backup
if [ $? -ne 0 ]; then
    echo "An error occurred, restoring the original sudoers file."
    mv /etc/sudoers.bak /etc/sudoers
else
    rm /etc/sudoers.bak
fi

grub-install --target=x86_64-efi --efi-directory=/efi --removable
grub-mkconfig -o /boot/grub/grub.cfg
useradd -m -G users,wheel,video,audio -s /bin/bash skywalker
passwd skywalker

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root." >&2
    exit 1
fi

# Enable SSH root login
SSHD_CONFIG="/mnt/gentoo/etc/ssh/sshd_config"
if grep -q "^#PermitRootLogin" "${SSHD_CONFIG}"; then
    sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' "${SSHD_CONFIG}"
else
    echo "PermitRootLogin yes" >> "${SSHD_CONFIG}"
fi
echo "SSH root login has been enabled."

# Enable sshd service to start at boot
ln -sf "/usr/lib/systemd/system/sshd.service" "/etc/systemd/system/multi-user.target.wants/sshd.service"
echo "sshd service has been enabled at boot."

###########################################################
################### XORG & GNOME SETUP ####################
###########################################################

#!/bin/bash
emerge --ask x11-drivers/nvidia-drivers
emerge --ask x11-base/xorg-server
emerge --ask gnome-base/gnome
emerge --ask gnome-base/gdm
systemctl enable gdm.service
echo "exec gnome-session" > ~/.xinitrc
sed -i '1i\export XDG_MENU_PREFIX=gnome-' ~/.xinitrc
exit

###########################################################
#################### UMOUNT && REBOOT #####################
###########################################################

#!/bin/bash
cd 
umount -l /mnt/gentoo/dev{/shm,/pts,}
umount -R /mnt/gentoo
reboot
