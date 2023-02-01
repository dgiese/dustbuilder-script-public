#!/bin/bash
# Author: Dennis Giese [dgiese@dontvacuum.me]
# Copyright 2017 by Dennis Giese

BASE_DIR="."
FLAG_DIR="."
IMG_DIR="./payload"
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

if [ ! -d $FEATURES_DIR/felnand ]; then
    echo "ERROR: felnand directory not found. You might want to clone the repo to ${FEATURES_DIR}, aborting"
    exit 1
fi

DEVICETYPE=$(cat "$FLAG_DIR/devicetype")
FRIENDLYDEVICETYPE=$(sed "s/\[s|t\]/x/g" $FLAG_DIR/devicetype)
version=$(cat "$FLAG_DIR/version")
jobid=$(cat "$FLAG_DIR/jobid")
jobidmd5=$(cat "$FLAG_DIR/jobid" | md5sum | awk '{print $1}')

mkdir -p $BASE_DIR/output
mkdir -p $BASE_DIR/kernel

cp -r $FEATURES_DIR/felnand/_initrd $IMG_DIR
mkdir -p $IMG_DIR/default
mkdir -p $IMG_DIR/dev
mkdir -p $IMG_DIR/sys
mkdir -p $IMG_DIR/proc
mkdir -p $IMG_DIR/tmp
chmod 777 $IMG_DIR/default
chmod 777 $IMG_DIR/dev
chmod 777 $IMG_DIR/sys
chmod 777 $IMG_DIR/proc
chmod 777 $IMG_DIR/tmp


if [ -f $FLAG_DIR/fix_boot ]; then
    echo "Fix Boot partitions"
    cp -r $FEATURES_DIR/felnand/_s5e_fix/* $IMG_DIR
fi

if [ -f $FLAG_DIR/fel_shell ]; then
    echo "Using FEL shell"
    cp -r $FEATURES_DIR/felnand/_fel_shell/* $IMG_DIR
fi


echo "integrate SSH authorized_keys"
cat $BASE_DIR/authorized_keys > $IMG_DIR/authorized_keys
cat $BASE_DIR/jobid > $IMG_DIR/id

sed -i "s/DEVICEMODEL=.*/DEVICEMODEL=\"${DEVICETYPE}\"/g" $IMG_DIR/patch.sh
chmod +x $IMG_DIR/patch.sh

echo "create rootfs.cpio"
sh -c 'cd payload/ && find . | cpio -H newc -o' > $BASE_DIR/kernel/rootfs.cpio

echo "copy kernel"

cp -r $FEATURES_DIR/felnand/linux-9ed/* $BASE_DIR/kernel/
cp $FEATURES_DIR/felnand/linux-9ed/configs/felnand.config $BASE_DIR/kernel/.config

echo "compile kernel"
cd $BASE_DIR/kernel/
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- uImage
cd ..

if [ ! -f $BASE_DIR/kernel/arch/arm/boot/uImage ]; then
    echo "Kernel building failed"
	exit 1
fi

zip -j $BASE_DIR/output/${FRIENDLYDEVICETYPE}_${version}_fel.zip $BASE_DIR/kernel/arch/arm/boot/uImage $FEATURES_DIR/felnand/package/*.* $BASE_DIR/activation.lic

md5sum $BASE_DIR/output/${FRIENDLYDEVICETYPE}_${version}_fel.zip >> $BASE_DIR/output/md5.txt
echo "$BASE_DIR/output/${FRIENDLYDEVICETYPE}_${version}_fel.zip" > $BASE_DIR/filename.txt

touch $BASE_DIR/output/done


