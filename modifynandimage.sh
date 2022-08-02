#!/bin/bash
# Author: Dennis Giese [dgiese@dontvacuum.me]
# Copyright 2017 by Dennis Giese

BASE_DIR="."
FLAG_DIR="."
IMG_DIR="./squashfs-root"
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
unsquashfs -d $IMG_DIR $BASE_DIR/rootfs.img.template
mkdir -p $IMG_DIR/etc/dropbear
chown root:root $IMG_DIR/etc/dropbear
cat $BASE_DIR/dropbear_rsa_host_key > $IMG_DIR/etc/dropbear/dropbear_rsa_host_key
cat $BASE_DIR/dropbear_dss_host_key > $IMG_DIR/etc/dropbear/dropbear_dss_host_key
cat $BASE_DIR/dropbear_ecdsa_host_key > $IMG_DIR/etc/dropbear/dropbear_ecdsa_host_key
cat $BASE_DIR/dropbear_ed25519_host_key > $IMG_DIR/etc/dropbear/dropbear_ed25519_host_key

echo "disable SSH firewall rule"
sed -i -e '/    iptables -I INPUT -j DROP -p tcp --dport 22/s/^/#/g' $IMG_DIR/opt/rockrobo/watchdog/rrwatchdoge.conf
sed -i -E 's/dport 22/dport 29/g' $IMG_DIR/opt/rockrobo/watchdog/WatchDoge
sed -i -E 's/dport 22/dport 29/g' $IMG_DIR/opt/rockrobo/rrlog/rrlogd

echo "reverting rr_login"
sed -i -E 's/::respawn:\/sbin\/rr_login -d \/dev\/ttyS0 -b 115200 -p vt100/::respawn:\/sbin\/getty -L ttyS0 115200 vt100/g' $IMG_DIR/etc/inittab

echo "integrate SSH authorized_keys"
mkdir $IMG_DIR/root/.ssh
chmod 700 $IMG_DIR/root/.ssh
cat $BASE_DIR/authorized_keys > $IMG_DIR/root/.ssh/authorized_keys
cat $BASE_DIR/authorized_keys > $IMG_DIR/etc/dropbear/authorized_keys
chmod 600 $IMG_DIR/root/.ssh/authorized_keys
chmod 600 $IMG_DIR/etc/dropbear/authorized_keys
chown root:root $IMG_DIR/root -R

if [ -f "$BASE_DIR/librrlocale.so" ]; then
    echo "patch region signature checking"
    install -m 0755 "$BASE_DIR/librrlocale.so" $IMG_DIR/opt/rockrobo/cleaner/lib/librrlocale.so
fi

echo "replacing dropbear"
md5sum $IMG_DIR/usr/sbin/dropbear
install -m 0755 $FEATURES_DIR/dropbear_rr22/dropbear $IMG_DIR/usr/sbin/dropbear
install -m 0755 $FEATURES_DIR/dropbear_rr22/dbclient $IMG_DIR/usr/bin/dbclient
install -m 0755 $FEATURES_DIR/dropbear_rr22/dropbearkey $IMG_DIR/usr/bin/dropbearkey
install -m 0755 $FEATURES_DIR/dropbear_rr22/scp $IMG_DIR/usr/bin/scp
md5sum $IMG_DIR/usr/sbin/dropbear

md5sum $IMG_DIR/opt/rockrobo/miio/miio_client
if grep -q "ots_info_ack" $IMG_DIR/opt/rockrobo/miio/miio_client; then
	echo "found OTS version of miio client, replacing it with 3.5.8"
     cp $FEATURES_DIR/miio_clients/3.5.8/miio_client $IMG_DIR/opt/rockrobo/miio/miio_client
fi
md5sum $IMG_DIR/opt/rockrobo/miio/miio_client


if [ -f $FLAG_DIR/adbd ]; then
    echo "replace adbd"
    install -m 0755 $FEATURES_DIR/adbd $IMG_DIR/usr/bin/adbd
fi

echo "replace tcpdump"
echo "#!/bin/sh" > $IMG_DIR/usr/sbin/tcpdump
echo "exit 0" >> $IMG_DIR/usr/sbin/tcpdump


#echo "install iptables modules"
#    mkdir -p $IMG_DIR/lib/xtables/
#    cp $FEATURES_DIR/iptables/xtables/*.* $IMG_DIR/lib/xtables/
#    cp $FEATURES_DIR/iptables/ip6tables $IMG_DIR/sbin/


if [ -f $FLAG_DIR/tools ]; then
    echo "installing tools"
    cp -r $FEATURES_DIR/rr_tools/root-dir/* $IMG_DIR/
fi

# minimal tool package for S7 as the firmware is to fat
if [ -f $FLAG_DIR/tools_min ]; then
    echo "installing minimal tools"
    cp -r $FEATURES_DIR/rr_tools_minimal/root-dir/* $IMG_DIR/
fi

if [ -f $FLAG_DIR/patch_logging ]; then
    echo "patch logging"
    echo "patch upload stuff"
    # UPLOAD_METHOD=0 (no upload)
    sed -i -E 's/(UPLOAD_METHOD=)([0-9]+)/\10/' $IMG_DIR/opt/rockrobo/rrlog/rrlog.conf
    sed -i -E 's/(UPLOAD_METHOD=)([0-9]+)/\10/' $IMG_DIR/opt/rockrobo/rrlog/rrlogmt.conf

    # Set LOG_LEVEL=3
    sed -i -E 's/(LOG_LEVEL=)([0-9]+)/\13/' $IMG_DIR/opt/rockrobo/rrlog/rrlog.conf
    sed -i -E 's/(LOG_LEVEL=)([0-9]+)/\13/' $IMG_DIR/opt/rockrobo/rrlog/rrlogmt.conf

    # Reduce logging of miio_client
    sed -i 's/-l 2/-l 0/' $IMG_DIR/opt/rockrobo/watchdog/ProcessList.conf

    # Let the script cleanup logs
    sed -i 's/nice.*//' $IMG_DIR/opt/rockrobo/rrlog/tar_extra_file.sh

    # Disable collecting device info to /dev/shm/misc.log
    sed -i '/^\#!\/bin\/bash$/a exit 0' $IMG_DIR/opt/rockrobo/rrlog/misc.sh

    # Disable logging of 'top'
    sed -i '/^\#!\/bin\/bash$/a exit 0' $IMG_DIR/opt/rockrobo/rrlog/toprotation.sh
    sed -i '/^\#!\/bin\/bash$/a exit 0' $IMG_DIR/opt/rockrobo/rrlog/topstop.sh
    echo "patch watchdog log"
    # Disable watchdog log
    # shellcheck disable=SC2016
    sed -i -E 's/\$RR_UDATA\/rockrobo\/rrlog\/watchdog.log/\/dev\/null/g' $IMG_DIR/opt/rockrobo/watchdog/rrwatchdoge.conf
fi

if [ -f $FLAG_DIR/patch_dns ]; then
	echo "patching DNS"
	sed -i -E 's/110.43.0.83/127.000.0.1/g' $IMG_DIR/opt/rockrobo/miio/miio_client
	sed -i -E 's/110.43.0.85/127.000.0.1/g' $IMG_DIR/opt/rockrobo/miio/miio_client
	sed -i 's/dport 22/dport 27/' $IMG_DIR/opt/rockrobo/watchdog/rrwatchdoge.conf
	cat $FEATURES_DIR/valetudo/deployment/etc/hosts-local > $IMG_DIR/etc/hosts
fi

if [ -f $FLAG_DIR/hostname ]; then
echo "patching Hostname"
	cat $FLAG_DIR/hostname > $IMG_DIR/etc/hostname
fi

mkdir -p $IMG_DIR/etc/hosts-bind
mv $IMG_DIR/etc/hosts $IMG_DIR/etc/hosts-bind/
ln -s /etc/hosts-bind/hosts $IMG_DIR/etc/hosts

sed -i "s/^exit 0//" $IMG_DIR/etc/rc.local
echo "if [[ -f /mnt/reserve/_root.sh ]]; then" >> $IMG_DIR/etc/rc.local
echo "    /mnt/reserve/_root.sh &" >> $IMG_DIR/etc/rc.local
echo "fi" >> $IMG_DIR/etc/rc.local
echo "exit 0" >> $IMG_DIR/etc/rc.local

install -m 0755 $FEATURES_DIR/valetudo/deployment/S10rc_local_for_nand $IMG_DIR/etc/init/S10rc_local

install -m 0755 $FEATURES_DIR/fwinstaller_nand/_root.sh.tpl $IMG_DIR/root/_root.sh.tpl
install -m 0755 $FEATURES_DIR/fwinstaller_nand/how_to_modify.txt $IMG_DIR/root/how_to_modify.txt

touch $IMG_DIR/build.txt
echo "build with firmwarebuilder (https://builder.dontvacuum.me)" > $IMG_DIR/build.txt
date -u  >> $IMG_DIR/build.txt
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

mksquashfs $IMG_DIR/ rootfs_tmp.img -noappend -root-owned -comp gzip -b 128k
rm -rf $IMG_DIR
dd if=$BASE_DIR/rootfs_tmp.img of=$BASE_DIR/rootfs.img bs=128k conv=sync
rm $BASE_DIR/rootfs_tmp.img

if [ -f $FLAG_DIR/vanilla ]; then
	echo "vanilla mode, purge rootfs, use template"
	rm $BASE_DIR/rootfs.img
	cp $FLAG_DIR/rootfs.img.template $BASE_DIR/rootfs.img
fi

md5sum ./*.img > $BASE_DIR/firmware.md5sum



echo "check image file size"
# S5 Max
if [ ${FRIENDLYDEVICETYPE} = "roborock.vacuum.s5e" ]; then
	echo "s5e"
	maximumsize=26214400
	minimumsize=20000000
# Roborock S6 Pure
elif [ ${FRIENDLYDEVICETYPE} = "roborock.vacuum.a08" ]; then
    echo "a08"
	maximumsize=24117248
	minimumsize=20000000
# Roborock S7
elif [ ${FRIENDLYDEVICETYPE} = "roborock.vacuum.a15" ]; then
    echo "a15"
	maximumsize=24117248
	minimumsize=20000000
# Roborock S4 Max
elif [ ${FRIENDLYDEVICETYPE} = "roborock.vacuum.a19" ]; then
    echo "a19"
	maximumsize=24117248
	minimumsize=20000000
else
	echo "all others"
	maximumsize=24117248
	minimumsize=20000000
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
        echo $maximumsize >> $BASE_DIR/output/error.txt
	exit 1
fi

sed "s/DEVICEMODEL=.*/DEVICEMODEL=\"${DEVICETYPE}\"/g" $FEATURES_DIR/fwinstaller_nand/install.sh > $BASE_DIR/install.sh
sed -i "s/# maxsizeplaceholder/maximumsize=${maximumsize}/g" $BASE_DIR/install.sh
sed -i "s/# minsizeplaceholder/minimumsize=${minimumsize}/g" $BASE_DIR/install.sh
chmod +x install.sh
tar -czf $BASE_DIR/output/${FRIENDLYDEVICETYPE}_${version}_fw.tar.gz $BASE_DIR/rootfs.img $BASE_DIR/boot.img $BASE_DIR/firmware.md5sum $BASE_DIR/install.sh
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


