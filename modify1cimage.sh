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

if [ ! -f $BASE_DIR/update.zip ]; then
    echo "ERROR: File update.zip not found! Decryption and unpacking was apparently unsuccessful."
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
FRIENDLYDEVICETYPE=$(cat "$FLAG_DIR/devicetype")
jobid=$(cat "$FLAG_DIR/jobid")
jobidmd5=$(cat "$FLAG_DIR/jobid" | md5sum | awk '{print $1}')

mkdir -p $BASE_DIR/output

echo "--------------"
echo "creating temp directory and unpacking squashfs"
unzip $BASE_DIR/update.zip
rm $BASE_DIR/update.zip
unsquashfs -d $IMG_DIR $BASE_DIR/rootfs.img
if [ -f $BASE_DIR/rootfs.img.vanilla ]; then
	echo "moving vanilla image to template"										
	mv $BASE_DIR/rootfs.img.vanilla $BASE_DIR/rootfs.img.template
	rm $BASE_DIR/rootfs.img
else
	echo "moving rootfs to template"								 
	mv $BASE_DIR/rootfs.img $BASE_DIR/rootfs.img.template
fi
if [ -f $BASE_DIR/mcu.bin ]; then
	echo "importing mcu update"
	cp $BASE_DIR/mcu.bin $IMG_DIR/mcu.bin
fi

if [ -f $BASE_DIR/UI.bin ]; then
	echo "importing UI update"
	cp $BASE_DIR/UI.bin $IMG_DIR/UI.bin
fi

if [ -f $BASE_DIR/UIMA.bin ]; then
	echo "importing UIMA update"
	cp $BASE_DIR/UI*.bin $IMG_DIR/
fi

echo "installing dropbear keys"
mkdir -p $IMG_DIR/etc/dropbear
chown root:root $IMG_DIR/etc/dropbear
cat $BASE_DIR/dropbear_rsa_host_key > $IMG_DIR/etc/dropbear/dropbear_rsa_host_key
cat $BASE_DIR/dropbear_dss_host_key > $IMG_DIR/etc/dropbear/dropbear_dss_host_key
cat $BASE_DIR/dropbear_ecdsa_host_key > $IMG_DIR/etc/dropbear/dropbear_ecdsa_host_key
cat $BASE_DIR/dropbear_ed25519_host_key > $IMG_DIR/etc/dropbear/dropbear_ed25519_host_key

echo "installing dropbear"
install -d $IMG_DIR/usr/local/sbin
install -m 0755 $FEATURES_DIR/dropbear_1c/dropbear $IMG_DIR/usr/local/sbin
install -d $IMG_DIR/usr/local/bin
install -m 0755 $FEATURES_DIR/dropbear_1c/dbclient $IMG_DIR/usr/local/bin
install -d $IMG_DIR/usr/local/bin
install -m 0755 $FEATURES_DIR/dropbear_1c/scp $IMG_DIR/usr/local/bin
cat $BASE_DIR/authorized_keys > $IMG_DIR/authorized_keys

echo "--------------"
echo "creating hooks for scripts"
cat $FEATURES_DIR/dropbear_1c/dropbear.sh > $IMG_DIR/etc/rc.d/dropbear.sh
chmod +x $IMG_DIR/etc/rc.d/dropbear.sh
echo "" >> $IMG_DIR/etc/rc.sysinit
echo "/etc/rc.d/dropbear.sh &" >> $IMG_DIR/etc/rc.sysinit

sed -i "s/\/usr\/local\/bin/\/data\/bin:\/usr\/local\/bin/g" $IMG_DIR/etc/rc.sysinit

echo "" > $IMG_DIR/etc/_root.tmp
echo "if [[ -f /data/_root.sh ]]; then" >> $IMG_DIR/etc/_root.tmp
echo "    /data/_root.sh &" >> $IMG_DIR/etc/_root.tmp
echo "fi" >> $IMG_DIR/etc/_root.tmp
echo "" >> $IMG_DIR/etc/_root.tmp
sed -i "/mount_misc.sh/r $IMG_DIR/etc/_root.tmp" $IMG_DIR/etc/rc.sysinit
rm $IMG_DIR/etc/_root.tmp

echo "if [[ -f /data/_root_postboot.sh ]]; then" >> $IMG_DIR/etc/rc.sysinit
echo "    /data/_root_postboot.sh &" >> $IMG_DIR/etc/rc.sysinit
echo "fi" >> $IMG_DIR/etc/rc.sysinit

if [ -f $FLAG_DIR/patch_dns ]; then

#EXPERIMENT-disable-rsyslog: Prevents writing of some log files onto /data, which should increase NAND flash lifetime
sed -i "s/rsyslogd/# rsyslogd/g" $IMG_DIR/etc/rc.d/rsyslog.sh

#EXPERIMENT-monitor_cpu: Prevents writing of some log files onto /data, which should increase NAND flash lifetime
sed -i "s/source \/usr\/bin\/config/exit 0\nsource \/usr\/bin\/config/g" $IMG_DIR/etc/rc.d/monitor_cpu.sh

#EXPERIMENT-disable_trans: No clue what this does, looks sketchy, might not be relevant for release fw
sed -i "s/source \/usr\/bin\/config/exit 0\nsource \/usr\/bin\/config/g" $IMG_DIR/etc/rc.d/msg_trans_monitor.sh

#EXPERIMENT-redirect-miio-log: same as above. We move it to tmp and not tmp/log to prevent uploads
sed -i "s/\/data\/log\//\/tmp\//g" $IMG_DIR/etc/rc.d/miio_monitor.sh

#EXPERIMENT-redirect-miio-log: not sure if we actually need it or if we can remove the log
sed -i "s/\/data\/log\//\/tmp\//g" $IMG_DIR/etc/rc.d/miio.sh
sed -i "s/5242880/1048576/g" $IMG_DIR/etc/rc.d/miio.sh

#EXPERIMENT-redirect-wifi-log: same as above. We move it to tmp and not tmp/log to prevent uploads
#sed -i "s/\/data\/log\//\/tmp\//g" $IMG_DIR/etc/rc.d/wifi_monitor.sh

fi

echo "backdooring"
sed -i -E 's/::respawn:\/usr\/bin\/getty.sh//g' $IMG_DIR/etc/inittab
sed -i -E 's/Put a getty on the serial port/\n::respawn:-\/sbin\/getty -n -l \/bin\/dustshell 115200 -L ttyS0/g' $IMG_DIR/etc/inittab
echo -e "#!/bin/sh\n/bin/login -f root" > $IMG_DIR/bin/dustshell
chmod +x $IMG_DIR/bin/dustshell



if [ -f $FLAG_DIR/valetudo ]; then
	echo "copy valetudo"
	install -D -m 0755 $FEATURES_DIR/valetudo/valetudo-armv7-lowmem $BASE_DIR/valetudo
	install -m 0755 $FEATURES_DIR/fwinstaller_1c/_root_postboot.sh.tpl $BASE_DIR/_root_postboot.sh.tpl
	touch $FLAG_DIR/patch_dns
fi
if [ -f $FLAG_DIR/patch_dns ]; then
	echo "patching DNS"
	install -m 0755 $FEATURES_DIR/fwinstaller_1c/vfactory_reset.sh $IMG_DIR/usr/bin
	install -m 0755 $FEATURES_DIR/fwinstaller_1c/install-mcufw.sh $IMG_DIR/usr/bin
	cat $FEATURES_DIR/nsswitch/nsswitch.conf > $IMG_DIR/etc/nsswitch.conf
	if [ -f $IMG_DIR/usr/bin/miio_client_helper_mjac.sh ]; then
		rm $IMG_DIR/usr/bin/miio_client_helper_mjac.sh
		install -m 0755 $FEATURES_DIR/miio_clients/dreame_4.1.8/miio_client_helper_nomqtt.sh $IMG_DIR/usr/bin
	fi

	# EXPERIMENTAL: disable automatic OTA updates
	grep "MIIO_AUTO_OTA=true" $IMG_DIR/usr/bin/config
	if [ $? -eq 0 ]; then
		sed -i -E 's/MIIO_AUTO_OTA=true/MIIO_AUTO_OTA=false/g' $IMG_DIR/usr/bin/config	
	fi

	# EXPERIMENTAL: disable automatic OTA updates
	grep "MIIO_AUTO_OTA=true" $IMG_DIR/usr/bin/boardconfig
	if [ $? -eq 0 ]; then
		sed -i -E 's/MIIO_AUTO_OTA=true/MIIO_AUTO_OTA=false/g' $IMG_DIR/usr/bin/boardconfig	
	fi

	### newer firmwares do not use a custom mjac file anymore, so we need to catch that here
	grep "MIIO_SDK_MJAC=true" $IMG_DIR/usr/bin/config
	if [ $? -eq 0 ]; then
		sed -i -E 's/MIIO_SDK_MJAC=true/MIIO_SDK_MJAC=false/g' $IMG_DIR/usr/bin/config	
		sed -i -E 's/MIIO_NET_AUTO_PROVISION=1/MIIO_NET_AUTO_PROVISION=0/g' $IMG_DIR/usr/bin/wifi_start.sh
	fi

	grep "MIIO_SDK_MJAC=true" $IMG_DIR/usr/bin/boardconfig
	if [ $? -eq 0 ]; then
		sed -i -E 's/MIIO_SDK_MJAC=true/MIIO_SDK_MJAC=false/g' $IMG_DIR/usr/bin/boardconfig	
		sed -i -E 's/MIIO_NET_AUTO_PROVISION=1/MIIO_NET_AUTO_PROVISION=0/g' $IMG_DIR/usr/bin/wifi_start.sh
	fi

	
	install -m 0755 $FEATURES_DIR/miio_clients/dreame_3.5.8/miio_client.patchedlimit $IMG_DIR/usr/bin/miio_client
	### Downgrade the helper if we do not already have an older helper
	grep "version: 4.1.6" $IMG_DIR/usr/bin/miio_client_helper_nomqtt.sh
	if [ $? -eq 1 ]; then
		grep "version: 3.5.8" $IMG_DIR/usr/bin/miio_client_helper_nomqtt.sh
		if [ $? -eq 1 ]; then
			# Downgrade the helper
			install -m 0755 $FEATURES_DIR/miio_clients/dreame_4.1.8/miio_client_helper_nomqtt.sh $IMG_DIR/usr/bin
			### Dreame tries to add some dm crypt stuff and we need to make some non-compatible robots compatible with the 4.1.8 miio helper
			grep "DM_FLAG" $IMG_DIR/usr/bin/config
			if [ $? -eq 1 ]; then
				sed -i '1s/^/DM_FLAG=\/mnt\/misc\/dm\n/' $IMG_DIR/usr/bin/config
			fi
		fi
	fi

	### Some dreames may also act as a BLE gateway with the stock firmware (e.g P2148)
        if [ -f $IMG_DIR/etc/init.d/ble.sh ]; then
                sed -i "s/source \/usr\/bin\/config/exit 0\nsource \/usr\/bin\/config/g" $IMG_DIR/etc/init.d/ble.sh
        fi

        ### This script is used for tracking
        if [ -f $IMG_DIR/ava/script/curl_server.sh ]; then
                sed -i "s/source \/usr\/bin\/config/exit 0\nsource \/usr\/bin\/config/g" $IMG_DIR/ava/script/curl_server.sh
        fi

	
	if [ ! -f $IMG_DIR/usr/lib/libjson-c.so.2 ]; then
		install -m 0755 $FEATURES_DIR/miio_clients/3.5.8.lib/* $IMG_DIR/usr/lib
	fi
	sed -i -E 's/110.43.0.83/127.000.0.1/g' $IMG_DIR/usr/bin/miio_client
	sed -i -E 's/110.43.0.85/127.000.0.1/g' $IMG_DIR/usr/bin/miio_client
	rm $IMG_DIR/etc/hosts
	cat $FEATURES_DIR/valetudo/deployment/etc/hosts-local > $IMG_DIR/etc/hosts
	install -m 0755 $FEATURES_DIR/fwinstaller_1c/_root_postboot.sh.tpl $IMG_DIR/misc/_root_postboot.sh.tpl
	install -m 0755 $FEATURES_DIR/fwinstaller_1c/how_to_modify.txt $IMG_DIR/misc/how_to_modify.txt
	sed -i 's/-oDISABLE_PSM//' $IMG_DIR/etc/rc.d/miio.sh
	sed -i 's/set_change_user() {/set_change_user() { \n     return 0\n/' $IMG_DIR/ava/script/msg_cvt.sh
	sed -i "s/307545464D4D757233624A4261696A7A\"/307545464D4D757233624A4261696A7A\"\n    avacmd msg_cvt '{\"type\":\"msgCvt\",\"cmd\":\"nation_matched\",\"result\":\"matched\"}' \&\n    return 0\n/" $IMG_DIR/ava/script/msg_cvt.sh

	#Disable encryption of FDS uploads (if enabled)
	sed -i -E 's/ENC_FILE=yes/ENC_FILE=nah/g' $IMG_DIR/ava/lib/*
fi

if [ -f $FLAG_DIR/miio_target ]; then
	echo "patching miio_target"
	miio_target_ip=$(cat "$FLAG_DIR/miio_target")
	miio_target_ip=${miio_target_ip//[^0-9.]/}
	sed -i -E 's/110.43.0.83/127.000.0.1/g' $IMG_DIR/usr/bin/miio_client
	sed -i -E 's/110.43.0.85/127.000.0.1/g' $IMG_DIR/usr/bin/miio_client
	sed -i -E "s/127.000.0.1/${miio_target_ip}/g" $IMG_DIR/usr/bin/miio_client
	sed -i -E "s/127.000.0.1/${miio_target_ip}/g" $IMG_DIR/etc/hosts
fi

#echo "Fix broken Dreame cronjob scripts"
#sed -i -E 's/#source \/usr\/bin\/config/source \/usr\/bin\/config/g' $IMG_DIR/etc/rc.d/wifi_monitor.sh
#sed -i -E 's/#source \/usr\/bin\/config/source \/usr\/bin\/config/g' $IMG_DIR/etc/rc.d/miio_monitor.sh

echo "Remove chinese DNS server"
sed -i 's/echo "nameserver 114.114.114.114" >> $RESOLV_CONF//g' $IMG_DIR/usr/share/udhcpc/default.script
sed -i 's/echo "nameserver 114.114.114.114" > $RESOLV_CONF//g' $IMG_DIR/usr/share/udhcpc/default.script

#echo "Reduce wifi_manager loglevel to error to save the NAND"
#sed -i -E 's/-l4/-l1/g' $IMG_DIR/etc/rc.d/wifi_manager.sh

if [ -f $FLAG_DIR/tools ]; then
    echo "installing tools"
    cp -r $FEATURES_DIR/1c_tools/root-dir/* $IMG_DIR/
fi

if [ -f $FLAG_DIR/tools_pro ]; then
    echo "installing tools_pro"
    cp -r $FEATURES_DIR/1c_tools_pro/root-dir/* $IMG_DIR/
fi

if [ -f $FLAG_DIR/hostname ]; then
	echo "patching Hostname"
	cat $FLAG_DIR/hostname > $IMG_DIR/etc/hostname
	# urgh...
	sed -i -E 's/get_hostname()/get_host_name()/g' $IMG_DIR/etc/wifi/udhcpc.sh
	sed -i -E 's/get_hostname/#get_hostname/g' $IMG_DIR/etc/wifi/udhcpc.sh
	sed -i -E 's/get_host_name()/get_hostname()/g' $IMG_DIR/etc/wifi/udhcpc.sh
fi

if [ -f $FLAG_DIR/timezone ]; then
	echo "patching Timezone"
	cat $FLAG_DIR/timezone > $IMG_DIR/etc/timezone
fi

if [ -f $FEATURES_DIR/fwinstaller_1c/sanitize.sh ]; then
	echo "Cleanup Dreame backdoors"
	$FEATURES_DIR/fwinstaller_1c/sanitize.sh
fi

touch $IMG_DIR/build.txt
echo "built with dustbuilder (https://builder.dontvacuum.me)" > $IMG_DIR/build.txt
date -u +"%Y-%m-%dT%H:%M:%SZ"  >> $IMG_DIR/build.txt
if [ -f $FLAG_DIR/version ]; then
    cat $FLAG_DIR/version >> $IMG_DIR/build.txt
fi

echo "" >> $IMG_DIR/build.txt
sed -i '$ d' $IMG_DIR/etc/banner
sed -i '$ d' $IMG_DIR/etc/banner
cat $IMG_DIR/build.txt >> $IMG_DIR/etc/banner

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

echo "--------------"
echo "creating rootfs"
mksquashfs $IMG_DIR/ rootfs_tmp.img -noappend -root-owned -comp xz -b 256k -p '/dev d 755 0 0' -p '/dev/console c 600 0 0 5 1'
rm -rf $IMG_DIR
dd if=$BASE_DIR/rootfs_tmp.img of=$BASE_DIR/rootfs.img bs=128k conv=sync
rm $BASE_DIR/rootfs_tmp.img

if [ -f $FLAG_DIR/vanilla ]; then
	echo "vanilla mode, purge rootfs, use template"
	rm $BASE_DIR/rootfs.img
	cp $FLAG_DIR/rootfs.img.template $BASE_DIR/rootfs.img
fi

echo "computing md5"
md5sum $BASE_DIR/rootfs.img > $BASE_DIR/rootfs_md5sum
cp parameter.txt parameter

if [ -d $BASE_DIR/burnBL ]; then
        cp $BASE_DIR/burnBL/*.* $BASE_DIR/
fi

md5sum ./*.img > $BASE_DIR/firmware.md5sum

echo "check image file size"
if [ ${FRIENDLYDEVICETYPE} = "dreame.vacuum.mc1808" ]; then
	echo "mc1808"
	maximumsize=50000000
	minimumsize=21000000
elif [ ${FRIENDLYDEVICETYPE} = "dreame.vacuum.mb1808" ]; then
    	echo "mb1808"
	maximumsize=50000000
	minimumsize=21000000
elif [ ${FRIENDLYDEVICETYPE} = "dreame.vacuum.p2009" ]; then
    	echo "p2009"
	maximumsize=30000000
	minimumsize=20000000
elif [ ${FRIENDLYDEVICETYPE} = "dreame.vacuum.p2027" ]; then
	echo "p2027"
        maximumsize=32000000
        minimumsize=20000000
elif [ ${FRIENDLYDEVICETYPE} = "dreame.vacuum.r2216" ]; then
	echo "r2216"
        maximumsize=50000000
        minimumsize=29000000
elif [ ${FRIENDLYDEVICETYPE} = "dreame.vacuum.r2257" ]; then
	echo "r2257"
        maximumsize=50000000
        minimumsize=29000000
else
	echo "all others"
	maximumsize=30000000
	minimumsize=20000000
fi

actualsize=$(wc -c < $BASE_DIR/rootfs.img)
if [ "$actualsize" -gt "$maximumsize" ]; then
        echo "(!!!) rootfs.img looks to big. The size might exceed the available space on the flash. $actualsize > $maximumsize"
        echo "(!!!) rootfs.img looks to big. The size might exceed the available space on the flash. $actualsize > $maximumsize" > $BASE_DIR/output/error.txt
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

	echo "create installer package"
	install -m 0755 $FEATURES_DIR/fwinstaller_1c/install-mcufw.sh $BASE_DIR/install-mcufw.sh
	if [ -f $FLAG_DIR/valetudo ]; then
		sed "s/DEVICEMODEL=.*/DEVICEMODEL=\"${DEVICETYPE}\"/g" $FEATURES_DIR/fwinstaller_1c/install-val.sh > $BASE_DIR/install.sh
		sed -i "s/# maxsizeplaceholder/maximumsize=${maximumsize}/g" $BASE_DIR/install.sh
		sed -i "s/# minsizeplaceholder/minimumsize=${minimumsize}/g" $BASE_DIR/install.sh
		chmod +x install.sh
		sed "s/DEVICEMODEL=.*/DEVICEMODEL=\"${DEVICETYPE}\"/g" $FEATURES_DIR/fwinstaller_1c/install-manual.sh > $BASE_DIR/install-manual.sh
		sed -i "s/# maxsizeplaceholder/maximumsize=${maximumsize}/g" $BASE_DIR/install-manual.sh
		sed -i "s/# minsizeplaceholder/minimumsize=${minimumsize}/g" $BASE_DIR/install-manual.sh
		chmod +x install-manual.sh
                if [ -f $BASE_DIR/UI.bin ]; then
                        tar -czf $BASE_DIR/output/${DEVICETYPE}_fw.tar.gz $BASE_DIR/*.img $BASE_DIR/mcu_md5sum mcu.bin $BASE_DIR/firmware.md5sum $BASE_DIR/install.sh $BASE_DIR/install-manual.sh $BASE_DIR/install-mcufw.sh $BASE_DIR/valetudo $BASE_DIR/_root_postboot.sh.tpl $BASE_DIR/ui_md5sum $BASE_DIR/UI.bin
                elif [ -f $BASE_DIR/UIMA.bin ]; then
                        tar -czf $BASE_DIR/output/${DEVICETYPE}_fw.tar.gz $BASE_DIR/*.img $BASE_DIR/mcu_md5sum mcu.bin $BASE_DIR/firmware.md5sum $BASE_DIR/install.sh $BASE_DIR/install-manual.sh $BASE_DIR/install-mcufw.sh $BASE_DIR/valetudo $BASE_DIR/_root_postboot.sh.tpl $BASE_DIR/ui_md5sum $BASE_DIR/UI*.bin
                else
                        tar -czf $BASE_DIR/output/${DEVICETYPE}_fw.tar.gz $BASE_DIR/*.img $BASE_DIR/mcu_md5sum mcu.bin $BASE_DIR/firmware.md5sum $BASE_DIR/install.sh $BASE_DIR/install-manual.sh $BASE_DIR/install-mcufw.sh $BASE_DIR/valetudo $BASE_DIR/_root_postboot.sh.tpl
                fi
	else
		sed "s/DEVICEMODEL=.*/DEVICEMODEL=\"${DEVICETYPE}\"/g" $FEATURES_DIR/fwinstaller_1c/install.sh > $BASE_DIR/install.sh
		sed -i "s/# maxsizeplaceholder/maximumsize=${maximumsize}/g" $BASE_DIR/install.sh
		sed -i "s/# minsizeplaceholder/minimumsize=${minimumsize}/g" $BASE_DIR/install.sh
		chmod +x install.sh
		sed "s/DEVICEMODEL=.*/DEVICEMODEL=\"${DEVICETYPE}\"/g" $FEATURES_DIR/fwinstaller_1c/install-manual.sh > $BASE_DIR/install-manual.sh
		sed -i "s/# maxsizeplaceholder/maximumsize=${maximumsize}/g" $BASE_DIR/install-manual.sh
		sed -i "s/# minsizeplaceholder/minimumsize=${minimumsize}/g" $BASE_DIR/install-manual.sh
		chmod +x install-manual.sh
		if [ -f $BASE_DIR/UI.bin ]; then
			tar -czf $BASE_DIR/output/${DEVICETYPE}_fw.tar.gz $BASE_DIR/*.img $BASE_DIR/mcu_md5sum mcu.bin $BASE_DIR/firmware.md5sum $BASE_DIR/install.sh $BASE_DIR/install-manual.sh $BASE_DIR/install-mcufw.sh $BASE_DIR/ui_md5sum $BASE_DIR/UI.bin
		elif [ -f $BASE_DIR/UIMA.bin ]; then
			tar -czf $BASE_DIR/output/${DEVICETYPE}_fw.tar.gz $BASE_DIR/*.img $BASE_DIR/mcu_md5sum mcu.bin $BASE_DIR/firmware.md5sum $BASE_DIR/install.sh $BASE_DIR/install-manual.sh $BASE_DIR/install-mcufw.sh $BASE_DIR/ui_md5sum $BASE_DIR/UI*.bin
		else
			tar -czf $BASE_DIR/output/${DEVICETYPE}_fw.tar.gz $BASE_DIR/*.img $BASE_DIR/mcu_md5sum mcu.bin $BASE_DIR/firmware.md5sum $BASE_DIR/install.sh $BASE_DIR/install-manual.sh $BASE_DIR/install-mcufw.sh
		fi
	fi
	md5sum $BASE_DIR/output/${DEVICETYPE}_fw.tar.gz > $BASE_DIR/output/md5.txt
	echo "${DEVICETYPE}_fw.tar.gz" > $BASE_DIR/filename.txt
	touch $BASE_DIR/server.txt

if [ -f $FLAG_DIR/diff ]; then
    echo "--------------"
	echo "unpack original"
	unsquashfs -d $BASE_DIR/original $BASE_DIR/rootfs.img.template
	rm -rf $BASE_DIR/original/dev
	echo "unpack modified"
	unsquashfs -d $BASE_DIR/modified $BASE_DIR/rootfs.img
	rm -rf $BASE_DIR/modified/dev
	rm $BASE_DIR/original/etc/OTA_Key_pub.pem
	rm $BASE_DIR/original/etc/adb_keys
	rm $BASE_DIR/original/etc/publickey.pem
	rm $BASE_DIR/original/usr/bin/autossh.sh
	rm $BASE_DIR/original/usr/bin/backup_key.sh
	rm $BASE_DIR/original/usr/bin/curl_download.sh
	rm $BASE_DIR/original/usr/bin/curl_upload.sh
	rm $BASE_DIR/original/usr/bin/packlog.sh
	sed -i "s/dibEPK917k/Gi29djChze/" $BASE_DIR/original/etc/*

	/usr/bin/git diff --no-index $BASE_DIR/original/ $BASE_DIR/modified/ > $BASE_DIR/output/diff.txt
	rm -rf $BASE_DIR/original
	rm -rf $BASE_DIR/modified
fi

touch $BASE_DIR/output/done
