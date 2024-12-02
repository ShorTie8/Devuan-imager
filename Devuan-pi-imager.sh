#!/bin/bash
# A simple script to make your own Devuan Image
#
# BeerWare By ShorTie	<shortie8@verizon.net> 

# Turn off path caching.
set +h

Devuan_ReLease=daedalus
Debian_ReLease=bookworm

# From  http://deb.devuan.org/devuan/pool/main/d/debootstrap
DeBootStrap=debootstrap_1.0.137devuan1.tar.gz

hostname=Devuan
root_password=toor 	# Re-Define your own root password here

timezone=America/New_York 	# You can define this here or remark out or leave blank to use current systems
locales=en_US.UTF-8			# You can define this here or remark out or leave blank to use current systems
default_locale=en_US.UTF-8	# You can define this here or remark out or leave blank to use current systems

number_of_keys=104		# You can define this here or remark out or leave blank to use current systems
keyboard_layout=us		# must be defined if number_of_keys is defined
keyboard_variant=		# blank is normal
keyboard_options=		# blank is normal
backspace=guess			# guess is normal

PI=Yuppers

#************************************************************************

# Define message colors
OOPS="\033[1;31m"    # red
DONE="\033[1;32m"    # green
INFO="\033[1;33m"    # yellow
STEP="\033[1;34m"    # blue
WARN="\033[1;35m"    # hot pink
BOUL="\033[1;36m"	 # light blue
NO="\033[0m"         # normal/light

# Define our oops and set trap
fail () {
    echo -e "${WARN}\n\n  Oh no's,${INFO} Sumfin went wrong\n ${NO}"
    echo -e "${DONE}  Cleaning up my mess .. ${OOPS}:(~ ${NO}"
    umount sdcard/proc
    umount sdcard/sys
    umount sdcard/dev/pts
    fuser -av sdcard
    fuser -kv sdcard
    umount sdcard/boot
    fuser -k sdcard
    umount sdcard
    kpartx -dv Image
    rm -rf sdcard
  #  rm Image
    exit 1
}

echo -e "${DONE}  Setting Trap ${NO}"
trap "echo; echo \"Unmounting /proc\"; fail" SIGINT SIGTERM


# Check to see if Devuan-pi-imager.sh is being run as root
start_time=$(date)
echo -e "${DONE}\n  Checking for root .. ${NO}"
if [ `id -u` != 0 ]; then
    echo "nop"
    echo -e "Ooops, Devuan-pi-imager.sh needs to be run as root !!\n"
    echo " Try 'sudo sh, ./Devuan-pi-imager.sh' as a user"
    exit
else
    echo -e "${INFO}  Yuppers,${BOUL} root it tis ..${DONE} :)~${NO}"
fi

if [ ! -e debs/Dependencies-ok ]; then
  echo -e "${DONE}\n  Installing dependencies ..  ${NO}"
    apt install dosfstools file kpartx libc6-dev parted psmisc xz-utils || fail
  touch debs/Dependencies-ok
fi


echo -e "${INFO}  Making sure of a kleen enviroment .. ${BOUL}:/~ ${NO}"
umount sdcard/proc
umount sdcard/sys
umount sdcard/dev/pts
fuser -av sdcard
fuser -kv sdcard
umount sdcard/boot
fuser -k sdcard
umount sdcard
kpartx -dv Image
rm -rvf sdcard
#rm Image

if [ ! -f Image ]; then
	echo -e "${DONE}  Creating Zero filled Image File ${NO}"
	dd if=/dev/zero of=Image  bs=1M  count=4200 iflag=fullblock
else
	echo -e "${DONE}  Zero out, First 420 Puff's of Image File ${NO}"
	dd if=/dev/zero of=Image  bs=1M  count=420 conv=notrunc status=progress
fi

DATE=$(date +"%Y%m%d")
UnameMe=`uname -m`

case ${UnameMe} in
	armhf)
		ARCH=armhf ;;
	aarch64)
		ARCH=arm64 ;;
	x86_64)
		ARCH=amd64 ;;
  esac

Image_Name=Devuan-${DATE}-${Devuan_ReLease}.${DATE}.img
echo ${Image_Name}

# Create partitions
echo -e "${DONE}\n\n  Creating partitions ${NO}"
fdisk Image <<EOF
o
n
p
1

+256M
a
t
b
n
p
2


w
EOF

echo -e "${DONE}\n  Setting up drive mapper ${NO}"
loop_device=$(losetup --show -f Image) || fail

echo -e "${DONE}    Loop device is ${DONE} $loop_device ${NO}"
echo -e "${DONE}  Partprobing $loop_device ${NO}"
partprobe ${loop_device}
bootpart=${loop_device}p1
rootpart=${loop_device}p2
echo -e "${DONE}    Boot partition is ${DONE} $bootpart ${NO}"
echo -e "${DONE}    Root partition is ${DONE} $rootpart ${NO}"

# Format Partitions
echo -e "${DONE}\n  Formating the Partitions ${NO}"
echo "mkfs.vfat -n boot $bootpart"
mkfs.vfat -n BOOT $bootpart
echo
echo "mkfs.ext4 -O ^huge_file  -L Devuan $rootpart"; echo
echo y | mkfs.ext4 -O ^huge_file  -L Devuan $rootpart && sync
echo

P1_UUID="$(lsblk -o PTUUID "${loop_device}" | sed -n 2p)-01"
P2_UUID="$(lsblk -o PTUUID "${loop_device}" | sed -n 2p)-02"
echo "P1_UUID = ${P1_UUID}"
echo "P2_UUID = ${P2_UUID}"

echo -e "${DONE}\n  Setting up for DeBootStrap ${NO}"
mkdir -v sdcard
mount -v -t ext4 -o sync $rootpart sdcard

if [ ! -d debs/${ARCH}/${Devuan_ReLease} ]; then
  echo -e "${DONE}\n  Making debs directory ${NO}"
  mkdir -vp debs/${ARCH}/${Devuan_ReLease}
fi

if [ -f debs/${ARCH}/${Devuan_ReLease}/eudev*.deb ]; then
  echo -e "${DONE}\n  Copying debs ${NO}"
  du -sh debs/${ARCH}/${Devuan_ReLease}
  mkdir -vp sdcard/var/cache/apt/archives
  cp debs/${ARCH}/${Devuan_ReLease}/*.deb sdcard/var/cache/apt/archives
fi

if [ ! -d debs/debootstrap ]; then
    wget -P debs https://pkgmaster.devuan.org/devuan/pool/main/d/debootstrap/${DeBootStrap} || fail
    mkdir -vp debs/debootstrap
    tar xf debs/${DeBootStrap} -C debs/debootstrap
fi


##	devuan_keyring
if [ ! -f "/usr/share/keyrings/devuan-keyring.gpg" ]; then
	echo -e "${DONE} Installing Devuan keyring"
	URL="https://pkgmaster.devuan.org/devuan/pool/main/d/devuan-keyring/"
	FILE="devuan-keyring_2023.10.07_all.deb"
	wget -nc --show-progress ${URL}${FILE}
	dpkg -i ${FILE}
	rm -v ${FILE}
else
	echo -e "${INFO} Already have Devuan keyring${NO}"
fi

##	
# These are added to debootstrap now so no setup Dialog boxes are done, configuration done later.
include="--include=apt-utils,kbd,locales,locales-all,gnupg,wget,keyboard-configuration,console-setup,dphys-swapfile,miniupnpd,devuan-keyring"
exclude=
#exclude="--exclude= "

echo -e "${DONE}\n  DeBootStrap's line is ${NO}"
DeBootStrapline=" --arch ${ARCH} ${include} ${exclude} ${Devuan_ReLease} sdcard"
echo ${DeBootStrapline}; echo
DEBOOTSTRAP_DIR=debs/debootstrap/source debs/debootstrap/source/debootstrap --arch ${ARCH} ${include} ${exclude} ${Devuan_ReLease} sdcard || fail

echo -e "${DONE}\n  Mount new chroot system\n ${NO}"
mount -v -t vfat -o sync $bootpart sdcard/boot
mount -v proc sdcard/proc -t proc
mount -v sysfs sdcard/sys -t sysfs
mount -v --bind /dev/pts sdcard/dev/pts

#mount -v --rbind /dev sdcard/dev
#mount -v --rbind /sys sdcard/sys
#mount -v -t proc /proc sdcard/proc



# Adjust a few things
echo -e "${INFO}\n\n  Copy, adjust and reconfigure ${NO}"

##	################# sources.list  ####################################################################################### 
echo -e "${WARN}\n  Adjusting /etc/apt/sources.list from/too... ${NO}"
echo -en "${WARN} From: ${DONE}"
cat sdcard/etc/apt/sources.list
echo -e "${BOUL} To:"
tee sdcard/etc/apt/sources.list <<EOF
deb http://deb.devuan.org/merged daedalus main non-free-firmware
deb-src http://deb.devuan.org/merged daedalus main non-free-firmware

deb http://deb.devuan.org/merged daedalus-security main non-free-firmware
deb-src http://deb.devuan.org/merged daedalus-security main non-free-firmware

# daedalus-updates, to get updates before a point release is made;
# see https://www.debian.org/doc/manuals/debian-reference/ch02.en.html#_updates_and_backports
deb http://deb.devuan.org/merged daedalus-updates main non-free-firmware
deb-src http://deb.devuan.org/merged daedalus-updates main non-free-firmware

EOF
echo -e "${NO}"

if [ "$PI" = "Yuppers" ] && [ "$ARCH" = "arm64" ]; then
	#	###########  Install raspberrypi.gpg.key  ################
	echo -e "${DONE}\n    Install raspberrypi.gpg.key   ${NO}"
	if [ ! -f debs/raspberrypi-archive-keyring_2016.10.31_all.deb ]; then
		wget -nc https://archive.raspberrypi.org/debian/pool/main/r/raspberrypi-archive-keyring/raspberrypi-archive-keyring_2016.10.31_all.deb -O debs/raspberrypi-archive-keyring_2016.10.31_all.deb
	fi
	cp -v  debs/raspberrypi-archive-keyring_2016.10.31_all.deb sdcard/
	chroot sdcard dpkg -i raspberrypi-archive-keyring_2016.10.31_all.deb
	rm -v sdcard/raspberrypi-archive-keyring_2016.10.31_all.deb
	
	echo -e "${DONE}\n  Creating raspi.list ${NO}"
	tee sdcard/etc/apt/sources.list.d/raspi.list <<EOF
deb http://archive.raspberrypi.org/debian/ ${Debian_ReLease} main
# Uncomment line below then 'apt-get update' to enable 'apt-get source'
#deb-src http://archive.raspberrypi.org/debian/ buster main
EOF

fi

	chroot sdcard apt update
	chroot sdcard apt upgrade -y

	
	##	raspberrypi-archive-keyring
#	chroot sdcard apt-get install -y raspberrypi-archive-keyring || fail
#	echo -e "${DONE}\n  Add archive.raspberrypi gpg.key ${NO}"

#	if [ ! -d debs/raspberrypi.gpg.key ]; then
#		wget -nc -P debs http://archive.raspberrypi.org/debian/raspberrypi.gpg.key || fail
#	fi
#	cp -v debs/raspberrypi.gpg.key sdcard
#	#ls /usr/share/keyrings/
#	chroot sdcard apt-key add raspberrypi.gpg.key
#	#chroot sdcard curl -sS http://archive.raspberrypi.org/debian/raspberrypi.gpg.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/raspberrypi.gpg || fail

#	#rm -v sdcard/raspberrypi.gpg.key
#	mv -vf sdcard/etc/apt/trusted.gpg sdcard/etc/apt/trusted.gpg.d/raspbian-archive-keyring.gpg || fail


echo -en "${DONE}\n  Adjusting locales too...  ${NO}"
if [ "$locales" == "" ]; then 
    cp -v /etc/locale.gen sdcard/etc/locale.gen
else
    sed -i "s/^# \($locales .*\)/\1/" sdcard/etc/locale.gen
fi
grep -v '^#' sdcard/etc/locale.gen

echo -en "${DONE}\n  Adjusting default local too...  ${NO}"
if [ "$default_locale" == "" ]; then 
    default_locale=$(fgrep "=" /etc/default/locale | cut -f 2 -d '=')
fi
echo $default_locale

echo -e "${DONE}\n  local-gen  LANG=${default_locale} ${NO}"
chroot sdcard locale-gen LANG="$default_locale"

echo -e "${DONE}\n  dpkg-reconfigure -f noninteractive locales ${NO}"
chroot sdcard dpkg-reconfigure -f noninteractive locales

echo -en "${DONE}  Changing timezone too...   America/New_York  ${NO}"
echo "America/New_York" > sdcard/etc/timezone
rm -v sdcard/etc/localtime
cat sdcard/etc/timezone

echo -e "${DONE}\n  dpkg-reconfigure -f noninteractive tzdata ${NO}"
chroot sdcard dpkg-reconfigure -f noninteractive tzdata

echo -e "${DONE}\n  Setting up keyboard ${NO}"
if [ "$number_of_keys" == "" ]; then 
    cp -v /etc/default/keyboard sdcard/etc/default/keyboard
else
    # adjust variables
    xkbmodel=XKBMODEL='"'$number_of_keys'"'
    xkblayout=XKBLAYOUT='"'$keyboard_layout'"'
    xkbvariant=XKBVARIANT='"'$keyboard_variant'"'
    xkboptions=XKBOPTIONS='"'$keyboard_options'"'
    backspace=BACKSPACE='"'$backspace'"'

    # make keyboard file
    cat <<EOF > sdcard/etc/default/keyboard
# KEYBOARD CONFIGURATION FILE

$xkbmodel
$xkblayout
$xkbvariant
$xkboptions

$backspace

EOF
fi
cat sdcard/etc/default/keyboard

echo -e "${DONE}\n  dpkg-reconfigure -f noninteractive keyboard-configuration ${NO}"
chroot sdcard dpkg-reconfigure -f noninteractive keyboard-configuration

#echo -e "${DONE}\n  Install ${DONE}consolekit\n ${NO}"
#chroot sdcard apt-get install -y consolekit logind || fail



echo -e "${DONE}\n  dpkg-reconfigure -f noninteractive console-setup ${NO}"
chroot sdcard dpkg-reconfigure -f noninteractive console-setup


echo -e "${DONE}\n  Setting up networking ${NO}"
echo $hostname > sdcard/etc/hostname
echo 'nameserver 8.8.8.8' > sdcard/etc/resolv.conf
echo 'nameserver 8.8.4.4' >> sdcard/etc/resolv.conf

cat <<EOF > sdcard/etc/hosts
127.0.0.1	localhost
::1		localhost ip6-localhost ip6-loopback
ff02::1		ip6-allnodes
ff02::2		ip6-allrouters

127.0.1.1	${hostname}

EOF

echo -e "${DONE}\n  Create sdcard/etc/network/interfaces ${NO}"
tee sdcard/etc/network/interfaces <<EOF
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
allow-hotplug eth0
iface eth0 inet dhcp

EOF

echo -e "${DONE}\n  hostname ${NO}"; cat sdcard/etc/hostname
echo -e "${DONE}\n  resolv.conf ${NO}"; cat sdcard/etc/resolv.conf
echo -e "${DONE}\n  hosts ${NO}"; cat sdcard/etc/hosts

echo -e "${DONE}  Creating fstab ${NO}"
cat <<EOF > sdcard/etc/fstab
#<file system>  <dir>          <type>   <options>       <dump>  <pass>
proc            /proc           proc    defaults          0       0
PARTUUID=${P1_UUID}  /boot           vfat    defaults          0       2
PARTUUID=${P2_UUID}  /               ext4    defaults,noatime  0       1
# a swapfile is not a swap partition, so no using swapon|off from here on, use  dphys-swapfile swap[on|off]  for that
EOF
cat sdcard/etc/fstab && sync; echo

# root=/dev/mmcblk0p2  or  root=PARTUUID=${P2_UUID} rootfstype=ext4 elevator=deadline fsck.repair=yes rootwait
#/dev/mmcblk0p1  /boot           vfat    defaults          0       2
#/dev/mmcblk0p2  /               ext4    defaults,noatime  0       1

echo -e "${DONE}\n  Setting dphys-swapfile size to 100meg ${NO}"
echo "CONF_SWAPSIZE=100" > sdcard/etc/dphys-swapfile

#	###########  Set up User's  ################

echo -e "${DONE}\n  Setup user pi  ${NO}"
chroot sdcard adduser pi --gecos "${hostname}" --disabled-password
echo pi:toor | chroot sdcard chpasswd

chroot sdcard groupadd spi
chroot sdcard groupadd i2c
chroot sdcard groupadd gpio

chroot sdcard adduser pi adm
chroot sdcard adduser pi dialout
chroot sdcard adduser pi cdrom
chroot sdcard adduser pi sudo
chroot sdcard adduser pi audio
chroot sdcard adduser pi video
chroot sdcard adduser pi plugdev
chroot sdcard adduser pi games
chroot sdcard adduser pi users
chroot sdcard adduser pi input
chroot sdcard adduser pi disk
chroot sdcard adduser pi render
chroot sdcard adduser pi lpadmin
chroot sdcard adduser pi spi
chroot sdcard adduser pi i2c
chroot sdcard adduser pi gpio
chroot sdcard adduser pi netdev

echo -e "${OOPS}#######################################################################################################################${NO}"
echo -e "${DONE}###########  Done with Basic System  ##################################################################################${NO}"
echo -e "${INFO}#######################################################################################################################${NO}"


echo -e "${OOPS}###########################################################################################################${NO}"
echo -e "${DONE}###########  More basic Stuff  #####################################################################################${NO}"
echo -e "${INFO}###########################################################################################################${NO}"
echo; echo
chroot sdcard apt-get install -y binutils firmware-linux firmware-linux-free firmware-linux-nonfree firmware-realtek initramfs-tools \
		libpython3.11-minimal ntp python3 python3-tk python3-venv python3.11-venv python3-tk-dbg tcl8.6 tk8.6 tcl-tclreadline rsyslog wget zip zlib1g


#echo -e "${OOPS}###########################################################################################################${NO}"
#echo -e "${DONE}###########  apt-cache search rasp  #####################################################################################${NO}"
#echo -e "${INFO}###########################################################################################################${NO}"
#echo; echo
#chroot sdcard apt-cache search rasp



echo -e "${OOPS}###########################################################################################################${NO}"
echo -e "${DONE}###########  linux-image for ${ARCH}  ########################################################################${NO}"
echo -e "${INFO}###########################################################################################################${NO}"


if [ "${PI}" = "Yuppers" ]; then
	chroot sdcard apt-get install -y firmware-realtek || fail
	#chroot sdcard apt-get install -y raspi-firmware
#	chroot sdcard apt-get install -y linux-image-rpi-v8 firmware-realtek || fail

	##	###########  Install Kernel  ##########################################################################################
	echo -e "${WARN}\n    Install kernel   ${NO}"
	if [ ! -f "debs/Raspi_FirmWare.tar.gz" ]; then
		wget -nc https://github.com/raspberrypi/firmware/archive/refs/heads/master.zip -O debs/Raspi_FirmWare.tar.gz
	fi
	pv debs/Raspi_FirmWare.tar.gz | tar -zxpf - --xattrs-include='*.*' -C sdcard/tmp || fail
	KERNEL=$(ls sdcard/tmp/firmware-master/modules | grep v8+ | cut -d"-" -f1 | awk '{print$1}')
	echo -e "${DONE}    KERNEL ${DONE} ${KERNEL}  ${NO}"
	echo "boot"
	cp -r sdcard/tmp/firmware-master/boot/* sdcard/boot
	echo "${KERNEL}-v8+"
	cp -r sdcard/tmp/firmware-master/modules/${KERNEL}-v8+/* sdcard/lib/modules
	echo "${KERNEL}-v8-16k+"
	cp -r sdcard/tmp/firmware-master/modules/${KERNEL}-v8-16k+ sdcard/lib/modules
	
	#	chroot sdcard apt-get -y install raspi-firmware raspberrypi-kernel || fail
	#chroot sdcard apt-get -y install raspberrypi-bootloader raspberrypi-kernel || fail

	echo; echo " ls boot"
	ls sdcard/boot
	echo; echo " ls lib/modules"
	ls sdcard/lib/modules
	echo

	echo -e "${DONE}\n    Crud Removal  ${DONE} ${KERNEL}  ${NO}"
	if [ "${ARCH}" = "armhf" ]; then
		rm -v sdcard/boot/{fixup4.dat,fixup4x.dat,fixup4cd.dat,fixup4db.dat}
		rm -v sdcard/boot/{start4.elf,start4x.elf,start4cd.elf,start4db.elf}
		rm -v sdcard/boot/kernel8.img
		rm -v sdcard/boot/bcm2711-rpi-4-b.dtb
		ls sdcard/lib/modules
		rm -rf sdcard/lib/modules/${KERNEL}-v8+
		ls sdcard/lib/modules
	elif [ "${ARCH}" = "arm64" ]; then
		rm -v sdcard/boot/{bootcode.bin,fixup.dat,fixup_x.dat,fixup_cd.dat,fixup_db.dat}
		rm -v sdcard/boot/{start.elf,start_x.elf,start_cd.elf,start_db.elf}
		rm -v sdcard/boot/{kernel.img,kernel7.img,kernel7l.img}
		rm -v sdcard/boot/{bcm2708-rpi-cm.dtb,bcm2708-rpi-b.dtb,bcm2708-rpi-b-rev1.dtb,bcm2708-rpi-b-plus.dtb}
		rm -v sdcard/boot/{bcm2708-rpi-zero.dtb,bcm2708-rpi-zero-w.dtb,bcm2709-rpi-2-b.dtb}
		rm -v sdcard/boot/{bcm2710-rpi-2-b.dtb,bcm2710-rpi-cm3.dtb,bcm2710-rpi-3-b.dtb,bcm2710-rpi-3-b-plus.dtb}
		echo -e "${DONE}From:${INFO}"
		ls sdcard/lib/modules
		echo -e "${DONE}"
		rm -rf sdcard/lib/modules/{${KERNEL}+,${KERNEL}-v7+,${KERNEL}-v7l+}
		echo -e "${DONE}To:${INFO}"
		ls sdcard/lib/modules
		echo -e "${NO}"
	else
		echo "UnKnum ARCH ${ARCH}"
	fi







	echo; echo " ls lib/modules"
	ls sdcard/boot
	ls sdcard/lib/modules



elif [ "${ARCH}" = "amd64" ]; then
	chroot sdcard apt-get install -y linux-image-${ARCH} intel-microcode amd64-microcode
else
	echo "UnKnum ARCH ${ARCH}"
	exit 1
fi


#
# W: Couldn't identify type of root file system for fsck hook

#The following additional packages will be installed:
#  apparmor busybox firmware-linux-free initramfs-tools initramfs-tools-core klibc-utils libklibc linux-base linux-image-6.1.0-28-arm64 zstd
#Suggested packages:
#  apparmor-profiles-extra apparmor-utils bash-completion linux-doc-6.1 debian-kernel-handbook


echo -e "${OOPS}###########################################################################################################${NO}"
echo -e "${DONE}###########  apache2  #####################################################################################${NO}"
echo -e "${INFO}###########################################################################################################${NO}"
echo; echo
#chroot sdcard apt-get install -y apache2



#	###########  ssh, root passwd && extra's  ################

echo -e "${DONE}\n  Install ${DONE}ssh\n ${NO}"
chroot sdcard apt-get install -y ssh --no-install-recommends || fail

echo -e "${DONE}\n  Setting up the root password... ${NO} $root_password "
echo root:$root_password | chroot sdcard chpasswd

echo -e "${DONE}\n  Allowing root to log into $Devuan_ReLease with password...  ${NO}"
sed -i 's/.*PermitRootLogin prohibit-password/PermitRootLogin yes/' sdcard/etc/ssh/sshd_config
grep 'PermitRootLogin' sdcard/etc/ssh/sshd_config
cp -v bashrc.root sdcard/root/.bashrc



cp -v bashrc.root sdcard/home/pi/.bashrc

#	########### Final setup		###########

## SmoothWall


echo -e "${OOPS}###########################################################################################################${NO}"
echo -e "${DONE}###########  apache2  #####################################################################################${NO}"
echo -e "${INFO}###########################################################################################################${NO}"
echo; echo
#chroot sdcard apt-get install -s apache2





echo -e "${OOPS}###########################################################################################################${NO}"
echo -e "${DONE}###########  grub2-common  #####################################################################################${NO}"
echo -e "${INFO}###########################################################################################################${NO}"
echo; echo
#chroot sdcard apt-get install -s grub2-common

echo -e "${OOPS}###########################################################################################################${NO}"
echo -e "${DONE}###########  libreswan  #####################################################################################${NO}"
echo -e "${INFO}###########################################################################################################${NO}"
echo; echo
#chroot sdcard apt-get install -s libreswan

echo -e "${OOPS}###########################################################################################################${NO}"
echo -e "${DONE}###########  clamav  #####################################################################################${NO}"
echo -e "${INFO}###########################################################################################################${NO}"
echo; echo
#chroot sdcard apt-get install -s clamav
##	The following additional packages will be installed:
##	  ca-certificates clamav-base clamav-freshclam libbrotli1 libclamav11 libcurl4 libicu72 libjson-c5 libmspack0 libnghttp2-14 librtmp1 libssh2-1 libxml2 openssl
##	Suggested packages:
##  libclamunrar clamav-docs apparmor libclamunrar11

#echo; echo
#Pre-Depends="libgeoip1 python3 acpica-tools apcupsd at attr autoconf automake bash bc binutils bison busybox bzip2 c-icap libc-icap-mod-contentfiltering libc-icap-mod-urlcheck libc-icap-mod-virus-scan libcairo2 wodim clamav coreutils cpio cron libdb5.3 dejagnu isc-dhcp-server dhcpcd dialog diffutils dnsmasq dosfstools e2fsprogs ethtool udev expat expect file findutils flex fontconfig fping fonts-freefont-ttf fonts-freefont-otf libfreetype6 gawk gcc libgd3 libgd-tools gdb libgdbm6 gettext git libglib2.0-0 libc6 libgmp10 gperf grep groff gzip hdparm apache2 iftop inotify-tools iperf iproute2 ipset iptables iputils-ping joe kbd klibc-utils kmod less libcap2-bin libcap-ng0 libdumbnet1 libevent-2.1-7 libffi8 libmnl0 libnet1 libnetfilter-acct1 libnetfilter-conntrack3 libnetfilter-cthelper0 libnetfilter-cttimeout1 libnetfilter-log1 libnetfilter-queue1 libnfnetlink0 libnftnl11 libosip2-15 libpcap0.8 libpng16-16 libtool libusb-0.1-4 libusb-1.0-0 libxml2 libxslt1.1 lm-sensors logrotate lynx m4 make python3-mako man-db manpages mdadm miniupnpd libmpc3 libmpfr6 mtools nano nasm ncurses-bin libncurses5 libneon27 net-tools libnewt0.52 libnspr4 libnss3 ntpdate libldap-2.5-0 openntpd openssh-client openssh-server openssl libreswan libpango-1.0-0 parted patch pciutils pcmciautils libpcre3 perl libpixman-1-0 pkg-config libpopt0 ppp procinfo procinfo-ng procps psmisc libreadline8 reiserfsprogs rrdtool rsync screen sed passwd libslang2 smartmontools libsqlite3-0 squid squidguard strace subversion sudo suricata sysfsutils rsyslog sysvinit tar tcl tcpdump texinfo unbound usb-modeswitch usbutils util-linux vim wget whois wireless-tools xtables-addons-common xz-utils libyaml-0-2 zip zlib1g"
#chroot sdcard apt-get install -s ${Pre-Depends}


echo -e "${OOPS}###########################################################################################################${NO}"
echo -e "${DONE}###########  linux-headers-${ARCH}  #####################################################################################${NO}"
echo -e "${INFO}###########################################################################################################${NO}"
echo; echo

#chroot sdcard apt-get install -s linux-headers-${ARCH} || fail

##	raspberrypi-kernel-headers



echo -e "${OOPS}###########################################################################################################${NO}"
echo -e "${DONE}###########  build-dep  #####################################################################################${NO}"
echo -e "${INFO}###########################################################################################################${NO}"

#chroot sdcard apt-get build-dep -s clamav
##chroot sdcard apt-get build-dep -s snort
#chroot sdcard apt-get build-dep -s libreswan
#chroot sdcard apt-get build-dep -s miniupnpd

echo -e "${OOPS}###########################################################################################################${NO}"
echo -e "${DONE}###########  Depends  #####################################################################################${NO}"
echo -e "${INFO}###########################################################################################################${NO}"

ls sdcard/lib/modules



echo -e "${DONE}  Some Depend's ${NO}"
DePends="libgeoip1 python3 acpica-tools apcupsd at attr autoconf automake \
				bash bc binutils bison busybox bzip2 c-icap libc-icap-mod-contentfiltering \
				libc-icap-mod-urlcheck libc-icap-mod-virus-scan libcairo2 wodim clamav \
				coreutils cpio cron libdb5.3 dejagnu isc-dhcp-server dhcpcd dialog diffutils \
				dnsmasq dosfstools e2fsprogs ethtool udev expat expect file findutils flex fontconfig \
				fping fonts-freefont-ttf fonts-freefont-otf libfreetype6 gawk gcc libgd3 libgd-tools \
				gdb libgdbm6 gettext git libglib2.0-0 libc6 libgmp10 gperf grep groff gzip hdparm \
				apache2 iftop inotify-tools iperf iproute2 ipset iptables iputils-ping joe kbd \
				klibc-utils kmod less libcap2-bin libcap-ng0 libdumbnet1 libevent-2.1-7 libffi8 \
				libmnl0 libnet1 libnetfilter-acct1 libnetfilter-conntrack3 libnetfilter-cthelper0 \
				libnetfilter-cttimeout1 libnetfilter-log1 libnetfilter-queue1 libnfnetlink0 libnftnl11 \
				libosip2-15 libpcap0.8 libpng16-16 libtool libusb-0.1-4 libusb-1.0-0 libxml2 libxslt1.1 \
				lm-sensors logrotate lynx m4 make python3-mako man-db manpages mdadm miniupnpd-nftables libmpc3 \
				libmpfr6 mtools nano nasm ncurses-bin libncurses5 libneon27 net-tools libnewt0.52 \
				libnspr4 libnss3 ntpdate libldap-2.5-0 openntpd openssh-client openssh-server openssl \
				libpango-1.0-0 parted patch pciutils pcmciautils libpcre3 perl libpixman-1-0 \
				pkg-config libpopt0 ppp procinfo procinfo-ng procps psmisc libreadline8 reiserfsprogs \
				rrdtool rsync screen sed passwd libslang2 smartmontools libsqlite3-0 squid squidguard \
				strace subversion sudo suricata sysfsutils rsyslog sysvinit tar tcl tcpdump texinfo \
				unbound usb-modeswitch usbutils util-linux uuid-runtime vim wget whois wireless-tools \
				xtables-addons-common xz-utils libyaml-0-2 zip zlib1g"
# chroot sdcard apt-get install -s ${DePends} || fail

ls sdcard/lib/modules

echo -e "${DONE} miniupnpd ${NO}"
chroot sdcard apt-get install -y miniupnpd

echo -e "${OOPS}###########################################################################################################${NO}"
echo -e "${DONE}###########  End Depends  #################################################################################${NO}"
echo -e "${INFO}###########################################################################################################${NO}"

echo -e "${OOPS}###########################################################################################################${NO}"
echo -e "${DONE}###########  SmoothWall  ##################################################################################${NO}"
echo -e "${INFO}###########################################################################################################${NO}"

if [ ! -f "smoothwall-express_4.0pa-1_amd64.deb" ]; then
	wget -O smoothwall-express_4.0pa-1_amd64.deb.gz https://community.smoothwall.org/forum/download/file.php?id=5897
	gunzip smoothwall-express_4.0pa-1_amd64.deb.gz
	rm -v  smoothwall-express_4.0pa-1_amd64.deb.gz
else
	echo "Already gotit"
fi

if [ "$ARCH" = "amd64" ]; then
		echo "ARCH=amd64"
		cp -v smoothwall-express_4.0pa-1_amd64.deb sdcard
		chroot sdcard dpkg -i smoothwall-express_4.0pa-1_amd64.deb
else
#smoothwall-express_4.0pa-1_amd64.deb.gz

	if [ ! -f "temp/lookit/data.tar.xz" ]; then
		mkdir lookit; cd lookit
		ar x ../smoothwall-express_4.0pa-1_amd64.deb
	fi
	pv temp/lookit/data.tar.xz | tar -Jxpf - --xattrs-include='*.*' -C sdcard || fail
fi





if [ "$PI" = "Yuppers" ]; then
echo -e "${OOPS}#######################################################################################################################${NO}"
echo -e "${DONE}########### ${WARN} pi Stuff  ${DONE}################################################################################################${NO}"
echo -e "${STEP}#######################################################################################################################${NO}"
	echo -e "${DONE}\n  Creating cmdline.txt ${NO}"
	tee sdcard/boot/cmdline.txt <<EOF
console=serial0,115200 console=tty1 root=PARTUUID=${P2_UUID} rootfstype=ext4 elevator=deadline fsck.repair=yes rootwait
EOF

	echo -e "${DONE}\n  Copy config.txt ${NO}"
	if [ ! -f debs/config.armhf ]; then
		echo; echo; echo "downloading"; echo
		wget https://raw.githubusercontent.com/RPi-Distro/pi-gen/master/stage1/00-boot-files/files/config.txt -O debs/config.armhf || fail
	fi
	if [ ! -f debs/config.arm64 ]; then
		echo; echo; echo "downloading"; echo
		wget https://raw.githubusercontent.com/RPi-Distro/pi-gen/master/stage1/00-boot-files/files/config.txt || fail
		cp -v config.txt debs/config.armhf
		sed '4 i #dtoverlay=sdtweak,poll_once=on' config.txt > config.txt.new
		sed '4 i #dtoverlay=i2c-rtc,ds3231' config.txt.new > config.txt.new.1
		sed '4 i dtoverlay=i2c-rtc,ds1307' config.txt.new.1 > config.txt.new.2
		sed '4 i dtparam=random=on' config.txt.new.2 > config.txt.new.3
		sed '4 i arm_64bit=1' config.txt.new.3 > config.txt.new.4
		sed '/Some settings/G' config.txt.new.4 > debs/config.arm64
		rm -v config.txt config.txt.new config.txt.new.*
		sed -i 's/#hdmi_group=1/hdmi_group=1/' debs/config.arm64
		sed -i 's/#hdmi_mode=1/hdmi_mode=4/' debs/config.arm64
		sed -i 's/#dtparam=i2c_arm=on/dtparam=i2c_arm=on/' debs/config.arm64
	fi
	cp -v debs/config.${ARCH} sdcard/boot/config.txt

	echo -e "${DONE}\n  Adding wifi firmware ${NO}"
	if [ ! -f debs/brcmfmac.tar.xz ]; then
		echo; echo; echo "downloading"; echo
		mkdir -vp sdcard/lib/firmware/brcm
		wget -nc -P sdcard/lib/firmware/brcm https://github.com/RPi-Distro/firmware-nonfree/raw/master/brcm/brcmfmac43430-sdio.bin || fail
		wget -nc -P sdcard/lib/firmware/brcm https://raw.githubusercontent.com/RPi-Distro/firmware-nonfree/master/brcm/brcmfmac43430-sdio.txt || fail
		wget -nc -P sdcard/lib/firmware/brcm https://github.com/RPi-Distro/firmware-nonfree/raw/master/brcm/brcmfmac43455-sdio.bin || fail
		wget -nc -P sdcard/lib/firmware/brcm https://github.com/RPi-Distro/firmware-nonfree/raw/master/brcm/brcmfmac43455-sdio.clm_blob || fail
		wget -nc -P sdcard/lib/firmware/brcm https://raw.githubusercontent.com/RPi-Distro/firmware-nonfree/master/brcm/brcmfmac43455-sdio.txt || fail
		tar -cJf debs/brcmfmac.tar.xz sdcard/lib/firmware/brcm/*
	fi
	tar xf debs/brcmfmac.tar.xz

	echo -e "${DONE}\n  Adding Raspberry Pi tweaks to sysctl.conf ${NO}"
	echo "" >> sdcard/etc/sysctl.conf
	echo "# http://www.raspberrypi.org/forums/viewtopic.php?p=104096" >> sdcard/etc/sysctl.conf
	echo "# rpi tweaks" >> sdcard/etc/sysctl.conf
	echo "vm.swappiness = 1" >> sdcard/etc/sysctl.conf
	echo "vm.min_free_kbytes = 8192" >> sdcard/etc/sysctl.conf
	echo "vm.vfs_cache_pressure = 50" >> sdcard/etc/sysctl.conf
	echo "vm.dirty_writeback_centisecs = 1500" >> sdcard/etc/sysctl.conf
	echo "vm.dirty_ratio = 20" >> sdcard/etc/sysctl.conf
	echo "vm.dirty_background_ratio = 10" >> sdcard/etc/sysctl.conf

	# https://haydenjames.io/raspberry-pi-performance-add-zram-kernel-parameters/
	#vm.vfs_cache_pressure=500
	#vm.swappiness=100
	#vm.dirty_background_ratio=1
	#vm.dirty_ratio=50
echo -e "${INFO}#######################################################################################################################${NO}"
echo -e "${OOPS}###########  End pi Stuff  ############################################################################################${NO}"
echo -e "${DONE}#######################################################################################################################${NO}"
fi

echo -e "${DONE}\n  sync'n debs ${NO}"
cp -nv sdcard/var/cache/apt/archives/*.deb debs/${ARCH}/${Devuan_ReLease}

echo -e "${DONE}\n  Cleaning out archives   ${NO}"
du -h sdcard/var/cache/apt/archives | tail -1
rm -rf sdcard/var/cache/apt/archives/*
rm -v sdcard/*.deb
install -v -m 0755 -D Devuan-pi-imager.sh sdcard/root/Devuan-imager/Devuan-pi-imager.sh
install -v -m 0644 bashrc.root sdcard/root/Devuan-imager
install -v -m 0644 growpart sdcard/root/Devuan-imager
install -v -m 0644 growpart.init sdcard/root/Devuan-imager
install -v -m 0755 growpart sdcard/usr/bin/growpart
install -v -m 0755 growpart.init sdcard/etc/init.d/growpart
install -v -m 0644 READme sdcard/root/Devuan-imager
chroot sdcard update-rc.d growpart defaults 2
cp -aR .git sdcard/root/Devuan-imager/.git
ls .git sdcard/root/Devuan-imager/.git

sync
echo -e "${DONE}\n  Total sdcard used ${NO}"; echo
#du -h sdcard | tail -1
du -ch sdcard | grep total

echo -e "${DONE}\n  Unmounting mount points ${NO}"
umount -v sdcard/proc
umount -v sdcard/sys
umount -v sdcard/dev/pts
umount -v sdcard/boot
umount -v sdcard
rm -rvf sdcard

echo -e "${DONE}\n  Sanity check on ${rootpart} ${NO}"
file -s ${rootpart}

echo -e "${DONE}\n  Listing superblocks of ${rootpart} ${NO}"
dumpe2fs ${rootpart} | grep -i superblock

echo -e "${DONE}\n  Forced file system check of ${rootpart} ${NO}"
e2fsck -f ${rootpart}

echo -e "${DONE}\n  Resizing filesystem to the minimum size of ${rootpart} ${NO}"
echo -e "${DONE}    This can take awhile... ${NO}"
resize2fs -pM ${rootpart}

echo
fsck.fat -traw ${bootpart}
echo


echo -e "${DONE}\n  Create  ${Image_Name}.gz Image ${NO}"
dd if=Image conv=sync,noerror bs=1M | gzip -c > ${Image_Name}.gz

echo -e "${DONE}\n  Create  sha512sum ${NO}"
sha512sum --tag ${Image_Name}.gz > ${Image_Name}.gz.sha512sum
cat ${Image_Name}.gz.sha512sum

echo -e "${DONE}\n  losetup -d ${loop_device} ${NO}"
losetup -d ${loop_device}

echo $start_time
echo $(date)
echo " "

echo -e "${DONE}\n\n  Okie Dokie, We Done\n ${NO}"
echo -e "${DONE}  Y'all Have A Great Day now   ${NO}"
echo
