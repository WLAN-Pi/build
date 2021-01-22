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

	display_alert "Use common wlanX name for interfaces" "" "info"
	sudo ln -s /dev/null /etc/udev/rules.d/80-net-setup-link.rules

	SetDefaultShell
	AddUserWLANPi
	SetupRNDIS
	SetupPipxEnviro
	InstallKismet
	InstallPipx
	InstallSpeedTestPipx
	InstallProfilerPipx
	InstallWiPerf
	SetupCockpit
	InstallFlaskWebUI
	SetupOtherServices
	SetupOtherConfigFiles

} # Main

# This sets up all external debian repos so we can call "apt update" only once here
SetupExternalRepos() {
	display_alert "Include apt repo" "WLAN Pi" "info"
	echo "deb [trusted=yes] https://apt.fury.io/dfinimundi /" > /etc/apt/sources.list.d/wlanpi.list

	apt update
}

# This installs Kismet
InstallKismet() {
	wget -O - https://www.kismetwireless.net/repos/kismet-release.gpg.key | sudo apt-key add -
	echo 'deb https://www.kismetwireless.net/repos/apt/release/buster buster main' | sudo tee /etc/apt/sources.list.d/kismet.list
	
	sudo apt update
	sudo apt install kismet -y
}

SetupPipxEnviro() {
	# Setting up Pipx in a global directory so all users in sudo group can access installed packages
	mkdir -p /opt/wlanpi/pipx/bin
	chown -R root:sudo /opt/wlanpi/pipx
	chmod -R g+rwx /opt/wlanpi/pipx
	cat <<EOF >> /etc/environment
PIPX_HOME=/opt/wlanpi/pipx
PIPX_BIN_DIR=/opt/wlanpi/pipx/bin
EOF
	# Set pipx variables for the remainder of the script
	export PIPX_HOME=/opt/wlanpi/pipx
	export PIPX_BIN_DIR=/opt/wlanpi/pipx/bin
}

InstallPipx() {
	# Install a deterministic version of pipx
	python3 -m pip install pipx==0.15.4.0
}

InstallSpeedTestPipx() {
	display_alert "Install speedtest-cli" "" "info"

	# Install unofficial speedtest-cli from pip via pipx
	pipx install speedtest-cli
}


InstallProfilerPipx() {
	display_alert "Install profiler2" "" "info"
	# install with pip via pipx
	
	pipx install git+https://github.com/wlan-pi/profiler2.git@main#egg=profiler2
	copy_overlay /lib/systemd/system/profiler.service -o root -g root -m 644
	copy_overlay /etc/profiler2/config.ini -o root -g root -m 644
}

SetupCockpit() {
	display_alert "Setup cockpit" "" "info"

	# Enable service
	systemctl enable cockpit.socket
}

SetDefaultShell() {
	# Change default shell to bash
	SHELL_BASH=$(which bash)
	display_alert "Setting default bash" "$SHELL_BASH" "info"

	sed -i "s|^SHELL=.*$|SHELL=${SHELL_BASH}|" /etc/default/useradd
}

SetupRNDIS() {
	display_alert "Setup RNDIS" "" "info"

	echo "options g_ether host_addr=5e:a4:f0:3e:31:d3 use_eem=0" > /etc/modprobe.d/g_ether.conf

	display_alert "Copy interfaces overlay" "rndis.conf" "info"
	copy_overlay /etc/network/interfaces.d/rndis.conf -o root -g root -m 644

	display_alert "Copy overlay" "isc-dhcp-server" "info"
	copy_overlay /etc/default/isc-dhcp-server -o root -g root -m 644

	display_alert "Configure DHCP" "dhcpd.conf" "info"
	cat <<-EOF >> /etc/dhcp/dhcpd.conf

# usb0 DHCP scope
subnet 169.254.42.0 netmask 255.255.255.224 {
	interface usb0;
	range 169.254.42.2 169.254.42.30;
	option domain-name-servers wlanpi.local;
	option domain-name "wlanpi.local";
	option broadcast-address 169.254.42.31;
	default-lease-time 86400;
	max-lease-time 86400;
}
EOF
}

SetupRootUser() {
	display_alert "Setup root user options" "" "info"
	rm -f /root/.not_logged_in_yet

	display_alert "Set root password" "" "info"
	echo "root:Wlanpi!" | chpasswd

	display_alert "Copy script to enable/disable root on demand to facilitate developement" "" "info"
	copy_overlay /usr/bin/enableroot -o root -g root -m 744

	display_alert "Disable root login" "" "info"
	enableroot 0
}

AddUserWLANPi() {
	display_alert "Adding WLAN Pi user" "" "info"
	useradd -m wlanpi
	echo wlanpi:wlanpi | chpasswd
	usermod -aG sudo wlanpi
	usermod -aG www-data wlanpi

	display_alert "Include system binaries in wlanpi's PATH - avoid using sudo" "" "info"
	echo 'export PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"' >> /home/wlanpi/.profile
	display_alert "Include pipx bin location in wlanpi's PATH" "" "info"
	echo 'export PATH="$PATH:/opt/wlanpi/pipx/bin"' >> /home/wlanpi/.profile
}

SetupWebGUI() {
	display_alert "Setup WebGUI" "" "info"

	git clone https://github.com/WLAN-Pi/wfe_v2.git
	cp -ra wfe_v2/site/* /var/www/html
	rm -rf wfe_v2

	chown -R www-data:www-data /var/www/html
}

InstallFlaskWebUI() {
	display_alert "Installing" "WebUI" "info"
	pipx install --include-deps git+https://github.com/wlan-pi/wlanpi-webui@main#egg=wlanpi_webui

	display_alert "Remove default config" "nginx" "info"
	rm -f /etc/nginx/sites-enabled/default

	display_alert "Configure" "nginx" "info"
	copy_overlay /etc/nginx/nginx.conf -o root -g root -m 644

	display_alert "Configure" "PHP" "info"
	copy_overlay /etc/php/7.3/fpm/php.ini -o root -g root -m 644

	display_alert "Fix permissions" "/var/www" "info"
	chown -R www-data:www-data /var/www
}

InstallWLANPiApps() {
	display_alert "Install pkg_admin modules" "" "info"
	for app in $(/usr/local/sbin/pkg_admin -c 2>/dev/null | sed -n '/---/,/---/p' | grep -v -- '---' | grep -v 'Installer script started' | grep -v -e '^$')
	do
		display_alert "Install" "$app" "info"
		/usr/local/sbin/pkg_admin -i $app
	done
}


InstallWiPerf() {
	display_alert "Setup package" "wiperf" "info"

	display_alert "Install" "wiperf_poller" "info"
	python3 -m pip install wiperf_poller
}

SetupOtherServices() {
	display_alert "Setup service" "iperf3" "info"
	copy_overlay /lib/systemd/system/iperf3.service -o root -g root -m 644
	systemctl enable iperf3

	display_alert "Setup service" "iperf2" "info"
	copy_overlay /lib/systemd/system/iperf2.service -o root -g root -m 644
	copy_overlay /lib/systemd/system/iperf2-udp.service -o root -g root -m 644

	display_alert "Setup service" "networkinfo" "info"
	copy_overlay /lib/systemd/system/networkinfo.service -o root -g root -m 644
	systemctl enable networkinfo

	display_alert "Disable service for OTG serial" "serial-getty" "info"
	if [ $LINUXFAMILY == sunxi* ]; then
		systemctl disable serial-getty@ttyS1
	elif [ $LINUXFAMILY == rockchip* ]; then
		systemctl disable serial-getty@ttyS2
	fi
}

SetupOtherConfigFiles() {
	display_alert "Set retry for dhclient" "" "info"
	if grep -q -E "^#?retry " /etc/dhcp/dhclient.conf; then
		sed -i 's/^#\?retry .*/retry 600;/' /etc/dhcp/dhclient.conf
	else
		echo "retry 600;" >> /etc/dhcp/dhclient.conf
	fi

	display_alert "Enable dynamically assigned DNS nameservers" "" "info"
	ln -sf /etc/resolvconf/run/resolv.conf /etc/resolv.conf

	display_alert "Add our custom sudoers file" "" "info"
	copy_overlay /etc/sudoers.d/wlanpidump -o root -g root -m 440

	display_alert "Add our pipx sudoers file for profiler" "" "info"
	copy_overlay /etc/sudoers.d/pipx -o root -g root -m 440

	display_alert "Copy ufw rules" "" "info"
	copy_overlay /etc/ufw/user.rules -o root -g root -m 640

	display_alert "Enable UFW on first boot script" "" "info"
	sed -i '/start)/a ufw enable' /usr/lib/armbian/armbian-firstrun

	display_alert "Setup" "TFTP" "info"
	usermod -a -G tftp wlanpi
	chown -R tftp:tftp /srv/tftp
	chmod 775 /srv/tftp
	copy_overlay /etc/default/tftpd-hpa -o root -g root -m 644

	display_alert "Copy config file" "avahi-daemon" "info"
	copy_overlay /etc/avahi/avahi-daemon.conf -o root -g root -m 644

	display_alert "Copy config file" "wpa_supplicant.conf" "info"
	copy_overlay /etc/wpa_supplicant/wpa_supplicant.conf -o root -g root -m 600

	display_alert "Copy config file" "network/interfaces" "info"
	copy_overlay /etc/network/interfaces -o root -g root -m 644

	display_alert "Configure arp_ignore" "network/arp" "info"
	echo "net.ipv4.conf.eth0.arp_ignore = 1" >> /etc/sysctl.conf

	display_alert "Copy config file" "ifplugd" "info"
	copy_overlay /etc/default/ifplugd -o root -g root -m 644

	display_alert "Copy script" "release-dhcp-lease" "info"
	copy_overlay /etc/ifplugd/action.d/release-dhcp-lease -o root -g root -m 755

	display_alert "Change default systemd boot target" "multi-user.target" "info"
	systemctl set-default multi-user.target

	display_alert "Copy config file" "RF Central Regulatory Domain Agent" "info"
	copy_overlay /etc/default/crda -o root -g root -m 644

	display_alert "Copy state file" "WLAN Pi Mode" "info"
	copy_overlay /etc/wlanpi-state -o root -g root -m 644
}

InstallMongoDB() {
	file_name="mongodb-src-r4.2.6"
	prev_pwd=$PWD
	cd /root/build

	display_alert "Download mongo" "" "info"
	wget -nc https://fastdl.mongodb.org/src/$file_name.tar.gz

	display_alert "Unpack mongo" "" "info"
	tar -zxvf $file_name.tar.gz
	cd $file_name

	display_alert "Install requirements" "" "info"
	python3 -m pip install wheel
	python3 -m pip install -r buildscripts/requirements.txt

	display_alert "Build mongo" "" "info"
	python3 buildscripts/scons.py core --ssl CCFLAGS=-march=armv8-a+crc

	display_alert "Clean up build objects" "" "info"
	cd ..
	rm -rf $file_name
	cd $prev_pwd
}

# Usage: copy_overlay <FILE_TO_COPY> [-o <owner>] [-g <group>] [-m <perms>]
copy_overlay() {
	OVERLAY_DIR="/tmp/overlay"
	INSTALL_FILE="$1"

	# Remove file from arguments
	shift

	# Make sure path to dest file exists
	mkdir -p $(dirname "$INSTALL_FILE")

	# Copy overlay with defined permissions
	install $@ "$OVERLAY_DIR$INSTALL_FILE" "$INSTALL_FILE"
}

#########
# Let's have unique way of displaying alerts
# Copied from Armbian build to standardize prints
#########
display_alert()
{
	# log function parameters to install.log
	[[ -n $DEST ]] && echo "Displaying message: $@" >> $DEST/debug/output.log

	local tmp=""
	[[ -n $2 ]] && tmp="[\e[0;33m $2 \x1B[0m]"

	case $3 in
		err)
		echo -e "[\e[0;31m error \x1B[0m] $1 $tmp"
		;;

		wrn)
		echo -e "[\e[0;35m warn \x1B[0m] $1 $tmp"
		;;

		ext)
		echo -e "[\e[0;32m o.k. \x1B[0m] \e[1;32m$1\x1B[0m $tmp"
		;;

		info)
		echo -e "[\e[0;32m o.k. \x1B[0m] $1 $tmp"
		;;

		*)
		echo -e "[\e[0;32m .... \x1B[0m] $1 $tmp"
		;;
	esac
}

Main "$@"
