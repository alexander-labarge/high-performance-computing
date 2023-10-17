#!/bin/bash

# Gentoo RSYNC Source Mirror Apptainer Image Build Script
# Author: La Barge, Alexander
# Date: 16 Oct 23 - 17 Oct 23

echo "Setting up Gentoo RSYNC Source Mirror using Apptainer..."

# Ensure we're running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# Pull the base Gentoo image
echo "Pulling base Gentoo image..."
apptainer pull docker://gentoo/stage3:amd64-systemd

# Convert Docker image to Apptainer sandbox
echo "Converting to Apptainer sandbox..."
apptainer build --sandbox ./sandbox-writeable-build docker://gentoo/stage3:amd64-systemd

# Enter the sandbox for configuration
apptainer exec -w ./sandbox-writeable-build /bin/bash <<EOF

echo "Updating Gentoo..."
emerge --sync

echo "Installing necessary packages..."
emerge net-misc/rsync
emerge bash

# Adjust prompt for clarity
export PS1="\033[1;33mapptainer-root # \w $ \033[0m"

# Setup directories for Gentoo Portage and Source Files
echo "Setting up directories..."
mkdir -p /mnt/gentoo-source
mkdir -p /mnt/gentoo-portage

echo "Fetching Gentoo Source Files from MIT..."
rsync -av --delete --progress --info=progress2 rsync://mirrors.mit.edu/gentoo-distfiles/ /mnt/gentoo-source

# Note: This step might be redundant, but kept for demonstration. 
# Consider removing if you're certain the next rsync will cover all necessary files.
echo "Copying Portage Tree..."
cp -r /var/db/repos/gentoo/* /mnt/gentoo-portage

echo "Setting up Rsync server..."
emerge rsync

echo "Configuring Rsync server for security and efficiency..."
cat > /etc/rsyncd.conf <<EOL
pid file = /var/run/rsyncd.pid
lock file = /var/run/rsync.lock
log file = /var/log/rsync.log
use chroot = yes
read only = yes
list = yes
uid = nobody
gid = nobody
max connections = 10
timeout = 300

[gentoo-portage]
    path = /mnt/gentoo-portage
    comment = Gentoo Portage Tree
    read only = yes

[gentoo-source]
    path = /mnt/gentoo-source
    comment = Gentoo Source Files (including distfiles)
    read only = yes
EOL

echo "Configuration written to /etc/rsyncd.conf."

echo "Performing final sync of Gentoo Portage Tree..."
rsync -v rsync://rsync.us.gentoo.org/gentoo-portage /mnt/gentoo-portage

echo "Performing final sync of Gentoo Source Files..."
rsync -av --delete --progress --info=progress2 rsync://mirrors.mit.edu/gentoo-distfiles/ /mnt/gentoo-source

EOF

echo "Container setup complete. You can now run your RSYNC server inside the container using 'rsync --daemon'."
echo "To test the server from outside the container, use 'rsync rsync://<container_ip>:<port>/gentoo-portage'."

# Provide the footprint of the storage inside the container
echo "Final storage footprint inside container:"
apptainer exec ./sandbox-writeable-build du -sh /mnt/gentoo-portage /mnt/gentoo-source

echo "All done!"

