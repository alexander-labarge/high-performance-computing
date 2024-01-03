#!/bin/bash

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

# Constants
TIMEZONE="America/New_York"
LOCALE="en_US.UTF-8"
COLLATE="C"
MAKECONF="/etc/portage/make.conf"
PACKAGE_CONF="/etc/portage/package.use/custom"

# Function to create directories if they don't exist
ensure_directory() {
    [ -d "$1" ] || mkdir -p "$1"
}

# Set up environment
source /etc/profile
export PS1="(darth-root) ${PS1}"


# Prepare system
ensure_directory /efi
mount /dev/sda1 /efi
emerge --sync

# Configure system
echo 'ACCEPT_LICENSE="*"' >> "$MAKECONF"
echo 'VIDEO_CARDS="nvidia"' >> "$MAKECONF"
echo 'USE="X"' >> "$MAKECONF"

ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
echo "en_US UTF-8" > /etc/locale.gen

locale-gen

echo "LANG=\"$LOCALE\"" > /etc/env.d/02locale
echo "LC_COLLATE=\"$COLLATE\"" >> /etc/env.d/02locale

env-update && source /etc/profile

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

# Assign MAKEOPTS automatically
NUM_CORES=$(nproc)
MAKEOPTS_VALUE=$((NUM_CORES + 1))
echo "MAKEOPTS=\"-j${MAKEOPTS_VALUE}\"" >> "$MAKECONF"

echo "make.conf has been updated successfully."
echo "Flags added were: ${OPTIMIZED_FLAGS}"
echo "MAKEOPTS Compiler Available CPU Cores have been set to: -j${MAKEOPTS_VALUE}"
echo "Make.conf File Contents Now:"
cat "$MAKECONF"

echo "Finished updating USE flags for all packages and system specific options"


# Additional commands
eselect profile list
eselect profile set 8
emerge --ask --verbose --update --deep --newuse @world
emerge --depclean

echo "Initial Rebuild Complete"

env-update && source /etc/profile && export PS1="(darth-root) ${PS1}"

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
KEYMAP=us

# Set the hostname (change to your desired hostname)
HOSTNAME=deathstar

# Run systemd-firstboot with the chosen keymap and hostname
systemd-firstboot --prompt --locale=en_US.UTF-8 --keymap=$KEYMAP --hostname=$HOSTNAME

# Enable Necessary System Services:
systemctl preset-all --preset-mode=enable-only
systemctl enable getty@tty1.service
systemctl enable sshd
systemctl enable systemd-timesyncd.service


#!/bin/bash

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
   echo "This script must be run as root" 
   exit 1
fi

# Update USE flags Before Building Stage 4 of OS

echo "Updating USE flags in /etc/portage/make.conf..."
echo 'USE="X grub -qt5 -kde gtk gnome -gnome-online-accounts systemd"' > /etc/portage/make.conf

# Select systemd profile for GNOME
echo "Selecting the systemd profile for GNOME..."
eselect profile set default/linux/amd64/17.1/desktop/gnome/systemd

emerge --ask --verbose --update --deep --newuse @world

# Resolve circular dependencies
echo "Resolving circular dependencies for libpulse..."
USE="minimal" emerge --ask --oneshot libsndfile

ACCEPT_KEYWORDS="~amd64" emerge --oneshot --verbose --autounmask-continue=y x11-drivers/nvidia-drivers

# Install GNOME
echo "Installing GNOME..."
emerge --ask gnome-base/gnome
# Uncomment below for minimal GNOME installation
# emerge --ask gnome-base/gnome-light

# Disable previewer for nautilus and remove GNOME online accounts
echo "Configuring nautilus and GNOME online accounts..."
mkdir -p /etc/portage/package.use
echo "gnome-base/nautilus -previewer" > /etc/portage/package.use/nautilus

# Update environment variables
echo "Updating environment variables..."
env-update && source /etc/profile

# Add user to plugdev group
echo "Adding user $USER to plugdev group..."
getent group plugdev
gpasswd -a $USER plugdev

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
