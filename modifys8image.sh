#!/bin/bash
# Author: Dennis Giese [dgiese@dontvacuum.me]
# Copyright 2017 by Dennis Giese

BASE_DIR="."
FLAG_DIR="."
IMG_DIR="./squashfs-root"
OPT_DIR="./squashfs-opt"
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

if [ ! -f $BASE_DIR/firmware.zip ]; then
    echo "ERROR: File firmware.zip not found! Decryption and unpacking was apparently unsuccessful."
	echo "please create zip file that contains rootfs.img, boot.img and mcu.bin. Make sure that the files are compatible with your device"
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
FRIENDLYDEVICETYPE=$(sed "s/\[s|t\]/x/g" $FLAG_DIR/devicetype)
version=$(cat "$FLAG_DIR/version")

mkdir -p $BASE_DIR/output


unzip $BASE_DIR/firmware.zip
mv $BASE_DIR/rootfs.img $BASE_DIR/rootfs.img.template
mv $BASE_DIR/opt.img $BASE_DIR/opt.img.template
COMPRESSION=$(unsquashfs -s $BASE_DIR/rootfs.img.template | grep 'Compression ' | sed 's/Compression //')
echo "compression mode:"
echo $COMPRESSION
if [ -z "$COMPRESSION" ]
then
      COMPRESSION="gzip"
fi
echo "unpacking rootfs"
unsquashfs -no -d $IMG_DIR $BASE_DIR/rootfs.img.template
echo "unpacking opt"
unsquashfs -no -d $OPT_DIR $BASE_DIR/opt.img.template

mkdir -p $IMG_DIR/etc/dropbear
chown root:root $IMG_DIR/etc/dropbear
cat $BASE_DIR/dropbear_rsa_host_key > $IMG_DIR/etc/dropbear/dropbear_rsa_host_key
cat $BASE_DIR/dropbear_dss_host_key > $IMG_DIR/etc/dropbear/dropbear_dss_host_key
cat $BASE_DIR/dropbear_ecdsa_host_key > $IMG_DIR/etc/dropbear/dropbear_ecdsa_host_key
cat $BASE_DIR/dropbear_ed25519_host_key > $IMG_DIR/etc/dropbear/dropbear_ed25519_host_key

echo "disable SSH firewall rule"
sed -i -e '/    iptables -I INPUT -j DROP -p tcp --dport 22/s/^/#/g' $OPT_DIR/watchdog/rrwatchdoge.conf
sed -i -E 's/dport 22/dport 29/g' $OPT_DIR/watchdog/WatchDoge
sed -i -E 's/dport 22/dport 29/g' $OPT_DIR/rrlog/rrlogd

echo "reverting rr_login"
#sed -i -E 's/::respawn:\/sbin\/rr_login -d \/dev\/ttyS0 -b 115200 -p vt100/::respawn:\/sbin\/getty -n -l \/sbin\/rr_login 115200 -L ttyS0/g' $IMG_DIR/etc/inittab
sed -i -E 's/::respawn:\/sbin\/rr_login -d \/dev\/ttyS0 -b 115200 -p vt100/::respawn:\/bin\/sh/g' $IMG_DIR/etc/inittab
install -m 0755 ./features/s8/busybox2 $IMG_DIR/bin/busybox2
install -m 0755 ./features/s8/dmsetup $IMG_DIR/bin/dmsetup
chmod +x $IMG_DIR/bin/busybox2
cp ./features/s8/rr_login $IMG_DIR/sbin/rr_login
chmod +x $IMG_DIR/sbin/rr_login
ln -s /bin/busybox2 $IMG_DIR/sbin/getty
ln -s /bin/busybox2 $IMG_DIR/bin/login

echo "integrate SSH authorized_keys"
mkdir $IMG_DIR/root/.ssh
chmod 700 $IMG_DIR/root/.ssh
cat $BASE_DIR/authorized_keys > $IMG_DIR/root/.ssh/authorized_keys
cat $BASE_DIR/authorized_keys > $IMG_DIR/etc/dropbear/authorized_keys
chmod 600 $IMG_DIR/root/.ssh/authorized_keys
chmod 600 $IMG_DIR/etc/dropbear/authorized_keys
chown root:root $IMG_DIR/root -R

echo "replacing dropbear"
if [ -f $IMG_DIR/usr/bin/dropbear ]; then
md5sum $IMG_DIR/usr/bin/dropbear
install -m 0755 ./features/s8/dropbearmulti $IMG_DIR/usr/bin/dropbear
ln -s /usr/bin/dropbear $IMG_DIR/usr/bin/dbclient
ln -s /usr/bin/dropbear $IMG_DIR/usr/bin/scp
md5sum $IMG_DIR/usr/bin/dropbear
else
md5sum $IMG_DIR/usr/bin/dropbear
install -m 0755 ./features/s8/dropbearmulti $IMG_DIR/usr/sbin/dropbear
ln -s /usr/sbin/dropbear $IMG_DIR/usr/bin/dbclient
ln -s /usr/sbin/dropbear $IMG_DIR/usr/bin/scp
md5sum $IMG_DIR/usr/sbin/dropbear
fi

sed -i -E 's/SELINUX=enforcing/SELINUX=disabled/g' $IMG_DIR/etc/selinux/config


if [ -f $FLAG_DIR/adbd ]; then
    echo "replace adbd"
    #install -m 0755 $FEATURES_DIR/adbd $IMG_DIR/sbin/adbd
fi

if [ -f $FLAG_DIR/tools ]; then
    echo "installing tools"
    install -m 0755 ./features/s8/htop $IMG_DIR/usr/bin/htop
	install -m 0755 ./features/s8/nano $IMG_DIR/usr/bin/nano
	install -m 0755 ./features/s8/wget $IMG_DIR/usr/bin/wget
	install -m 0755 ./features/s8/curl $IMG_DIR/usr/bin/curl
	install -m 0755 ./features/s8/libncurses.so.5 $IMG_DIR/usr/lib/libncurses.so.5
	
fi

if [ -f $FLAG_DIR/patch_logging ]; then
    echo "patch logging"
    echo "patch upload stuff"
    # UPLOAD_METHOD=0 (no upload)
    sed -i -E 's/(UPLOAD_METHOD=)([0-9]+)/\10/' $OPT_DIR/rrlog/rrlog.conf
    sed -i -E 's/(UPLOAD_METHOD=)([0-9]+)/\10/' $OPT_DIR/rrlog/rrlogmt.conf

    # Set LOG_LEVEL=3
    sed -i -E 's/(LOG_LEVEL=)([0-9]+)/\13/' $OPT_DIR/rrlog/rrlog.conf
    sed -i -E 's/(LOG_LEVEL=)([0-9]+)/\13/' $OPT_DIR/rrlog/rrlogmt.conf

    # Reduce logging of miio_client
    sed -i 's/-l 2/-l 0/' $OPT_DIR/watchdog/ProcessList.conf

    # Let the script cleanup logs
    sed -i 's/nice.*//' $OPT_DIR/rrlog/tar_extra_file.sh

    # Disable collecting device info to /dev/shm/misc.log
    sed -i '/^\#!\/bin\/bash$/a exit 0' $OPT_DIR/rrlog/misc.sh

    # Disable logging of 'top'
    sed -i '/^\#!\/bin\/bash$/a exit 0' $OPT_DIR/rrlog/toprotation.sh
    sed -i '/^\#!\/bin\/bash$/a exit 0' $OPT_DIR/rrlog/topstop.sh
    echo "patch watchdog log"
    # Disable watchdog log
    # shellcheck disable=SC2016
    sed -i -E 's/\$RR_UDATA\/rockrobo\/rrlog\/watchdog.log/\/dev\/null/g' $OPT_DIR/watchdog/rrwatchdoge.conf
fi

if [ -f $FLAG_DIR/patch_dns ]; then

	md5sum $OPT_DIR/miio/miio_client
	if grep -q "ots_info_ack" $OPT_DIR/miio/miio_client; then
		echo "found OTS version of miio client, replacing it with 3.5.8"
		 cp $FEATURES_DIR/miio_clients/3.5.8_aarch64/miio_client $OPT_DIR/miio/miio_client
	fi
	md5sum $OPT_DIR/miio/miio_client

	if [ ! -f $IMG_DIR/usr/lib/libjson-c.so.2 ]; then
		install -m 0755 $FEATURES_DIR/miio_clients/3.5.8_aarch64.lib/* $IMG_DIR/usr/lib
	fi


	echo "patching DNS"
	sed -i -E 's/110.43.0.83/127.000.0.1/g' $OPT_DIR/miio/miio_client
	sed -i -E 's/110.43.0.85/127.000.0.1/g' $OPT_DIR/miio/miio_client
	md5sum $IMG_DIR/usr/lib/libcurl.so.4.6.0
    install -m 0755 ./features/s8/libcurl.so $IMG_DIR/usr/lib/libcurl.so.4.6.0
	md5sum $IMG_DIR/usr/lib/libcurl.so.4.6.0
	sed -i 's/dport 22/dport 27/' $OPT_DIR/watchdog/rrwatchdoge.conf
	cat $FEATURES_DIR/nsswitch/nsswitch.conf > $IMG_DIR/etc/nsswitch.conf
	cat $FEATURES_DIR/valetudo/deployment/etc/hosts-local > $IMG_DIR/etc/hosts
	mkdir -p $IMG_DIR/etc/hosts-bind
	mv $IMG_DIR/etc/hosts $IMG_DIR/etc/hosts-bind/
	ln -s /etc/hosts-bind/hosts $IMG_DIR/etc/hosts

fi

if [ -f $FLAG_DIR/hostname ]; then
	echo "patching Hostname"
	cat $FLAG_DIR/hostname > $IMG_DIR/etc/hostname
fi

sed -i "s/^exit 0//" $IMG_DIR/etc/rc.local
echo "touch /tmp/_inside_etc_rc_local.txt" >>  $IMG_DIR/etc/rc.local
echo "if [[ -f /mnt/reserve/_root.sh ]]; then" >> $IMG_DIR/etc/rc.local
echo "    /mnt/reserve/_root.sh &" >> $IMG_DIR/etc/rc.local
echo "fi" >> $IMG_DIR/etc/rc.local
echo "exit 0" >> $IMG_DIR/etc/rc.local

echo "installing rc.local links"
install -m 0755 $FEATURES_DIR/valetudo/deployment/S10rc_local_for_nand $IMG_DIR/etc/init.d/S16rc_local
ln -s ../init.d/S16rc_local $IMG_DIR/etc/rc.d/S95rc_local

echo "just make sure to put us in the watchdoge startup"
sed -i -E 's/echo \"startup rrwatchdoge...\"/sh \/etc\/rc.local \&\necho \"startup rrwatchdoge...\"/g' $IMG_DIR/usr/bin/start_rrwatchdoge.sh


install -m 0755 ./features/fwinstaller_s8/_root.sh.tpl $IMG_DIR/root/_root.sh.tpl
install -m 0755 ./features/fwinstaller_s8/how_to_modify.txt $IMG_DIR/root/how_to_modify.txt

touch $IMG_DIR/build.txt
echo "built with dustbuilder (https://builder.dontvacuum.me)" > $IMG_DIR/build.txt
date -u +"%Y-%m-%dT%H:%M:%SZ"  >> $IMG_DIR/build.txt
if [ -f $FLAG_DIR/version ]; then
    cat $FLAG_DIR/version >> $IMG_DIR/build.txt
fi
echo "" >> $IMG_DIR/build.txt

if [ -f $FLAG_DIR/jobmd5 ]; then
	touch $IMG_DIR/dustbuilder.txt
	cat $FLAG_DIR/version >> $IMG_DIR/dustbuilder.txt
	echo "" >> $IMG_DIR/dustbuilder.txt
	cat $FLAG_DIR/devicetypealias >> $IMG_DIR/dustbuilder.txt
	echo "" >> $IMG_DIR/dustbuilder.txt
	cat $FLAG_DIR/jobid >> $IMG_DIR/dustbuilder.txt
	echo "" >> $IMG_DIR/dustbuilder.txt
	cat $FLAG_DIR/jobkey >> $IMG_DIR/dustbuilder.txt
	echo "" >> $IMG_DIR/dustbuilder.txt
	cat $FLAG_DIR/jobmd5 >> $IMG_DIR/dustbuilder.txt
	echo "" >> $IMG_DIR/dustbuilder.txt
fi

echo "finished patching, repacking"

mksquashfs $IMG_DIR/ rootfs_tmp.img -noappend -root-owned -comp $COMPRESSION -b 128k
#rm -rf $IMG_DIR
dd if=$BASE_DIR/rootfs_tmp.img of=$BASE_DIR/rootfs.img bs=128k conv=sync
rm $BASE_DIR/rootfs_tmp.img

mksquashfs $OPT_DIR/ opt_tmp.img -noappend -root-owned -comp $COMPRESSION -b 256k
#rm -rf $OPT_DIR
dd if=$BASE_DIR/opt_tmp.img of=$BASE_DIR/opt.img bs=256k conv=sync
rm $BASE_DIR/opt_tmp.img

if [ -f $FLAG_DIR/vanilla ]; then
	echo "vanilla mode, purge rootfs, use template"
	rm $BASE_DIR/rootfs.img
	rm $BASE_DIR/opt.img
	cp $FLAG_DIR/rootfs.img.template $BASE_DIR/rootfs.img
	cp $FLAG_DIR/opt.img.template $BASE_DIR/opt.img
fi

md5sum ./*.img > $BASE_DIR/firmware.md5sum



echo "check image file size"
# S8
if [ ${FRIENDLYDEVICETYPE} = "roborock.vacuum.a51" ]; then
	echo "a51"
	maximumsize=75000000
	maximumsizeopt=85000000
	minimumsize=35000000
elif [ ${FRIENDLYDEVICETYPE} = "roborock.vacuum.a46" ]; then
	echo "a46"
	maximumsize=75000000
	maximumsizeopt=85000000
	minimumsize=35000000
else
    echo "all others"
	maximumsize=75000000
	maximumsizeopt=85000000
	minimumsize=35000000
fi

actualsize=$(wc -c < $BASE_DIR/rootfs.img)
if [ "$actualsize" -gt "$maximumsize" ]; then
	echo "(!!!) rootfs.img looks to big. The size might exceed the available space on the flash."
	echo "(!!!) rootfs.img looks to big. The size might exceed the available space on the flash." > $BASE_DIR/output/error.txt
        echo ${FRIENDLYDEVICETYPE} >> $BASE_DIR/output/error.txt
	echo $actualsize >> $BASE_DIR/output/error.txt
	echo $maximumsize >> $BASE_DIR/output/error.txt
	exit 1
fi

if [ "$actualsize" -le "$minimumsize" ]; then
	echo "(!!!) rootfs.img looks to small. Maybe something went wrong with the image generation."
        echo "(!!!) rootfs.img looks to small. Maybe something went wrong with the image generation." > $BASE_DIR/output/error.txt
        echo ${FRIENDLYDEVICETYPE} >> $BASE_DIR/output/error.txt
        echo $actualsize >> $BASE_DIR/output/error.txt
        echo $minimumsize >> $BASE_DIR/output/error.txt
	exit 1
fi

actualsize=$(wc -c < $BASE_DIR/opt.img)
if [ "$actualsize" -gt "$maximumsizeopt" ]; then
	echo "(!!!) opt.img looks to big. The size might exceed the available space on the flash."
	echo "(!!!) opt.img looks to big. The size might exceed the available space on the flash." > $BASE_DIR/output/error.txt
        echo ${FRIENDLYDEVICETYPE} >> $BASE_DIR/output/error.txt
	echo $actualsize >> $BASE_DIR/output/error.txt
	echo $maximumsizeopt >> $BASE_DIR/output/error.txt
	exit 1
fi

if [ "$actualsize" -le "$minimumsize" ]; then
	echo "(!!!) opt.img looks to small. Maybe something went wrong with the image generation."
        echo "(!!!) opt.img looks to small. Maybe something went wrong with the image generation." > $BASE_DIR/output/error.txt
        echo ${FRIENDLYDEVICETYPE} >> $BASE_DIR/output/error.txt
        echo $actualsize >> $BASE_DIR/output/error.txt
        echo $minimumsize >> $BASE_DIR/output/error.txt
	exit 1
fi

sed "s/DEVICEMODEL=.*/DEVICEMODEL=\"${DEVICETYPE}\"/g" ./features/fwinstaller_s8/install.sh > $BASE_DIR/install.sh
sed -i "s/# maxsizeplaceholder/maximumsize=${maximumsize}/g" $BASE_DIR/install.sh
sed -i "s/# minsizeplaceholder/minimumsize=${minimumsize}/g" $BASE_DIR/install.sh
chmod +x install.sh
install -m 0755 ./features/fwinstaller_s8/unsquashfs $BASE_DIR/unsquashfs
install -m 0755 ./features/s8/dmsetup $BASE_DIR/dmsetup
install -m 0755 ./features/s8/busybox2 $BASE_DIR/busybox2
tar -czf $BASE_DIR/output/${FRIENDLYDEVICETYPE}_${version}_fw.tar.gz $BASE_DIR/rootfs.img $BASE_DIR/opt.img $BASE_DIR/boot.img $BASE_DIR/firmware.md5sum $BASE_DIR/install.sh $BASE_DIR/unsquashfs $BASE_DIR/dmsetup $BASE_DIR/busybox2
md5sum $BASE_DIR/output/${FRIENDLYDEVICETYPE}_${version}_fw.tar.gz > $BASE_DIR/output/md5.txt
echo "${FRIENDLYDEVICETYPE}_${version}_fw.tar.gz" > $BASE_DIR/filename.txt
touch $BASE_DIR/server.txt

if [ -f $FLAG_DIR/diff ]; then
	echo "--------------"
        echo "unpack original"
        unsquashfs -d $BASE_DIR/original $BASE_DIR/rootfs.img.template
        rm -rf $BASE_DIR/original/dev
        echo "unpack modified"
        unsquashfs -d $BASE_DIR/modified $BASE_DIR/rootfs.img
        rm -rf $BASE_DIR/modified/dev

	/usr/bin/git diff --no-index $BASE_DIR/original/ $BASE_DIR/modified/ > $BASE_DIR/output/diff.txt
	rm -rf $BASE_DIR/original
	rm -rf $BASE_DIR/modified

fi

touch $BASE_DIR/output/done


