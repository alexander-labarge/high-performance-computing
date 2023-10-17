#!/bin/bash

# Target: Gentoo Linux amd-64
# This script installs Cockpit and PCP from source, and configures PAM to allow login to Cockpit.

set -e # Exit script immediately on first error.

# Cockpit doesn't necessarily require PCP as a dependency, but it's a good idea to install it anyway.
# This is due to the fact that cockpit will be unable to archive the necessary logs.
# A potential way to to get around is to emerge the grafana-pcp plugin, but I haven't tested it yet.

# During build from source, cockpit requires the following dependencies:
sudo emerge --ask net-libs/libssh

# Attempting to Compile Performance Co-Pilot (PCP) from source:
# Package Info: https://github.com/performancecopilot/pcp/releases
# Version Info: pcp-6.1.0

# PCP Can not be compiled without the Git REPO:
# Install Git to allow linkers to find the necessary files:
sudo emerge --ask dev-vcs/git

# Download the source code:
git clone https://github.com/performancecopilot/pcp.git

# ./configure unnecessary and built into Makefile:
./Makepkgs --verbose

# Fix for QtPrintSupport error:
sudo emerge -av dev-qt/qtprintsupport

# Fix for PCP User Required error:
sudo groupadd -r pcp || true
sudo useradd -c "Performance Co-Pilot" -g pcp -d /var/lib/pcp -M -r -s /usr/sbin/nologin pcp || true

# Continue with PCP Install:
cd pcp
./configure 
make -j8
make -j8 install

# Configure PAM for Cockpit:
# PAM (Pluggable Authentication Modules) is a system that allows different authentication methods to be used by applications.
# Cockpit uses PAM to authenticate users, so we need to configure PAM to allow login to Cockpit.
sudo nano /etc/pam.d/cockpit

# Add the following lines to the file:
#%PAM-1.0
auth       include      system-remote-login
account    include      system-remote-login
password   include      system-remote-login
session    include      system-remote-login

# Restart Cockpit service:
sudo systemctl restart cockpit.service
sudo systemctl status cockpit.service
