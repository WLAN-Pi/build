#!/bin/bash

# arguments: $RELEASE $LINUXFAMILY $BOARD $BUILD_DESKTOP
#
# This is the image customization script

# NOTE: It is copied to /tmp directory inside the image
# and executed there inside chroot environment
# so don't reference any files that are not already installed

# NOTE: If you want to transfer files between chroot and host
# userpatches/overlay directory on host is bind-mounted to /tmp/overlay in chroot

RELEASE=$1
LINUXFAMILY=$2
BOARD=$3
BUILD_DESKTOP=$4

Main() {
	SetupRootUser
	SetupExternalRepos

	# Use common wlanX name for interfaces
	sudo ln -s /dev/null /etc/udev/rules.d/80-net-setup-link.rules

	SetDefaultShell
	AddUserWLANPi
	SetupRNDIS
	SetupOtherConfigFiles
	InstallSpeedTest

} # Main

# This sets up all external debian repos so we can call "apt update" only once here
SetupExternalRepos() {
	###### speedtest ######
	export INSTALL_KEY=379CE192D401AB61
	# Debian versions supported: jessie, stretch, buster
	export DEB_DISTRO=$(lsb_release -sc)
	sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys $INSTALL_KEY
	echo "deb https://ookla.bintray.com/debian ${DEB_DISTRO} main" | sudo tee /etc/apt/sources.list.d/speedtest.list
	###### speedtest ######

	apt update
}

InstallSpeedTest() {
	# Repo was included on SetupExternalRepos
	apt -y --allow-unauthenticated install speedtest
}

SetDefaultShell() {
	# Change default shell to bash
	SHELL_BASH=$(which bash)
	echo Found bash in $SHELL_BASH

	sed -i "s|^SHELL=.*$|SHELL=${SHELL_BASH}|" /etc/default/useradd
}

SetupRNDIS() {
	echo "options g_ether host_addr=5e:a4:f0:3e:31:d3 use_eem=0" > /etc/modprobe.d/g_ether.conf

	cat <<-EOF >> /etc/network/interfaces

# USB Ethernet
allow-hotplug usb0
iface usb0 inet static
address 169.254.42.1
netmask 255.255.255.224
EOF

	cat <<-EOF > /etc/default/isc-dhcp-server
DHCPDv4_CONF=/etc/dhcp/dhcpd.conf
DHCPDv4_PID=/var/run/dhcpd.pid
INTERFACESv4="usb0"
EOF

	cat <<-EOF >> /etc/dhcp/dhcpd.conf

# usb0 DHCP scope
subnet 169.254.42.0 netmask 255.255.255.224 {
	interface usb0;
	range 169.254.42.2 169.254.42.30;
	option domain-name-servers wlanpi.local;
	option domain-name "wlanpi.local";
	option routers 169.254.42.1;
	option broadcast-address 169.254.42.31;
	default-lease-time 600;
	max-lease-time 7200;
}
EOF
}

SetupRootUser() {
	rm -f /root/.not_logged_in_yet

	# Set root password
	echo "root:Wlanpi!" | chpasswd
	# Disable root login
	sed -i 's#\(root:.*\)/bin/bash#\1/sbin/nologin#g' /etc/passwd
}

AddUserWLANPi() {
	echo Adding WLAN Pi user
	useradd -m wlanpi
	echo wlanpi:wlanpi | chpasswd
	usermod -aG sudo wlanpi
}

InstallWLANPiApps() {
	echo Install pkg_admin modules
	for app in $(/usr/local/sbin/pkg_admin -c 2>/dev/null | sed -n '/---/,/---/p' | grep -v -- '---' | grep -v 'Installer script started' | grep -v -e '^$')
	do
		echo Install $app
		/usr/local/sbin/pkg_admin -i $app
	done
}

SetupOtherConfigFiles() {
	# Set retry for dhclient
	if grep -q -E "^#?retry " /etc/dhcp/dhclient.conf; then
		sed -i 's/^#\?retry .*/retry 15;/' /etc/dhcp/dhclient.conf
	else
		echo "retry 15;" >> /etc/dhcp/dhclient.conf
	fi

	# Set default DNS nameserver on resolveconf template
	echo "nameserver 8.8.8.8" >> /etc/resolvconf/resolv.conf.d/tail

	# Add our custom sudoers file
	install -o root -g root -m 440 /tmp/overlay/etc/sudoers.d/wlanpidump /etc/sudoers.d
}

InstallMongoDB() {
	file_name="mongodb-src-r4.2.6"
	prev_pwd=$PWD
	cd /root/build

	echo Download mongo
	wget -nc https://fastdl.mongodb.org/src/$file_name.tar.gz

	echo Unpack mongo
	tar -zxvf $file_name.tar.gz
	cd $file_name

	echo Install requirements
	python3 -m pip install wheel
	python3 -m pip install -r buildscripts/requirements.txt

	echo Build mongo
	python3 buildscripts/scons.py core --ssl CCFLAGS=-march=armv8-a+crc

	echo Clean up build objects
	cd ..
	rm -rf $file_name
	cd $prev_pwd
}

Main "$@"
