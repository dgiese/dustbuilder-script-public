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

if [ ! -f ${BASE_DIR}/update.zip ]; then
    echo "ERROR: File update.zip not found! Decryption and unpacking was apparently unsuccessful."
	echo "please create zip file that contains rootfs.img, boot.img and mcu.bin. Make sure that the files are compatible with your device"
    exit 1
fi

if [ ! -f ${BASE_DIR}/authorized_keys ]; then
    echo "ERROR: authorized_keys not found. Please create your authorized_keys file first (it contains the public portion of your ssh key, likely starting with ssh-rsa)."
    exit 1
fi

if [ ! -f ${FLAG_DIR}/devicetype ]; then
    echo "ERROR: devicetype definition not found, aborting"
    echo "you likely want to set the flags manually or by running _buildflags.sh from dustbuilder"
    exit 1
fi

if [ ! -f ${FLAG_DIR}/jobid ]; then
    echo "ERROR: jobid not found, aborting"
    echo "you likely want to set the flags manually or by running _buildflags.sh from dustbuilder"
    exit 1
fi

if [ ! -d ${FEATURES_DIR} ]; then
    echo "ERROR: Features directory not found. You might want to clone the repo from https://github.com/dgiese/dustbuilder-features to ${FEATURES_DIR}, aborting"
    exit 1
fi

DEVICETYPE=$(cat "${FLAG_DIR}/devicetype")
FRIENDLYDEVICETYPE=$(cat "${FLAG_DIR}/devicetype")
jobid=$(cat "${FLAG_DIR}/jobid")
jobidmd5=$(cat "${FLAG_DIR}/jobid" | md5sum | awk '{print $1}')

mkdir -p ${BASE_DIR}/output

echo "--------------"
echo "creating temp directory and unpacking squashfs"
unzip ${BASE_DIR}/update.zip
rm ${BASE_DIR}/update.zip
unsquashfs -d ${IMG_DIR} ${BASE_DIR}/rootfs.img
if [ -f ${BASE_DIR}/rootfs.img.vanilla ]; then
	echo "moving vanilla image to template"
	mv ${BASE_DIR}/rootfs.img.vanilla ${BASE_DIR}/rootfs.img.template
	rm ${BASE_DIR}/rootfs.img
else
	echo "moving rootfs to template"
	mv ${BASE_DIR}/rootfs.img ${BASE_DIR}/rootfs.img.template
fi

echo "installing dropbear keys"
rm -f ${IMG_DIR}/etc/dropbear # The E20 Evo Plus already has this as a symlink pointing to /run
mkdir -p ${IMG_DIR}/etc/dropbear
chown root:root ${IMG_DIR}/etc/dropbear
cat ${BASE_DIR}/dropbear_rsa_host_key > ${IMG_DIR}/etc/dropbear/dropbear_rsa_host_key
cat ${BASE_DIR}/dropbear_dss_host_key > ${IMG_DIR}/etc/dropbear/dropbear_dss_host_key
cat ${BASE_DIR}/dropbear_ecdsa_host_key > ${IMG_DIR}/etc/dropbear/dropbear_ecdsa_host_key
cat ${BASE_DIR}/dropbear_ed25519_host_key > ${IMG_DIR}/etc/dropbear/dropbear_ed25519_host_key

echo "installing dropbear"
install -d ${IMG_DIR}/usr/local/sbin
install -m 0755 ${FEATURES_DIR}/dropbear_1t/dropbear ${IMG_DIR}/usr/sbin
install -d ${IMG_DIR}/usr/local/bin
install -m 0755 ${FEATURES_DIR}/dropbear_1t/dbclient ${IMG_DIR}/usr/bin
install -d ${IMG_DIR}/usr/local/bin
install -m 0755 ${FEATURES_DIR}/dropbear_1t/scp ${IMG_DIR}/usr/bin
cat ${BASE_DIR}/authorized_keys > ${IMG_DIR}/authorized_keys
mkdir -p ${IMG_DIR}/root/.ssh
cat ${BASE_DIR}/authorized_keys > ${IMG_DIR}/root/.ssh/authorized_keys


echo "--------------"
echo "creating hooks for scripts"
cat ${FEATURES_DIR}/dropbear_1t/dropbear-midea.sh > ${IMG_DIR}/etc/init.d/S97dropbear.sh
chmod +x ${IMG_DIR}/etc/init.d/S97dropbear.sh

echo "#!/bin/sh" > ${IMG_DIR}/etc/init.d/S22_root.sh
echo "if [[ -f /oem/_root.sh ]]; then" >> ${IMG_DIR}/etc/init.d/S22_root.sh
echo "    chmod +x /oem/_root.sh" >> ${IMG_DIR}/etc/init.d/S22_root.sh
echo "    /oem/_root.sh &" >> ${IMG_DIR}/etc/init.d/S22_root.sh
echo "fi" >> ${IMG_DIR}/etc/init.d/S22_root.sh
echo "" >> ${IMG_DIR}/etc/init.d/S22_root.sh
chmod +x ${IMG_DIR}/etc/init.d/S22_root.sh

echo "#!/bin/sh" > ${IMG_DIR}/etc/init.d/S98_postboot.sh
echo "if [[ -f /oem/_root_postboot.sh ]]; then" >> ${IMG_DIR}/etc/init.d/S98_postboot.sh
echo "    chmod +x /oem/_root_postboot.sh" >> ${IMG_DIR}/etc/init.d/S98_postboot.sh
echo "    /oem/_root_postboot.sh &" >> ${IMG_DIR}/etc/init.d/S98_postboot.sh
echo "fi" >> ${IMG_DIR}/etc/init.d/S98_postboot.sh
echo "" >> ${IMG_DIR}/etc/init.d/S98_postboot.sh
chmod +x ${IMG_DIR}/etc/init.d/S98_postboot.sh

# Include the config value in the firmware for users that might lose it
if [ -f ${FLAG_DIR}/configvalue ]; then
        cp "${FLAG_DIR}/configvalue" "${IMG_DIR}/dust_configvalue"
fi

echo "backdooring"
sed -i "s/login/sh/" ${IMG_DIR}/bin/adb_shell
sed -i "s/#::respawn:-/::respawn:-/" ${IMG_DIR}/etc/inittab
sed -i "s/ttyFIQ0/#ttyFIQ0/" ${IMG_DIR}/etc/inittab
new_hash='$1$qasBt/BW$cXCi/N0pji0wBICWQdp32.'
sed -i -E "s|^(root:)[^:]*|\1$new_hash|" ${IMG_DIR}/etc/shadow
sed -i "s/\/root/\/tmp/" ${IMG_DIR}/etc/passwd


if [ -f ${FLAG_DIR}/valetudo ]; then
        echo "copy valetudo"
        install -D -m 0755 ${FEATURES_DIR}/valetudo/valetudo-aarch64 ${BASE_DIR}/valetudo
        touch ${FLAG_DIR}/patch_dns
fi

if [ -f ${FLAG_DIR}/patch_dns ]; then
	echo "#!/bin/sh" > ${IMG_DIR}/etc/init.d/S23ramlogs
	echo "" >> ${IMG_DIR}/etc/init.d/S23ramlogs
	echo "case \"\$1\" in" >> ${IMG_DIR}/etc/init.d/S23ramlogs
	echo "    start|\"\")" >> ${IMG_DIR}/etc/init.d/S23ramlogs
	echo "        echo \"Mounting tmpfs for logs...\"" >> ${IMG_DIR}/etc/init.d/S23ramlogs
	echo "        mount -t tmpfs -o size=30m tmpfs /userdata/logs/" >> ${IMG_DIR}/etc/init.d/S23ramlogs
	echo "        ;;" >> ${IMG_DIR}/etc/init.d/S23ramlogs
	echo "esac" >> ${IMG_DIR}/etc/init.d/S23ramlogs
	chmod +x ${IMG_DIR}/etc/init.d/S23ramlogs


	cat ${FEATURES_DIR}/midea/hosts >> ${IMG_DIR}/etc/hosts
	cat ${FEATURES_DIR}/midea/dust_modules_updater.sh >> ${IMG_DIR}/bin/dust_modules_updater.sh
	cat $FEATURES_DIR/nsswitch/nsswitch.conf > $IMG_DIR/etc/nsswitch.conf

	chmod +x ${IMG_DIR}/bin/dust_modules_updater.sh

	mkdir -p ${IMG_DIR}/etc/ssl/valetudo

	faketime '2015-01-01 00:00:00' openssl req -x509 -new -nodes \
	    -newkey rsa:4096 -keyout ${IMG_DIR}/etc/ssl/valetudo/ca.key \
	    -sha256 -days 36525 -out ${IMG_DIR}/etc/ssl/valetudo/ca.pem \
	    -subj "/CN=DustCA"

	cat ${IMG_DIR}/etc/ssl/valetudo/ca.pem >> ${IMG_DIR}/etc/ssl/certs/cacert.pem

	# MQTT
	cp ${IMG_DIR}/etc/ssl/valetudo/ca.pem ${IMG_DIR}/usr/ssl/CA.pem

	# NTP - Without the sync working, the firmware won't connect
	sed -i 's/north-america\.pool\.ntp\.org/no.more.ideas.lol.localntp/g' ${IMG_DIR}/usr/lib/libmziot.so
	sed -i 's/europe\.pool\.ntp\.org/youradhere.localntp/g' ${IMG_DIR}/usr/lib/libmziot.so
	sed -i 's/asia\.pool\.ntp\.org/callisto.localntp/g' ${IMG_DIR}/usr/lib/libmziot.so
	sed -i 's/time\.windows\.com/jupiter.localntp/g' ${IMG_DIR}/usr/lib/libmziot.so
	sed -i 's/cn\.pool\.ntp\.org/saturn.localntp/g' ${IMG_DIR}/usr/lib/libmziot.so
	sed -i 's/ntp\.tencent\.com/uranus.localntp/g' ${IMG_DIR}/usr/lib/libmziot.so
	sed -i 's/time\.google\.com/phobos.localntp/g' ${IMG_DIR}/usr/lib/libmziot.so
	sed -i 's/ntp\.ntsc\.ac\.cn/pluto.localntp/g' ${IMG_DIR}/usr/lib/libmziot.so
	sed -i 's/ntp\.aliyun\.com/venus.localntp/g' ${IMG_DIR}/usr/lib/libmziot.so
	sed -i 's/pool\.ntp\.org/sol.localntp/g' ${IMG_DIR}/usr/lib/libmziot.so

	sed -i 's/www\.baidu\.com/127.000.000.1/g' ${IMG_DIR}/usr/lib/libmziot.so
	sed -i 's/www\.google\.com/127.000.000.01/g' ${IMG_DIR}/usr/lib/libmziot.so

	sed -i 's/www\.baidu\.com/127.000.000.1/g' ${IMG_DIR}/usr/bin/iot_node
	sed -i 's/www\.google\.com/127.000.000.01/g' ${IMG_DIR}/usr/bin/iot_node
	sed -i 's/www\.baidu\.com/127.000.000.1/g' ${IMG_DIR}/usr/bin/iot_node_msmart
	sed -i 's/www\.google\.com/127.000.000.01/g' ${IMG_DIR}/usr/bin/iot_node_msmart

	sed -i 's/api\.ipify\.org/127.000.13.37/g' ${IMG_DIR}/usr/bin/iot_node
	sed -i 's/api\.ipify\.org/127.000.13.37/g' ${IMG_DIR}/usr/bin/iot_node_msmart
	sed -i 's/api\.ipify\.cn/127.00.13.37/g' ${IMG_DIR}/usr/bin/iot_node
	sed -i 's/api\.ipify\.cn/127.00.13.37/g' ${IMG_DIR}/usr/bin/iot_node_msmart



	echo "Applying patches..."
	if [ -d "${BASE_DIR}/patches" ]; then
	    if ls "${BASE_DIR}/patches"/*.patch 1> /dev/null 2>&1; then
	        for patch in "${BASE_DIR}/patches"/*.patch; do
	            echo "Applying $patch"
	            patch -p1 --ignore-whitespace -d "${IMG_DIR}" < "$patch"
	        done
	    else
	        echo "No patch files found in ${BASE_DIR}/patches/"
	    fi
	fi

	echo "Applying binary patches..."
	BINARY_PATCH_DIR="${BASE_DIR}/binary_patches"
	if [ -d "${BINARY_PATCH_DIR}" ]; then
	    find -L "${BINARY_PATCH_DIR}" -type f -name "*.bsdiff" | while read -r patch_file; do
	        relative_patch_path=${patch_file#"$BINARY_PATCH_DIR/"}
        	relative_target_path=${relative_patch_path%.bsdiff}
	        target_file="${IMG_DIR}/${relative_target_path}"

	        if [ -f "${target_file}" ]; then
        	    echo "Applying binary patch to ${relative_target_path}"
		    original_mode=$(stat -c %a "${target_file}")

	            if bspatch "${target_file}" "${target_file}.patched" "${patch_file}"; then
			install -m "${original_mode}" "${target_file}.patched" "${target_file}"
			rm -f "${target_file}.patched"
		    else
			echo "ERROR: Failed to apply patch ${patch_file}"
		    fi
        	else
		    echo "WARNING: Original file for patch not found: ${target_file}"
        	fi
    	    done
	else
	    echo "No binary patch directory found. Skipping."
	fi

        echo "Copying custom files..."
        FILES_DIR="${BASE_DIR}/files"
        if [ -d "${FILES_DIR}" ]; then
            if [ -n "$(ls -A ${FILES_DIR})" ]; then
                echo "Copying files from ${FILES_DIR} to ${IMG_DIR}"
                cp -av "${FILES_DIR}/." "${IMG_DIR}/"
            else
                echo "Custom files directory is empty. Skipping."
            fi
        else
            echo "No custom files directory found. Skipping."
        fi
fi

if [ -f ${FLAG_DIR}/tools ]; then
    echo "installing tools"
    cp -r ${FEATURES_DIR}/midea_tools/root-dir/* ${IMG_DIR}/
fi



touch ${IMG_DIR}/build.txt
echo "built with dustbuilder (https://builder.dontvacuum.me)" > ${IMG_DIR}/build.txt
date -u +"%Y-%m-%dT%H:%M:%SZ"  >> ${IMG_DIR}/build.txt

echo "--------------"
echo "creating rootfs"
mksquashfs ${IMG_DIR}/ rootfs_tmp.img -noappend -root-owned -comp xz -b 256k -p '/dev d 755 0 0' -p '/dev/console c 600 0 0 5 1'
rm -rf ${IMG_DIR}
dd if=${BASE_DIR}/rootfs_tmp.img of=${BASE_DIR}/rootfs.img bs=128k conv=sync
rm ${BASE_DIR}/rootfs_tmp.img

if [ -f ${FLAG_DIR}/vanilla ]; then
	echo "vanilla mode, purge rootfs, use template"
	rm ${BASE_DIR}/rootfs.img
	cp ${FLAG_DIR}/rootfs.img.template ${BASE_DIR}/rootfs.img
fi

echo "computing md5"
md5sum ${BASE_DIR}/rootfs.img > ${BASE_DIR}/rootfs_md5sum


INSTALLER_DEVICE_TYPE="invalid"
MIN_FW_VERSION="0"
if [ -f "${BASE_DIR}/minfwversion" ]; then
        MIN_FW_VERSION=$(cat "${BASE_DIR}/minfwversion" | tr -d '[:space:]')

        echo "Min FW Version: $MIN_FW_VERSION"
fi

if [ ${FRIENDLYDEVICETYPE} = "midea.j12" ]; then
        echo "J12 Ultra"
        INSTALLER_DEVICE_TYPE="v12_eureka"

	maximumsize=28000000 # partition size is 33554432
	minimumsize=23000000
elif [ ${FRIENDLYDEVICETYPE} = "midea.e20evoplus" ]; then
        echo "E20 Evo Plus"

	INSTALLER_DEVICE_TYPE="e20_evo_plus_eureka"

	maximumsize=28000000 # partition size is 33554432
	minimumsize=23000000
elif [ ${FRIENDLYDEVICETYPE} = "midea.e20plus" ]; then
        echo "E20 Plus"

	INSTALLER_DEVICE_TYPE="e20s_plus"

	maximumsize=28000000 # partition size is 33554432
	minimumsize=23000000
else
	echo "all others" # TODO: proper partition size here
	maximumsize=28000000
	minimumsize=23000000
fi



actualsize=$(wc -c < ${BASE_DIR}/rootfs.img)
if [ "$actualsize" -gt "$maximumsize" ]; then
        echo "(!!!) rootfs.img looks to big. The size might exceed the available space on the flash. $actualsize > $maximumsize"
        echo "(!!!) rootfs.img looks to big. The size might exceed the available space on the flash. $actualsize > $maximumsize" > ${BASE_DIR}/output/error.txt
        echo ${FRIENDLYDEVICETYPE} >> ${BASE_DIR}/output/error.txt
        echo $actualsize >> ${BASE_DIR}/output/error.txt
        echo $maximumsize >> ${BASE_DIR}/output/error.txt
        exit 1
fi

if [ "$actualsize" -le "$minimumsize" ]; then
        echo "(!!!) rootfs.img looks to small. Maybe something went wrong with the image generation."
        echo "(!!!) rootfs.img looks to small. Maybe something went wrong with the image generation." > ${BASE_DIR}/output/error.txt
        echo ${FRIENDLYDEVICETYPE} >> ${BASE_DIR}/output/error.txt
        echo $actualsize >> ${BASE_DIR}/output/error.txt
        echo $maximumsize >> ${BASE_DIR}/output/error.txt
        exit 1
fi

md5sum ./*.img > ${BASE_DIR}/firmware.md5sum

echo "create installer package"
mkdir -p ${BASE_DIR}/rkimage
mkdir -p ${BASE_DIR}/rkimage/Image
cp ${BASE_DIR}/rootfs.img ${BASE_DIR}/rkimage/Image/rootfs.img
cp ${BASE_DIR}/boot.img ${BASE_DIR}/rkimage/Image/
mv ${BASE_DIR}/boot.bin ${BASE_DIR}/rkimage/
cp ${BASE_DIR}/package-file ${BASE_DIR}/rkimage/Image/
mv ${BASE_DIR}/parameter.txt ${BASE_DIR}/rkimage/Image/
cp ${BASE_DIR}/package-file ${BASE_DIR}/rkimage/Image/
sed -i "s/Image\///" ${BASE_DIR}/rkimage/Image/package-file


./tools/rk/afptool -pack ${BASE_DIR}/rkimage/Image ${BASE_DIR}/rkimage/firmware.img
./tools/rk/rkImageMaker -RK3308 ${BASE_DIR}/rkimage/boot.bin ${BASE_DIR}/rkimage/firmware.img ${BASE_DIR}/midea_rk_update_ota.img -os_type:androidos


sed -e "s#CHANGEDEVICEMODELCHANGE#${INSTALLER_DEVICE_TYPE}#g" \
    -e "s#CHANGEMINVERSIONCHANGE#${MIN_FW_VERSION}#g" \
    "${FEATURES_DIR}/midea/install.sh" > "${BASE_DIR}/install.sh"


md5sum ${BASE_DIR}/install.sh ${BASE_DIR}/valetudo ${BASE_DIR}/midea_rk_update_ota.img ${BASE_DIR}/submodules/* > ${BASE_DIR}/updatepackage.md5sum


tar --ignore-failed-read -czf ${BASE_DIR}/output/${DEVICETYPE}_fw.tar.gz ${BASE_DIR}/midea_rk_update_ota.img ${BASE_DIR}/install.sh ${BASE_DIR}/submodules ${BASE_DIR}/updatepackage.md5sum ${BASE_DIR}/valetudo





md5sum ${BASE_DIR}/output/${DEVICETYPE}_fw.tar.gz > ${BASE_DIR}/output/md5.txt
echo "${DEVICETYPE}_fw.tar.gz" > ${BASE_DIR}/filename.txt
touch ${BASE_DIR}/server.txt

if [ -f ${FLAG_DIR}/diff ]; then
    echo "--------------"
	echo "unpack original"
	unsquashfs -d ${BASE_DIR}/original ${BASE_DIR}/rootfs.img.template
	rm -rf ${BASE_DIR}/original/dev
	echo "unpack modified"
	unsquashfs -d ${BASE_DIR}/modified ${BASE_DIR}/rootfs.img
	rm -rf ${BASE_DIR}/modified/dev
	
	/usr/bin/git diff --no-index ${BASE_DIR}/original/ ${BASE_DIR}/modified/ > ${BASE_DIR}/output/diff.txt
	rm -rf ${BASE_DIR}/original
	rm -rf ${BASE_DIR}/modified

fi

touch ${BASE_DIR}/output/done
