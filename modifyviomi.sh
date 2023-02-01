#!/bin/bash
# Author: Dennis Giese [dgiese@dontvacuum.me]
# Copyright 2017 by Dennis Giese

BASE_DIR="."
FLAG_DIR="."
IMG_DIR="./CRL200S-OTA/target_sys/squashfs-root"
FEATURES_DIR="./features"

if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo "WARNING: Unsupported OS, image generation might fail or create bad images. Do not proceed if you are not sure what you are doing"
    echo "press CTRL+C to abort"
    sleep 5
fi

command -v unzip >/dev/null 2>&1 || { echo "ERROR: unzip command not found, aborting"; exit 1; }
command -v unsquashfs >/dev/null 2>&1 || { echo "ERROR: unzip command not found, aborting"; exit 1; }
command -v mksquashfs >/dev/null 2>&1 || { echo "ERROR: unzip command not found, aborting"; exit 1; }
command -v install >/dev/null 2>&1 || { echo "ERROR: install command not found, aborting"; exit 1; }
command -v md5sum >/dev/null 2>&1 || { echo "ERROR: md5sum command not found, aborting"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "ERROR: git command not found, aborting"; exit 1; }

if [ ! -f $BASE_DIR/upd_viomi.bin ]; then
    echo "ERROR: File upd_viomi.bin not found! Decryption and unpacking was apparently unsuccessful."
    exit 1
fi

if [ ! -f $BASE_DIR/authorized_keys ]; then
    echo "ERROR: authorized_keys not found. Please create your authorized_keys file first (it contains the public portion of your ssh key, likely starting with ssh-rsa)."
    exit 1
fi

if [ ! -f $FLAG_DIR/devicetype ]; then
    echo "ERROR: devicetype definition not found, aborting"
    echo "you likely want to set the flags manually or by running _buildflags.sh from dustbuilder"
    exit 1
fi

if [ ! -f $FLAG_DIR/jobid ]; then
    echo "ERROR: jobid not found, aborting"
    echo "you likely want to set the flags manually or by running _buildflags.sh from dustbuilder"
    exit 1
fi

if [ ! -d $FEATURES_DIR ]; then
    echo "ERROR: Features directory not found. You might want to clone the repo from https://github.com/dgiese/dustbuilder-features to ${FEATURES_DIR}, aborting"
    exit 1
fi

DEVICETYPE=$(cat "$FLAG_DIR/devicetype")
FRIENDLYDEVICETYPE=$(cat "$FLAG_DIR/devicetype")

mkdir -p $BASE_DIR/output

tar -xzvf $BASE_DIR/upd_viomi.bin -C $BASE_DIR/
tar -xzvf $BASE_DIR/CRL200S-OTA/target_sys.tar.gz -C $BASE_DIR/CRL200S-OTA/
unsquashfs -d $IMG_DIR $BASE_DIR/CRL200S-OTA/target_sys/rootfs.img
rm $BASE_DIR/CRL200S-OTA/target_sys/rootfs.img
mkdir -p $IMG_DIR/etc/dropbear
chown root:root $IMG_DIR/etc/dropbear
cat $BASE_DIR/dropbear_rsa_host_key > $IMG_DIR/etc/dropbear/dropbear_rsa_host_key
cat $BASE_DIR/dropbear_dss_host_key > $IMG_DIR/etc/dropbear/dropbear_dss_host_key
cat $BASE_DIR/dropbear_ecdsa_host_key > $IMG_DIR/etc/dropbear/dropbear_ecdsa_host_key
cat $BASE_DIR/dropbear_ed25519_host_key > $IMG_DIR/etc/dropbear/dropbear_ed25519_host_key


echo "integrate SSH authorized_keys"
mkdir $IMG_DIR/root/.ssh
chmod 700 $IMG_DIR/root/.ssh
cat $BASE_DIR/authorized_keys > $IMG_DIR/root/.ssh/authorized_keys
cat $BASE_DIR/authorized_keys > $IMG_DIR/etc/dropbear/authorized_keys
chmod 600 $IMG_DIR/root/.ssh/authorized_keys
chmod 600 $IMG_DIR/etc/dropbear/authorized_keys
chown root:root $IMG_DIR/root -R

install -m 0755 $FEATURES_DIR/viomi_tools/root-dir/usr/sbin/dropbear $IMG_DIR/usr/sbin/dropbear
install -m 0755 $FEATURES_DIR/viomi_tools/root-dir/usr/sbin/dropbearmulti $IMG_DIR/usr/sbin/dropbearmulti

ln -s /usr/sbin/dropbear $IMG_DIR/usr/bin/dbclient
ln -s /usr/sbin/dropbear $IMG_DIR/usr/bin/ssh
ln -s /usr/sbin/dropbear $IMG_DIR/usr/bin/scp
ln -s /usr/sbin/dropbear $IMG_DIR/usr/bin/dropbearkey

install -m 0755 $FEATURES_DIR/dropbear_viomi/init.d/dropbear $IMG_DIR/etc/init.d/dropbear
install -m 0755 $FEATURES_DIR/dropbear_viomi/config/dropbear $IMG_DIR/etc/config/dropbear

ln -s ../init.d/dropbear $IMG_DIR/etc/rc.d/S50dropbear
ln -s ../init.d/dropbear $IMG_DIR/etc/rc.d/K50dropbear

# disable disabling of adbd
sed -i -E 's/echo 0/echo 1/g' $IMG_DIR/usr/sbin/RobotApp

echo "backdooring"
sed -i -E 's/\/bin\/login/\/bin\/ash/g' $IMG_DIR/etc/inittab
sed -i -E 's/\/bin\/login/\/bin\/ash/g' $IMG_DIR/bin/adb_shell

if [ -f $FLAG_DIR/tools ]; then
    echo "installing tools"
    cp -r $FEATURES_DIR/viomi_tools/root-dir/* $IMG_DIR/
fi

if [ -f $FLAG_DIR/hostname ]; then
echo "patching Hostname"
	cat $FLAG_DIR/hostname > $IMG_DIR/etc/hostname
fi

if [ -f $FLAG_DIR/timezone ]; then
echo "patching Timezone"
	cat $FLAG_DIR/timezone > $IMG_DIR/etc/timezone
fi


sed -i "s/^exit 0//" $IMG_DIR/etc/rc.local
echo "if [[ -f /mnt/UDISK/_root.sh ]]; then" >> $IMG_DIR/etc/rc.local
echo "    /mnt/UDISK/_root.sh &" >> $IMG_DIR/etc/rc.local
echo "fi" >> $IMG_DIR/etc/rc.local
echo "exit 0" >> $IMG_DIR/etc/rc.local
mkdir $IMG_DIR/misc
install -m 0755 $FEATURES_DIR/fwinstaller_viomi/_root.sh.tpl $IMG_DIR/misc/_root.sh.tpl
install -m 0644 $FEATURES_DIR/fwinstaller_viomi/how_to_modify.txt $IMG_DIR/misc/how_to_modify.txt

# For robots such as the conga 3790, we need a different wifi driver module
mkdir -p $IMG_DIR/opt/8821cs/
install -m 0755 $FEATURES_DIR/fwinstaller_viomi/8821cs_patched.ko $IMG_DIR/opt/8821cs/8821cs_patched.ko
install -m 0755 $FEATURES_DIR/fwinstaller_viomi/enable_8821cs.sh $IMG_DIR/opt/8821cs/enable_8821cs.sh
install -m 0755 $FEATURES_DIR/fwinstaller_viomi/disable_8821cs.sh $IMG_DIR/opt/8821cs/disable_8821cs.sh

#install -m 0755 $FEATURES_DIR/fwinstaller_viomi/net-rtl8821cs $IMG_DIR/etc/modules.d/net-rtl8821cs
#install -m 0755 $FEATURES_DIR/fwinstaller_viomi/rmwm.sh $IMG_DIR/bin/rmwm.sh
#install -m 0755 $FEATURES_DIR/fwinstaller_viomi/inswm.sh $IMG_DIR/bin/inswm.sh
#install -m 0755 $FEATURES_DIR/fwinstaller_viomi/reboot $IMG_DIR/sbin/reboot

#sed -i -E 's/rmmod 8189es/\/bin\/rmwm.sh/g' $IMG_DIR/usr/sbin/log*
#sed -i -E 's/insmod 8189es/\/bin\/inswm.sh/g' $IMG_DIR/usr/sbin/log*
#sed -i -E 's/rmmod 8189es/\/bin\/rmwm.sh/g' $IMG_DIR/usr/sbin/RobotApp*
#sed -i -E 's/insmod 8189es/\/bin\/inswm.sh/g' $IMG_DIR/usr/sbin/RobotApp*
#sed -i -E 's/rmmod 8189es/\/bin\/rmwm.sh/g' $IMG_DIR/usr/sbin/wifi*
#sed -i -E 's/insmod 8189es/\/bin\/inswm.sh/g' $IMG_DIR/usr/sbin/wifi*
#sed -i -E 's/rmmod 8189es/\/bin\/rmwm.sh/g' $IMG_DIR/usr/bin/mac*
#sed -i -E 's/insmod 8189es/\/bin\/inswm.sh/g' $IMG_DIR/usr/bin/mac*
#sed -i -E 's/rmmod 8189es/\/bin\/rmwm.sh/g' $IMG_DIR/bin/wifi*
#sed -i -E 's/insmod 8189es/\/bin\/inswm.sh/g' $IMG_DIR/bin/wifi*
#sed -i -E 's/insmod \/lib\/modules\/3.4.39\/8189es/\/bin\/inswm.sh \/lib\/modules\/3.4.39/g' $IMG_DIR/bin/wifi*


echo "built with dustbuilder (https://builder.dontvacuum.me)" >> $IMG_DIR/etc/banner
date -u +"%Y-%m-%dT%H:%M:%SZ"  >> $IMG_DIR/etc/banner
echo "" >> $IMG_DIR/etc/banner

if [ -f $FLAG_DIR/patch_dns ]; then
	# Set system timezone to UTC
	sed -i "s/option[[:space:]]\+timezone[[:space:]]\+Asia\/Shanghai/option timezone Etc\/UTC/g" $IMG_DIR/etc/config/system
	sed -i "s/option[[:space:]]\+timezone[[:space:]]\+CST-8/option timezone UTC/g" $IMG_DIR/etc/config/system

	# Disable firmware ntp client
	sed -i "s/option[[:space:]]\+enable[[:space:]]\+1/option enable 0/g" $IMG_DIR/etc/config/system

	# Set language to EN
	sed -i "s/languageType=1/languageType=2/g" $IMG_DIR/etc/sysconf/sysConfig.ini

	# Patch miio_client and add hostsfile redirect
	sed -i -E 's/110.43.0.83/127.000.0.1/g' $IMG_DIR/usr/bin/miio_client
	sed -i -E 's/110.43.0.85/127.000.0.1/g' $IMG_DIR/usr/bin/miio_client
	rm $IMG_DIR/etc/hosts
	cat $FEATURES_DIR/valetudo/deployment/etc/hosts-local > $IMG_DIR/etc/hosts
fi


echo "finished patching, repacking"

mksquashfs $IMG_DIR/ $BASE_DIR/CRL200S-OTA/target_sys/rootfs_tmp.img -noappend -root-owned -comp xz -b 256k -p '/dev d 755 0 0' -p '/dev/console c 600 0 0 5 1'
rm -rf $IMG_DIR
dd if=$BASE_DIR/CRL200S-OTA/target_sys/rootfs_tmp.img of=$BASE_DIR/CRL200S-OTA/target_sys/rootfs.img bs=128k conv=sync
rm $BASE_DIR/CRL200S-OTA/target_sys/rootfs_tmp.img
md5sum "$BASE_DIR/CRL200S-OTA/target_sys/rootfs.img" | awk '{ print $1 }' > $BASE_DIR/CRL200S-OTA/target_sys/rootfs.img.md5

echo "check image file size"
maximumsize=26000000
minimumsize=20000000
actualsize=$(wc -c < "$BASE_DIR/CRL200S-OTA/target_sys/rootfs.img")
if [ "$actualsize" -ge "$maximumsize" ]; then
	echo "(!!!) rootfs.img looks to big. The size might exceed the available space on the flash."
	exit 1
fi

if [ "$actualsize" -le "$minimumsize" ]; then
	echo "(!!!) rootfs.img looks to small. Maybe something went wrong with the image generation."
	exit 1
fi

if [ -f $FLAG_DIR/livesuit ]; then
	echo "build Livesuit image"
	tar -xzvf $BASE_DIR/CRL200S-OTA/ramdisk_sys.tar.gz
	cp $BASE_DIR/CRL200S-OTA/target_sys/rootfs.img $BASE_DIR/livesuitimage/rootfs.fex
	cp $BASE_DIR/CRL200S-OTA/target_sys/boot.img $BASE_DIR/livesuitimage/boot.fex
	if [ -f $FLAG_DIR/resetsettings ]; then
		echo "create empty partitions"
		cp $BASE_DIR/livesuitimage/sys_partition_reset.fex $BASE_DIR/livesuitimage/sys_partition.fex
	fi
	cp $BASE_DIR/ramdisk_sys/boot_initramfs.img $BASE_DIR/livesuitimage/recovery.fex
	$FEATURES_DIR/../tools/pack-bintools/FileAddSum $BASE_DIR/livesuitimage/empty.fex $BASE_DIR/livesuitimage/Vempty.fex
	$FEATURES_DIR/../tools/pack-bintools/FileAddSum $BASE_DIR/livesuitimage/boot.fex $BASE_DIR/livesuitimage/Vboot.fex
	$FEATURES_DIR/../tools/pack-bintools/FileAddSum $BASE_DIR/livesuitimage/rootfs.fex $BASE_DIR/livesuitimage/Vrootfs.fex
	$FEATURES_DIR/../tools/pack-bintools/FileAddSum $BASE_DIR/livesuitimage/recovery.fex $BASE_DIR/livesuitimage/Vrecovery.fex
	$FEATURES_DIR/../tools/pack-bintools/FileAddSum $BASE_DIR/livesuitimage/boot-resource.fex $BASE_DIR/livesuitimage/Vboot-resource.fex
	$FEATURES_DIR/../tools/pack-bintools/dragon $BASE_DIR/livesuitimage/image.cfg
	mv $BASE_DIR/livesuitimage/FILELIST $BASE_DIR/output/${DEVICETYPE}_livesuitimage.img
	md5sum $BASE_DIR/output/${DEVICETYPE}_livesuitimage.img > $BASE_DIR/output/md5.txt
	echo "${DEVICETYPE}_livesuitimage.img" > $BASE_DIR/filename.txt
	rm -rf $BASE_DIR/ramdisk_sys/
else
	rm $BASE_DIR/CRL200S-OTA/target_sys.tar.gz
	tar -czvf $BASE_DIR/CRL200S-OTA/target_sys.tar.gz -C $BASE_DIR/CRL200S-OTA/ target_sys
	md5sum $BASE_DIR/CRL200S-OTA/target_sys.tar.gz > $BASE_DIR/CRL200S-OTA/target_sys_md5
	rm -rf $BASE_DIR/CRL200S-OTA/target_sys
	tar -czf $BASE_DIR/output/${DEVICETYPE}_fw.tar.gz CRL200S-OTA
	md5sum $BASE_DIR/output/${DEVICETYPE}_fw.tar.gz > $BASE_DIR/output/md5.txt
	echo "${DEVICETYPE}_fw.tar.gz" > $BASE_DIR/filename.txt
	touch $BASE_DIR/server.txt
fi

if [ -f $FLAG_DIR/diff ]; then
	mkdir $BASE_DIR/original
	tar -xzvf $BASE_DIR/upd_viomi.bin -C $BASE_DIR/original/
	tar -xzvf $BASE_DIR/original/CRL200S-OTA/target_sys.tar.gz -C $BASE_DIR/original/CRL200S-OTA/
	unsquashfs -d $BASE_DIR/original/CRL200S-OTA/target_sys/squashfs-root $BASE_DIR/original/CRL200S-OTA/target_sys/rootfs.img
	rm -rf $BASE_DIR/original/CRL200S-OTA/target_sys/squashfs-root/dev
	rm -rf $BASE_DIR/original/CRL200S-OTA/ramdisk_sys*

	mkdir $BASE_DIR/modified
    mkdir -p $BASE_DIR/modified/CRL200S-OTA/
	tar xvf $BASE_DIR/CRL200S-OTA/target_sys.tar.gz -C $BASE_DIR/modified/CRL200S-OTA/
	unsquashfs -d $BASE_DIR/modified/CRL200S-OTA/target_sys/squashfs-root $BASE_DIR/modified/CRL200S-OTA/target_sys/rootfs.img
	rm -rf $BASE_DIR/modified/CRL200S-OTA/target_sys/squashfs-root/dev

	/usr/bin/git diff --no-index $BASE_DIR/original/ $BASE_DIR/modified/ > $BASE_DIR/output/diff.txt
	rm -rf $BASE_DIR/original
	rm -rf $BASE_DIR/modified
fi

if [ -f $FLAG_DIR/installer ]; then
	mkdir $BASE_DIR/installer_repack
	mv $BASE_DIR/output/${DEVICETYPE}_fw.tar.gz $BASE_DIR/installer_repack
	tar xzvf $BASE_DIR/installer_repack/${DEVICETYPE}_fw.tar.gz -C $BASE_DIR/installer_repack
	tar xzvf $BASE_DIR/installer_repack/CRL200S-OTA/target_sys.tar.gz -C $BASE_DIR/installer_repack
	mv $BASE_DIR/installer_repack/target_sys/ $BASE_DIR/installer_repack/work/
    install -m 0755 $FEATURES_DIR/fwinstaller_viomi/_root.sh.tpl $BASE_DIR/installer_repack/work/_root.sh.tpl
	install -m 0755 $FEATURES_DIR/fwinstaller_viomi/install.sh $BASE_DIR/installer_repack/work/install.sh
	chmod +x $BASE_DIR/installer_repack/work/install.sh

	cd $BASE_DIR/installer_repack/work/
	md5sum *.img > firmware.md5sum
	cd ../..

	tar -czf $BASE_DIR/output/${DEVICETYPE}_fw.tar.gz -C $BASE_DIR/installer_repack/work/ .
	md5sum $BASE_DIR/output/${DEVICETYPE}_fw.tar.gz > $BASE_DIR/output/md5.txt

	rm -rf $BASE_DIR/installer_repack
fi

touch $BASE_DIR/output/done
