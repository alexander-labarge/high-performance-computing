# `amd64-gentoo-hpc-cockpit-install.sh` Script

The `amd64-gentoo-hpc-cockpit-install.sh` script installs Cockpit and Performance Co-Pilot (PCP) from source on an ~amd64 systemd init driven Gentoo Linux machine. The script also configures PAM login authentication to properly address problems for Cockpit Web Console login, which has been a major stopping point for source based linux distro users. 

## Background

I am leading the effort to redesign a multi-million dollar HPC cluster. The lack of a user-friendly interface for managing the HPC cluster can be a significant barrier for users who are not familiar with the command-line interface. This can lead to inefficiencies and errors in managing the cluster, which can impact performance and productivity.

The Network Admin Team requested some type of visual oversight of the cluster to be able to monitor power consumption/ power state of the HPC cluster nodes. 

## Discussion - Developer Perspective

There is no official supported ebuild on Gentoo for Cockpit due to several problems. One of the main issues is that Cockpit is a web-based graphical interface for managing Linux servers, which goes against the Gentoo philosophy of minimalism, high degree of performance, and customization. Additionally, Cockpit has many dependencies, including systemd, which is not supported by Gentoo. 

Another issue is that Cockpit is not fully compatible with Gentoo's source-based distribution model. Cockpit is designed to work with binary-based distributions like Red Hat Enterprise Linux, which have pre-built packages available in their repositories. Gentoo, on the other hand, relies on users building packages from source, which can be time-consuming and error-prone.

As a result, there is no official supported ebuild for Cockpit on Gentoo. However, users can still install Cockpit from source using the `amd64-gentoo-hpc-cockpit-install.sh` script, which installs Cockpit and Performance Co-Pilot (PCP) from source and configures PAM to allow login to Cockpit.

I will be submitting this as an ebuild for Gentoo Linux once refined. 

## Dependencies

Cockpit requires the following dependencies during the build from source:

- `net-libs/libssh`

PCP requires the following dependencies during the build from source:

- `dev-vcs/git`
- `dev-qt/qtprintsupport`

## Installation

To install Cockpit and PCP from source on Gentoo Linux, follow these steps:

1. Install the necessary dependencies using `sudo emerge --ask <dependency>`.
2. Clone the PCP source code using `git clone https://github.com/performancecopilot/pcp.git`.
3. Navigate to the PCP source code directory using `cd pcp`.
4. Run `./Makepkgs --verbose` to build PCP from source.
5. Fix the `QtPrintSupport` error by running `sudo emerge -av dev-qt/qtprintsupport`.
6. Create the `pcp` user and group by running `sudo groupadd -r pcp` and `sudo useradd -c "Performance Co-Pilot" -g pcp -d /var/lib/pcp -M -r -s /usr/sbin/nologin pcp`.
7. Continue with the PCP installation by running `./configure`, `make -j8`, and `make -j8 install`.
8. Configure PAM for Cockpit by adding the necessary lines to the `/etc/pam.d/cockpit` file.
9. Restart the Cockpit service using `sudo systemctl restart cockpit.service`.
10. Check the status of the Cockpit service using `sudo systemctl status cockpit.service`.

By following these steps, users can install Cockpit and PCP from source on Gentoo Linux, and configure PAM to allow login to Cockpit.
