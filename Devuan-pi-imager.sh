#!/bin/bash
# A simple script to make your own Devuan pi4 arm64 image
#
# BeerWare By ShorTie	<shortie8@verizon.net> 

# Turn off path caching.
set +h

DATE=$(date +"%Y%m%d")
#my_DESKTOP=yes

if [ "$1" = "armhf" ]; then
    echo "32 bit"
    ARCH=armhf
    release=beowulf
    Image_Name=Devuan-pi-${release}.${DATE}.img
    echo ${Image_Name}
else
    echo "64 bit"
    ARCH=arm64
    release=beowulf
    #release=chimaera
    Image_Name=Devuan-p4-64-${release}.${DATE}.img
    echo ${Image_Name}
fi

# From  http://deb.devuan.org/devuan/pool/main/d/debootstrap
DebootStrap=debootstrap_1.0.123+devuan2.tar.gz

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
    echo -e "${STEP}  Cleaning up my mess .. ${OOPS}:(~ ${NO}"
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

echo -e "${STEP}  Setting Trap ${NO}"
trap "echo; echo \"Unmounting /proc\"; fail" SIGINT SIGTERM


# Check to see if Devuan-pi-imager.sh is being run as root
start_time=$(date)
echo -e "${STEP}\n  Checking for root .. ${NO}"
if [ `id -u` != 0 ]; then
    echo "nop"
    echo -e "Ooops, Devuan-pi-imager.sh needs to be run as root !!\n"
    echo " Try 'sudo sh, ./Devuan-pi-imager.sh' as a user"
    exit
else
    echo -e "${INFO}  Yuppers,${BOUL} root it tis ..${DONE} :)~${NO}"
fi

if [ ! -e debs/Dependencies-ok ]; then
  echo -e "${STEP}\n  Installing dependencies ..  ${NO}"
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
  echo -e "${DONE}\n\n  Creating a zero-filled file ${NO}"
  if [ "$my_DESKTOP" = "yes" ]; then
    dd if=/dev/zero of=Image  bs=1M  count=3866 iflag=fullblock
  else
    dd if=/dev/zero of=Image  bs=1M  count=1840 iflag=fullblock
  fi
fi

# Create partitions
echo -e "${STEP}\n\n  Creating partitions ${NO}"
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

echo -e "${STEP}\n  Setting up drive mapper ${NO}"
loop_device=$(losetup --show -f Image) || fail

echo -e "${STEP}    Loop device is ${DONE} $loop_device ${NO}"
echo -e "${STEP}  Partprobing $loop_device ${NO}"
partprobe ${loop_device}
bootpart=${loop_device}p1
rootpart=${loop_device}p2
echo -e "${STEP}    Boot partition is ${DONE} $bootpart ${NO}"
echo -e "${STEP}    Root partition is ${DONE} $rootpart ${NO}"

# Format partitions
echo -e "${STEP}\n  Formating partitions ${NO}"
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

echo -e "${STEP}\n  Setting up for debootstrap ${NO}"
mkdir -v sdcard
mount -v -t ext4 -o sync $rootpart sdcard

echo -e "${STEP}\n  Copying debs ${NO}"
if [ ! -d debs/${ARCH}/${release} ]; then
  echo -e "${STEP}\n  Making debs directory ${NO}"
  mkdir -vp debs/${ARCH}/${release}
fi
du -sh debs/${ARCH}/${release}
mkdir -vp sdcard/var/cache/apt/archives
cp debs/${ARCH}/${release}/*.deb sdcard/var/cache/apt/archives

if [ ! -d debs/debootstrap ]; then
    wget -nc -P debs https://pkgmaster.devuan.org/devuan/pool/main/d/debootstrap/${DebootStrap}
    mkdir -vp debs/debootstrap
    tar xf debs/${DebootStrap} -C debs/debootstrap
fi

# These are added to debootstrap now so no setup Dialog boxes are done, configuration done later.
include="--include=kbd,locales,keyboard-configuration,console-setup,dphys-swapfile,devuan-keyring"
exclude=
#exclude="--exclude="

echo -e "${STEP}\n  debootstrap's line is ${NO}"
debootstrapline=" --arch ${ARCH} ${include} ${exclude} ${release} sdcard"
echo ${debootstrapline}; echo
DEBOOTSTRAP_DIR=debs/debootstrap/source debs/debootstrap/source/debootstrap --arch ${ARCH} ${include} ${exclude} ${release} sdcard || fail

echo -e "${STEP}\n  Mount new chroot system\n ${NO}"
mount -v -t vfat -o sync $bootpart sdcard/boot
mount -v proc sdcard/proc -t proc
mount -v sysfs sdcard/sys -t sysfs
mount -v --bind /dev/pts sdcard/dev/pts

#mount -v --rbind /dev sdcard/dev
#mount -v --rbind /sys sdcard/sys
#mount -v -t proc /proc sdcard/proc



# Adjust a few things
echo -e "${INFO}\n\n  Copy, adjust and reconfigure ${NO}"

echo -e "${STEP}\n  Adjusting /etc/apt/sources.list from/too... ${NO}"
cat sdcard/etc/apt/sources.list
  sed -i sdcard/etc/apt/sources.list -e "s/main/main contrib non-free/"
#  echo "deb http://deb.devuan.org/merged ${release} main contrib non-free" >> sdcard/etc/apt/sources.list
#echo "deb http://deb.devuan.org/merged ${release} main contrib non-free" > sdcard/etc/apt/sources.list
cat sdcard/etc/apt/sources.list

echo -e "${STEP}\n  Install ${DONE}locales-all\n ${NO}"
chroot sdcard apt-get install -y locales-all || fail

echo -en "${STEP}\n  Adjusting locales too...  ${NO}"
if [ "$locales" == "" ]; then 
    cp -v /etc/locale.gen sdcard/etc/locale.gen
else
    sed -i "s/^# \($locales .*\)/\1/" sdcard/etc/locale.gen
fi
grep -v '^#' sdcard/etc/locale.gen

echo -en "${STEP}\n  Adjusting default local too...  ${NO}"
if [ "$default_locale" == "" ]; then 
    default_locale=$(fgrep "=" /etc/default/locale | cut -f 2 -d '=')
fi
echo $default_locale

echo -e "${STEP}\n  local-gen  LANG=${default_locale} ${NO}"
chroot sdcard locale-gen LANG="$default_locale"

echo -e "${STEP}\n  dpkg-reconfigure -f noninteractive locales ${NO}"
chroot sdcard dpkg-reconfigure -f noninteractive locales

echo -en "${STEP}  Changing timezone too...   America/New_York  ${NO}"
echo "America/New_York" > sdcard/etc/timezone
rm -v sdcard/etc/localtime
cat sdcard/etc/timezone

echo -e "${STEP}\n  dpkg-reconfigure -f noninteractive tzdata ${NO}"
chroot sdcard dpkg-reconfigure -f noninteractive tzdata

echo -e "${STEP}\n  Setting up keyboard ${NO}"
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

echo -e "${STEP}\n  dpkg-reconfigure -f noninteractive keyboard-configuration ${NO}"
chroot sdcard dpkg-reconfigure -f noninteractive keyboard-configuration

echo -e "${STEP}\n  Install ${DONE}consolekit\n ${NO}"
#chroot sdcard apt-get install -y consolekit logind || fail



echo -e "${STEP}\n  dpkg-reconfigure -f noninteractive console-setup ${NO}"
chroot sdcard dpkg-reconfigure -f noninteractive console-setup


echo -e "${STEP}\n  Setting up networking ${NO}"
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

echo -e "${STEP}\n  hostname ${NO}"; cat sdcard/etc/hostname
echo -e "${STEP}\n  resolv.conf ${NO}"; cat sdcard/etc/resolv.conf
echo -e "${STEP}\n  hosts ${NO}"; cat sdcard/etc/hosts


echo -e "${STEP}  Creating fstab ${NO}"
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

echo -e "${STEP}\n  Setting dphys-swapfile size to 100meg ${NO}"
echo "CONF_SWAPSIZE=100" > sdcard/etc/dphys-swapfile

echo -e "${DONE}\n  Done Coping, adjusting and reconfiguring ${NO}"
#	###########  Done with basic system  ################


#	###########  Install raspberrypi.gpg.key  ################

echo -e "${DONE}\n    Install raspberrypi.gpg.key   ${NO}"
echo -e "${STEP}  apt install -y gnupg wget ${NO}"
chroot sdcard apt-get install -y gnupg wget

echo -e "${STEP}\n  Add archive.raspberrypi gpg.key ${NO}"

if [ ! -d debs/raspberrypi.gpg.key ]; then
    wget -nc -P debs http://archive.raspberrypi.org/debian/raspberrypi.gpg.key
fi
cp -v debs/raspberrypi.gpg.key sdcard
chroot sdcard apt-key add raspberrypi.gpg.key
rm -v sdcard/raspberrypi.gpg.key

echo -e "${STEP}\n  Creating raspi.list ${NO}"
tee sdcard/etc/apt/sources.list.d/raspi.list <<EOF
deb http://archive.raspberrypi.org/debian/ buster main
# Uncomment line below then 'apt-get update' to enable 'apt-get source'
#deb-src http://archive.raspberrypi.org/debian/ buster main
EOF

echo -e "${STEP}     apt update  ${NO}"
chroot sdcard apt update

echo -e "${STEP}     apt upgrade  ${NO}"
chroot sdcard apt-get upgrade -y

echo -e "${STEP}\n\n  Install some firmware ${NO}"
chroot sdcard apt-get install firmware-atheros firmware-brcm80211 \
	firmware-libertas firmware-linux-free firmware-misc-nonfree firmware-realtek


#	###########  Install kernel  ######################################################

echo -e "${DONE}\n    Install kernel   ${NO}"
chroot sdcard apt-get -y install raspberrypi-bootloader raspberrypi-kernel

KERNEL=$(ls sdcard/lib/modules | grep v8+ | cut -d"-" -f1 | awk '{print$1}')

echo -e "${STEP}\n    Crud Removal  ${DONE} ${KERNEL}  ${NO}"
if [ "${ARCH}" == "arm64" ]; then
    rm -v sdcard/boot/{bootcode.bin,fixup.dat,fixup_x.dat,fixup_cd.dat,fixup_db.dat}
    rm -v sdcard/boot/{start.elf,start_x.elf,start_cd.elf,start_db.elf}
    rm -v sdcard/boot/{kernel.img,kernel7.img,kernel7l.img}
    rm -v sdcard/boot/{bcm2708-rpi-cm.dtb,bcm2708-rpi-b.dtb,bcm2708-rpi-b-rev1.dtb,bcm2708-rpi-b-plus.dtb}
    rm -v sdcard/boot/{bcm2708-rpi-zero.dtb,bcm2708-rpi-zero-w.dtb,bcm2709-rpi-2-b.dtb}
    rm -v sdcard/boot/{bcm2710-rpi-2-b.dtb,bcm2710-rpi-cm3.dtb,bcm2710-rpi-3-b.dtb,bcm2710-rpi-3-b-plus.dtb}
    ls sdcard/lib/modules
    rm -rf sdcard/lib/modules/{${KERNEL}+,${KERNEL}-v7+,${KERNEL}-v7l+}
    ls sdcard/lib/modules
else
 #   rm -v sdcard/boot/{fixup4.dat,fixup4x.dat,fixup4cd.dat,fixup4db.dat}
 #   rm -v sdcard/boot/{start4.elf,start4x.elf,start4cd.elf,start4db.elf}
    rm -v sdcard/boot/kernel8.img
 #   rm -v sdcard/boot/bcm2711-rpi-4-b.dtb
    ls sdcard/lib/modules
    rm -rf sdcard/lib/modules/${KERNEL}-v8+
    ls sdcard/lib/modules
fi

echo -e "${STEP}\n  Creating cmdline.txt ${NO}"
tee sdcard/boot/cmdline.txt <<EOF
console=serial0,115200 console=tty1 root=PARTUUID=${P2_UUID} rootfstype=ext4 elevator=deadline fsck.repair=yes rootwait
EOF

echo -e "${STEP}\n  Copy config.txt ${NO}"
if [ ! -f debs/config.armhf ]; then
    echo; echo; echo "downloading"; echo
    wget https://raw.githubusercontent.com/RPi-Distro/pi-gen/master/stage1/00-boot-files/files/config.txt
    cp -v config.txt debs/config.armhf
    sed '4 i dtparam=random=on' config.txt > config.txt.new
    sed '4 i arm_64bit=1' config.txt.new > config.txt.new.1
    sed '/Some settings/G' config.txt.new.1 > debs/config.arm64
    rm -v config.txt config.txt.new config.txt.new.1
fi
cp -v debs/config.${ARCH} sdcard/boot/config.txt

echo -e "${STEP}\n  Adding wifi firmware ${NO}"
if [ ! -f debs/brcmfmac.tar.xz ]; then
    echo; echo; echo "downloading"; echo
    mkdir -vp sdcard/lib/firmware/brcm
    wget -nc -P sdcard/lib/firmware/brcm https://github.com/RPi-Distro/firmware-nonfree/raw/master/brcm/brcmfmac43430-sdio.bin
    wget -nc -P sdcard/lib/firmware/brcm https://raw.githubusercontent.com/RPi-Distro/firmware-nonfree/master/brcm/brcmfmac43430-sdio.txt
    wget -nc -P sdcard/lib/firmware/brcm https://github.com/RPi-Distro/firmware-nonfree/raw/master/brcm/brcmfmac43455-sdio.bin
    wget -nc -P sdcard/lib/firmware/brcm https://github.com/RPi-Distro/firmware-nonfree/raw/master/brcm/brcmfmac43455-sdio.clm_blob
    wget -nc -P sdcard/lib/firmware/brcm https://raw.githubusercontent.com/RPi-Distro/firmware-nonfree/master/brcm/brcmfmac43455-sdio.txt
    tar -cJf debs/brcmfmac.tar.xz sdcard/lib/firmware/brcm/*
fi
tar xvf debs/brcmfmac.tar.xz

echo -e "${STEP}\n  Adding Raspberry Pi tweaks to sysctl.conf ${NO}"
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


echo -e "${STEP}\n  apt install -y libraspberrypi-bin ${NO}"
chroot sdcard apt-get install -y libraspberrypi-bin

echo -e "${STEP}\n  apt install -y libraspberrypi-dev ${NO}"
chroot sdcard apt-get install -y libraspberrypi-dev

echo -e "${STEP}\n  apt install -y libraspberrypi-doc ${NO}"
chroot sdcard apt-get install -y libraspberrypi-doc


#	###########  ssh, root passwd && extra's  ################

echo -e "${STEP}\n  Install ${DONE}ssh\n ${NO}"
chroot sdcard apt-get install -y ssh --no-install-recommends || fail

echo -e "${STEP}\n  Setting up the root password... ${NO} $root_password "
echo root:$root_password | chroot sdcard chpasswd

echo -e "${STEP}\n  Allowing root to log into $release with password...  ${NO}"
sed -i 's/.*PermitRootLogin prohibit-password/PermitRootLogin yes/' sdcard/etc/ssh/sshd_config
grep 'PermitRootLogin' sdcard/etc/ssh/sshd_config
cp -v bashrc.root sdcard/root/.bashrc


EXTRAS="dhcpcd5 git ntp mlocate parted psmisc wpasupplicant"
echo -e "${STEP}\n  Install ${DONE}${EXTRAS}\n ${NO}"
chroot sdcard apt-get install -y ${EXTRAS} || fail

#	###########  Set up User's  ################

echo -e "${DONE}\n  Setup user pi  ${NO}"
echo -e "${STEP}\n    apt install -y sudo ${NO}"
chroot sdcard apt-get install -y sudo
echo
chroot sdcard adduser pi --gecos "${hostname}" --disabled-password
echo pi:toor | chroot sdcard chpasswd

chroot sdcard groupadd spi
chroot sdcard groupadd i2c
chroot sdcard groupadd gpio

chroot sdcard adduser pi sudo
chroot sdcard adduser pi audio
chroot sdcard adduser pi dialout
chroot sdcard adduser pi video
chroot sdcard adduser pi disk
chroot sdcard adduser pi spi
chroot sdcard adduser pi i2c
chroot sdcard adduser pi gpio
chroot sdcard adduser pi netdev

cp -v bashrc.root sdcard/home/pi/.bashrc

#	###########  Install Desktop  ################

if [ "$DESKTOP" = "yes" ]; then
    echo -e "${DONE}\n  Install Desktop ${NO}"
    chroot sdcard apt-get install -y gufw xterm lxappearance lxrandr lxpolkit openbox obconf obmenu openbox-menu menu tint2 nitrogen featherpad vlc audacious \
		ceni alsa-utils alsa-tools-gui slim pcmanfm chromium lxqt-sudo orage sylpheed sylpheed-i18n sylpheed-plugins hexchat zenity xautolock
    chroot sdcard apt-get install -y xserver-xorg-core xserver-xorg-input-libinput xserver-xorg-input-kbd xserver-xorg-input-mouse xserver-xorg-input-evdev \
		cinnabar-icon-theme desktop-base base-files
    install -v -m 0644 -D menu.xml sdcard/home/devuan/.config/openbox/menu.xml
    install -v -m 0644 rc.xml sdcard/home/devuan/.config/openbox/rc.xml
fi


if [ "$my_DESKTOP" = "yes" ]; then
    echo -e "${DONE}\n  Install my_Desktop ${NO}"

    echo -e "${DONE}\n    gstreamer1.0-x ${NO}"
    chroot sdcard apt-get install -y gstreamer1.0-x \
		gstreamer1.0-omx gstreamer1.0-plugins-base \
		gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
		gstreamer1.0-alsa gstreamer1.0-libav qpdfview gtk2-engines

    echo -e "${DONE}\n    alsa-utils ${NO}"
    chroot sdcard apt-get install -y alsa-utils \
		desktop-base raspberrypi-artwork policykit-1 gvfs rfkill

    echo -e "${DONE}\n    xinit xserver-xorg ${NO}"
    chroot sdcard apt-get install -y xinit xserver-xorg \
		xserver-xorg-video-fbdev xserver-xorg-video-fbturbo

    if [ "${ARCH}" == "armhf" ]; then
        echo -e "${DONE}\n    lxde  ${NO}"
        chroot sdcard apt-get install -y lxde
    else
        echo -e "${DONE}\n    lxde   --no-install-recommends ${NO}"
        chroot sdcard apt-get install -y lxde  --no-install-recommends
    fi

    echo -e "${DONE}\n    mousepad lxtask menu-xdg ${NO}"
    chroot sdcard apt-get install -y mousepad lxtask menu-xdg \
		zenity xdg-utils gvfs-backends gvfs-fuse lightdm \
		gnome-themes-standard gnome-icon-theme

    echo -e "${DONE}\n    piclone pi-greeter rpi-imager ${NO}"
    chroot sdcard apt-get install -y piclone pi-greeter rpi-imager

    echo -e "${STEP}\n    switching lightdm.conf's autologin-user to ${DONE} pi  ${NO}"
    grep autologin-user= sdcard/etc/lightdm/lightdm.conf
    #sed sdcard/etc/lightdm/lightdm.conf -i -e "s/autologin-user=pi/autologin-user=devuan/"
    #grep autologin-user sdcard/etc/lightdm/lightdm.conf
fi

#	########### Final setup		###########

echo -e "${STEP}\n  sync'n debs ${NO}"
cp -nv sdcard/var/cache/apt/archives/*.deb debs/${ARCH}/${release}

echo -e "${STEP}\n  Cleaning out archives   ${NO}"
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
echo -e "${STEP}\n  Total sdcard used ${NO}"; echo
#du -h sdcard | tail -1
du -ch sdcard | grep total

echo -e "${STEP}\n  Unmounting mount points ${NO}"
umount -v sdcard/proc
umount -v sdcard/sys
umount -v sdcard/dev/pts
umount -v sdcard/boot
umount -v sdcard
rm -rvf sdcard

echo -e "${STEP}\n  Sanity check on ${rootpart} ${NO}"
file -s ${rootpart}

echo -e "${STEP}\n  Listing superblocks of ${rootpart} ${NO}"
dumpe2fs ${rootpart} | grep -i superblock

echo -e "${STEP}\n  Forced file system check of ${rootpart} ${NO}"
e2fsck -f ${rootpart}

echo -e "${STEP}\n  Resizing filesystem to the minimum size of ${rootpart} ${NO}"
echo -e "${STEP}    This can take awhile... ${NO}"
resize2fs -pM ${rootpart}

echo
fsck.fat -traw ${bootpart}
echo


echo -e "${STEP}\n  Create  ${Image_Name}.gz Image ${NO}"
dd if=Image conv=sync,noerror bs=1M | gzip -c > ${Image_Name}.gz

echo -e "${STEP}\n  Create  sha512sum ${NO}"
sha512sum --tag ${Image_Name}.gz > ${Image_Name}.gz.sha512sum
cat ${Image_Name}.gz.sha512sum

echo -e "${STEP}\n  losetup -d ${loop_device} ${NO}"
losetup -d ${loop_device}

echo $start_time
echo $(date)
echo " "

echo -e "${STEP}\n\n  Okie Dokie, We Done\n ${NO}"
echo -e "${DONE}  Y'all Have A Great Day now   ${NO}"
echo
