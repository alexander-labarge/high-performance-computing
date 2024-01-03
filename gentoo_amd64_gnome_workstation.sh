#!/bin/bash

# Constants
TIMEZONE="America/New_York"
LOCALE="en_US.UTF-8"
COLLATE="C"
MAKECONF="/etc/portage/make.conf"
PACKAGE_CONF="/etc/portage/package.use/custom"
DRIVE="sda"
STAGE3_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/20231231T163203Z/stage3-amd64-desktop-systemd-mergedusr-20231231T163203Z.tar.xz"

# Define the einfo function for the chroot environment
function einfo() {
    local blue='\e[1;34m'   # Light blue
    local yellow='\e[1;33m' # Yellow
    local red='\e[1;31m'    # Red
    local reset='\e[0m'     # Reset text formatting
    local hostname=$(hostname)
    local current_datetime=$(date '+%Y-%m-%d %H:%M:%S')
    local log_file="install-log-${hostname}-$(date '+%Y-%m-%d').log"

    # Ensure the log file exists in the current directory
    touch "$log_file"

    echo -e "${red}------------------------------------------------------------------------------------------------------------${reset}"
    echo -e "${blue}[${yellow}$(date '+%Y-%m-%d %H:%M:%S')${blue}] $1${reset}"
    echo -e "${red}------------------------------------------------------------------------------------------------------------${reset}"

    # Append the log message to the log file in the current directory
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$log_file" 2>&1
}

function einfo_purple_bold() {
    local purple_bold='\e[1;35m' # Purple and bold
    local reset='\e[0m'          # Reset text formatting
    echo -e "${purple_bold}$1${reset}"
}

# New function to execute commands and log their output and errors
function exec_and_log() {
    local command_output
    local command_error

    # Combine all arguments into one string to log the full command
    local full_command="$*"

    # Log the command being executed
    einfo "Executing command: $full_command"

    # Execute command and capture stdout and stderr
    command_output=$(eval "$full_command" 2>&1)
    command_error=$?

    # Log output
    einfo "$command_output"

    # Check if there was an error
    if [ $command_error -ne 0 ]; then
        einfo "Error (Exit Code: $command_error): $command_output"
    fi
}

function countdown_timer() {
    for ((i = 3; i >= 0; i--)); do
        if [ $i -gt 0 ]; then
            echo -ne "\r\033[K\e[31mContinuing in \e[34m$i\e[31m seconds\e[0m"
        else
            echo -e "\r\033[K\e[1;34mContinuing\e[0m"
        fi
        sleep 1
    done
}

function configure_disks() {
    # Display drive layout
    einfo "Drive Layout:"
    lsblk /dev/$DRIVE

    # Confirm with the user before proceeding
    read -p "Do you want to proceed with formatting this drive? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
        einfo "Partitioning aborted by user."
        exit 1
    fi

    einfo "Setting up partitions on /dev/$DRIVE..."

    # Start fdisk to partition the drive
    { 
        echo g; # Create a new empty GPT partition table
        echo n; # New partition for EFI
        echo 1; # Partition number 1
        echo ;  # Default first sector
        echo +1G; # 1 GB for the EFI partition
        echo t; # Change partition type
        echo 1; # Partition type 1 (EFI System)
        echo n; # New partition for Swap
        echo 2; # Partition number 2
        echo ;  # Default first sector
        echo +16G; # 16 GB for the swap partition
        echo n; # New partition for Root
        echo 3; # Partition number 3
        echo ;  # Default first sector
        echo ;  # Use the remaining space for the root partition
        echo w; # Write changes
    } | fdisk /dev/$DRIVE

    # After creating all the partitions
    partprobe /dev/$DRIVE

    einfo "Disk partitioning complete."

    countdown_timer
}

function format_filesystems() {
    # Formatting the EFI partition as FAT32
    einfo "Formatting EFI partition..."
    mkfs.vfat -F32 "/dev/${DRIVE}1"
    einfo "EFI partition formatted."

    countdown_timer

    # Formatting the Swap partition
    einfo "Setting up swap space..."
    mkswap "/dev/${DRIVE}2"
    swapon "/dev/${DRIVE}2"
    einfo "Swap space set up."

    countdown_timer

    # Formatting the Root partition
    einfo "Formatting root partition..."
    mkfs.xfs -f "/dev/${DRIVE}3"
    einfo "Root partition formatted."

    countdown_timer

    einfo "Filesystems formatted."

    countdown_timer
}

function mount_file_systems() {
    einfo "Mounting filesystems..."
    
    # Mount root partition
    einfo "Creating root mount point at /mnt/gentoo..."
    mkdir -p "/mnt/gentoo"
    einfo "Root mount point created."
    mount "/dev/${DRIVE}3" "/mnt/gentoo"
    einfo "Mounted root partition."

    # Mount EFI partition
    einfo "Making EFI directory at /efi..."
    mkdir -p "/mnt/gentoo/efi"
    einfo "EFI directory created."
    mount "/dev/${DRIVE}1" "/mnt/gentoo/efi"
    einfo "Mounted EFI partition."

    einfo "Filesystems mounted."

    countdown_timer
}

function download_and_extract_stage3() {
    einfo "Downloading Gentoo stage3 tarball..."
 
    # Download the stage3 tarball
    wget "$STAGE3_URL" -O "/mnt/gentoo/stage3-amd64-desktop-systemd-mergedusr-20231231T163203Z.tar.xz"

    # Check if the download was successful
    if [ ! -f "/mnt/gentoo/stage3-amd64-desktop-systemd-mergedusr-20231231T163203Z.tar.xz" ]; then
        eerror "Download failed, exiting."
        exit 1
    fi

    einfo "Extracting stage3 tarball..."
    tar xpvf "/mnt/gentoo/stage3-amd64-desktop-systemd-mergedusr-20231231T163203Z.tar.xz" --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo

    einfo "Stage3 tarball extracted."

    countdown_timer
}

configure_disks
format_filesystems
mount_file_systems
download_and_extract_stage3

# Mount System Devices

mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run 




# Function to create directories if they don't exist
ensure_directory() {
    [ -d "$1" ] || mkdir -p "$1"
}

# Set up environment
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
chroot /mnt/gentoo /bin/bash
source /etc/profile
export PS1="(darth-root) ${PS1}"


# Prepare system
emerge --sync

# Configure system
echo 'ACCEPT_LICENSE="*"' >> "$MAKECONF"
echo 'VIDEO_CARDS="nvidia"' >> "$MAKECONF"
echo 'USE="X grub -qt5 -kde gtk gnome -gnome-online-accounts"' >> "$MAKECONF"

ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
echo "en_US UTF-8" > /etc/locale.gen

locale-gen

echo "LANG=\"$LOCALE\"" > /etc/env.d/02locale
echo "LC_COLLATE=\"$COLLATE\"" >> /etc/env.d/02locale

env-update && source /etc/profile && export PS1="(skywalker-chroot) ${PS1}"

# Define package and USE flags
PACKAGE="x11-drivers/nvidia-drivers"
USE_FLAGS="modules strip X persistenced static-libs tools"

echo "Applying Customized USE flag changes for ${PACKAGE}..."
ensure_directory "/etc/portage/package.use"
echo "${PACKAGE} ${USE_FLAGS}" >> "$PACKAGE_CONF"
echo "USE flag changes for ${PACKAGE} have been applied."

# Install and configure cpuid2cpuflags
echo "Installing cpuid2cpuflags and applying CPU-specific USE flags..."
emerge --verbose --autounmask-continue=y app-portage/cpuid2cpuflags

echo "Creating CPU-specific USE flags file..."
ensure_directory "/etc/portage/package.use"
echo "*/* $(cpuid2cpuflags)" > "/etc/portage/package.use/00cpu-flags"
echo "CPU-specific USE flags have been applied."
echo "CPU flags added were: $(cpuid2cpuflags)"

# Additional USE flag changes
echo "Apply Kernel Specific Initramfs Use Flags"
USE_CHANGES=("sys-kernel/installkernel-gentoo grub")

echo "Additional USE flag changes have been applied."

# Update USE flags for all packages
cp "$MAKECONF" "$MAKECONF.bak2"
OPTIMIZED_FLAGS="$(gcc -v -E -x c /dev/null -o /dev/null -march=native 2>&1 | grep /cc1 | sed -n 's/.*-march=\([a-z]*\)/-march=\1/p' | sed 's/-dumpbase null//')"

if [ -z "${OPTIMIZED_FLAGS}" ]; then
    echo "Failed to extract optimized CPU flags"
    exit 1
fi

# Update make.conf with optimized CPU flags
sed -i "/^COMMON_FLAGS/c\COMMON_FLAGS=\"-O2 -pipe ${OPTIMIZED_FLAGS}\"" "$MAKECONF"
sed -i 's/COMMON_FLAGS="\(.*\)"/COMMON_FLAGS="\1"/;s/  */ /g' "$MAKECONF"
sed -i 's/COMMON_FLAGS="\(.*\) *"/COMMON_FLAGS="\1"/' "$MAKECONF"

# Assign MAKEOPTS automatically
NUM_CORES=$(nproc)
MAKEOPTS_VALUE=$((NUM_CORES + 1))
echo "MAKEOPTS=\"-j${MAKEOPTS_VALUE} -l$(nproc)\"" >> "$MAKECONF"

echo "make.conf has been updated successfully."
echo "Flags added were: ${OPTIMIZED_FLAGS}"
echo "MAKEOPTS Compiler Available CPU Cores have been set to: -j${MAKEOPTS_VALUE}"
echo "Make.conf File Contents Now:"
cat "$MAKECONF"

echo "Finished updating USE flags for all packages and system specific options"


# Additional commands
eselect profile list
eselect profile set default/linux/amd64/17.1/desktop/gnome/systemd/merged-usr
emerge --verbose --update --deep --newuse @world
emerge --depclean

echo "Initial Rebuild Complete"

env-update && source /etc/profile && export PS1="(skywalker-chroot) ${PS1}"

echo "Install Firmware + Microcode"

# Allows for:
# dracut[I]: *** Generating early-microcode cpio image ***
# dracut[I]: *** Constructing AuthenticAMD.bin ***

emerge --verbose --autounmask-continue=y sys-kernel/linux-firmware

emerge --verbose --autounmask-continue=y sys-kernel/installkernel-gentoo

emerge --verbose --autounmask-continue=y sys-kernel/gentoo-kernel-bin

emerge --depclean

env-update && source /etc/profile && export PS1="(darth-root) ${PS1}"

# FSTAB GENERATION

# Determine the DRIVE variable based on the root device currently mounted (searches for root / and drive prefix i.e. "sda")
ROOT_DEVICE=$(mount | grep " / " | awk '{print $1}')
DRIVE=$(echo "$ROOT_DEVICE" | sed -E 's/.*\/([a-z]+)[0-9]+/\1/')

# Backup and generate fstab
einfo "Backing up and generating fstab..."
cp /etc/fstab /etc/fstab.backup

# Backup and generate fstab
einfo "Backing up and generating fstab..."
cp /etc/fstab /etc/fstab.backup

# Generating the new fstab entries
einfo "Setting up initial comment in fstab..."
echo "# /etc/fstab: static file system information." | tee /etc/fstab
einfo "Adding blank line..."
echo "#" | tee -a /etc/fstab
einfo "Adding fstab details reference..."
echo "# See fstab(5) for details." | tee -a /etc/fstab
einfo "Adding another blank line..."
echo "#" | tee -a /etc/fstab
einfo "Adding column headers..."
echo "# <file system> <mount point>   <type>  <options>       <dump>  <pass>" | tee -a /etc/fstab

# Generate and add fstab entries with einfo messages

# /efi partition
EFI_UUID=$(blkid -o value -s UUID /dev/${DRIVE}1)
EFI_FSTAB_ENTRY="UUID=${EFI_UUID} /efi vfat defaults 0 2"
echo "$EFI_FSTAB_ENTRY" | tee -a /etc/fstab
einfo "Adding /efi partition to fstab: $EFI_FSTAB_ENTRY"

countdown_timer

# Swap partition
SWAP_UUID=$(blkid -o value -s UUID /dev/${DRIVE}2)
SWAP_FSTAB_ENTRY="UUID=${SWAP_UUID} none swap sw 0 0"
echo "$SWAP_FSTAB_ENTRY" | tee -a /etc/fstab
einfo "Adding swap partition to fstab: $SWAP_FSTAB_ENTRY"

countdown_timer

# Root partition
ROOT_UUID=$(blkid -o value -s UUID /dev/${DRIVE}3)
ROOT_FSTAB_ENTRY="UUID=${ROOT_UUID} / xfs defaults 0 1"
echo "$ROOT_FSTAB_ENTRY" | tee -a /etc/fstab
einfo "Adding / partition to fstab: $ROOT_FSTAB_ENTRY"

countdown_timer

einfo "Fstab generation complete."
einfo "Contents of /etc/fstab:"
cat /etc/fstab

countdown_timer

echo "deathstar" > /etc/hostname

# NETWORK SETUP:

emerge --verbose --autounmask-continue=y net-misc/dhcpcd
systemctl enable dhcpcd

# Change Root Password
einfo "Changing root password. Please set a new password."
passwd root

countdown_timer

# Create a new user named skywalker
einfo "Creating new user skywalker..."
useradd -m skywalker -G wheel -s /bin/bash

# Set the password for skywalker
einfo "Set a password for skywalker."
echo "skywalker:password" | chpasswd

# Add the user to all available groups
for group in $(cut -d: -f1 /etc/group); do
    gpasswd -a skywalker $group
done
einfo "Added skywalker to all available groups."

countdown_timer

# Install sudo
einfo "Installing sudo..."
emerge --verbose --autounmask-continue=y app-admin/sudo

# Allow wheel group to use sudo
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
einfo "Sudo configuration complete."

countdown_timer

# Install SSHD
einfo "Installing SSHD..."
emerge --verbose --autounmask-continue=y net-misc/openssh
einfo "SSHD installation complete."

countdown_timer

# Configure SSHD for password authentication
einfo "Configuring SSH for password authentication..."
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
einfo "Password authentication enabled for SSH."

countdown_timer

# Generating SSH keys
einfo "Generating SSH keys..."
ssh-keygen -A
einfo "SSH key generation complete."

countdown_timer

# Display SSH keys
einfo "SSH keys:"
cat /etc/ssh/ssh_host_*

countdown_timer

# Set the desired keymap (us = option 242)
KEYMAP="us"

# Set the hostname (change to your desired hostname)
HOSTNAME="deathstar"

# Run systemd-firstboot with the chosen keymap and hostname
systemd-firstboot --prompt --locale=en_US.UTF-8 --keymap=$KEYMAP --hostname=$HOSTNAME

# Enable Necessary System Services:
systemctl preset-all --preset-mode=enable-only
systemctl enable getty@tty1.service
systemctl enable sshd
systemctl enable systemd-timesyncd.service

emerge --verbose --update --deep --newuse @world

# Resolve circular dependencies
# echo "Resolving circular dependencies for libpulse..."
# USE="minimal" emerge --ask --oneshot libsndfile

NVIDIA_DRIVER="x11-drivers/nvidia-drivers"
ACCEPT_KEYWORDS_DIR="/etc/portage/package.accept_keywords"
ACCEPT_KEYWORDS_FILE="$ACCEPT_KEYWORDS_DIR/nvidia-drivers"

# Ensure the /etc/portage/package.accept_keywords directory exists
if [ ! -d "$ACCEPT_KEYWORDS_DIR" ]; then
    echo "Creating directory $ACCEPT_KEYWORDS_DIR"
    mkdir -p "$ACCEPT_KEYWORDS_DIR"
fi

# Set the ~amd64 keyword for the package
echo "$NVIDIA_DRIVER ~amd64" >> "$ACCEPT_KEYWORDS_FILE"
echo "Added ~amd64 keyword for $NVIDIA_DRIVER"

# Install the package
emerge --verbose --autounmask-continue=y "$NVIDIA_DRIVER"

# Build NVIDIA Experimental Modules into Kernel
echo "Building NVIDIA experimental kernel modules..."
emerge @module-rebuild

# Disable previewer for nautilus and remove GNOME online accounts
# This aids in privacy and security addressed in CVE-2018-17183
echo "Configuring nautilus and GNOME online accounts..."
mkdir -p /etc/portage/package.use
echo "gnome-base/nautilus -previewer" > /etc/portage/package.use/nautilus

# Install GNOME
echo "Installing GNOME..."
# Resolve circular dependencies
USE="minimal" emerge --verbose --oneshot libsndfile

emerge --verbose --autounmask-continue=y gnome-base/gnome
# Uncomment below for minimal GNOME installation
# emerge --ask gnome-base/gnome-light

# Update environment variables
echo "Updating environment variables..."

env-update && source /etc/profile && export PS1="(skywalker-chroot) ${PS1}"

# Add All Users to Plugdev group
# Check if the plugdev group exists
if getent group plugdev > /dev/null; then
    echo "The plugdev group exists. Adding users to the group..."
    
    # Get all users with a login shell (typically regular users)
    for USER in $(awk -F: '$7~/\/bin\/bash|\/bin\/sh/ {print $1}' /etc/passwd); do
        echo "Adding user $USER to plugdev group..."
        gpasswd -a "$USER" plugdev
    done

    echo "All users have been added to the plugdev group."
else
    echo "The plugdev group does not exist. Please create the group first."
fi

# Configure display manager (GDM)
if systemctl > /dev/null 2>&1; then
    # Systemd
    echo "Configuring GDM for systemd..."
    systemctl enable gdm.service
    systemctl start gdm.service
else
    # OpenRC
    echo "Configuring GDM for OpenRC..."
    rc-update add elogind boot
    rc-service elogind start
    emerge --ask --noreplace gui-libs/display-manager-init
    echo 'DISPLAYMANAGER="gdm"' > /etc/conf.d/display-manager
    rc-update add display-manager default
    rc-service display-manager start
fi

echo "Configuration complete."

# ADDITIONAL OPTIONAL PACKAGES

# Index the file system to provide faster file location capabilities, install sys-apps/mlocate
emerge --verbose --autounmask-continue=y sys-apps/mlocate

# Install Bash Completition
emerge --verbose --autounmask-continue=y app-shells/bash-completion

# Install Plymouth
emerge --verbose --autounmask-continue=y sys-boot/plymouth

# Install network block device support
emerge --verbose --autounmask-continue=y sys-block/nbd

# Install NFS support
emerge --verbose --autounmask-continue=y net-fs/nfs-utils

# Install rpcbind for NFS support
emerge --verbose --autounmask-continue=y net-nds/rpcbind

# Install rsyslog for logging
emerge --verbose --autounmask-continue=y app-admin/rsyslog

# Install Squashfs support
emerge --verbose --autounmask-continue=y sys-fs/squashfs-tools

# Install TPM 2.0 TSS support
emerge --verbose --autounmask-continue=y app-crypt/tpm2-tools

# Install Bluez for Bluetooth support (experimental)
emerge --verbose --autounmask-continue=y net-wireless/bluez

# Install BIOS-given device names support
emerge --verbose --autounmask-continue=y sys-apps/biosdevname

# Install network NVMe support
emerge --verbose --autounmask-continue=y sys-apps/nvme-cli

# Install jq for JSON data processing
emerge --verbose --autounmask-continue=y app-misc/jq
