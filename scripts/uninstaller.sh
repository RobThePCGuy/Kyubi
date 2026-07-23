#MAGISK
############################################
# Kyubi Uninstaller (system-mode only)
############################################

##############
# Preparation
##############

# Default permissions
umask 022

OUTFD=$2
COMMONDIR=$INSTALLER/assets

if [ ! -f $COMMONDIR/util_functions.sh ]; then
  echo "! Unable to extract zip file!"
  exit 1
fi

# Load utility functions
. $COMMONDIR/util_functions.sh

setup_flashable

############
# Detection
############

if echo $MAGISK_VER | grep -q '\.'; then
  PRETTY_VER=$MAGISK_VER
else
  PRETTY_VER="$MAGISK_VER($MAGISK_VER_CODE)"
fi
print_title "Kyubi $PRETTY_VER Uninstaller"

is_mounted /data || mount /data || abort "! Unable to mount /data, please uninstall with the Kyubi app"
mount_partitions
check_data
$DATA_DE || abort "! Cannot access /data, please uninstall with the Kyubi app"
get_flags

backup_restore(){
test -f "${1}.gz" || { test -f "$1" && gzip -k "$1"; }
test -f "${1}.gz" && { rm -rf "$1" && gzip -kdf "${1}.gz"; } || return 1
}

# Detect version and architecture
api_level_arch_detect

ui_print "- Device platform: $ABI"

if ( [ -z "$(grep_prop SHA1 "$MAGISKTMP/.magisk/config")" ] && $BOOTMODE ) || [ "$(grep_prop SYSTEMMODE /system/etc/init/magisk/config)" == "true" ]; then

# Use kernel trick to clean up mirrors automatically when installer completed
MIRRORDIR="/proc/$$/attr"
ROOTDIR="$MIRRORDIR/system_root"
SYSTEMDIR="$MIRRORDIR/system"
VENDORDIR="$MIRRORDIR/vendor"
ODM_DIR="$MIRRORDIR/odm"

if $BOOTMODE; then
    # setup mirrors to get the original content
    mount -t tmpfs -o 'mode=0755' tmpfs "$MIRRORDIR" || return 1
    if is_rootfs; then
        ROOTDIR=/
        mkdir "$SYSTEMDIR"
        force_bind_mount "/system" "$SYSTEMDIR" || return 1
    else
        mkdir "$ROOTDIR"
        force_bind_mount "/" "$ROOTDIR" || return 1
        if mountpoint -q /system; then
            mkdir "$SYSTEMDIR"
            force_bind_mount "/system" "$SYSTEMDIR" || return 1
        else
            ln -fs ./system_root/system "$SYSTEMDIR"
        fi
    fi

    # check if /vendor is seperated fs
    if mountpoint -q /vendor; then
        mkdir "$VENDORDIR"
        force_bind_mount "/vendor" "$VENDORDIR" || return 1
    else
        ln -fs ./system/vendor "$VENDORDIR"
    fi

    # check if /odm is seperated fs
    if mountpoint -q /odm; then
        mkdir "$ODM_DIR"
        force_bind_mount "/odm" "$ODM_DIR" || return 1
    else
        ln -fs ./system_root/odm "$ODM_DIR"
    fi
else
    MIRRORDIR="/"
    ROOTDIR="$MIRRORDIR/system_root"
    SYSTEMDIR="$MIRRORDIR/system"
    VENDORDIR="$MIRRORDIR/vendor"
    ODM_DIR="$MIRRORDIR/odm"
fi

ui_print "--- Uninstall Kyubi in system partition"

blockdev --setrw /dev/block/mapper/system$SLOT 2>/dev/null
mount -o rw,remount /system || mount -o rw,remount /
mount -o rw,remount /system_root
mount -o rw,remount /vendor
mount -o rw,remount /odm

for file in /vendor/etc/selinux/precompiled_sepolicy /odm/etc/selinux/precompiled_sepolicy /system/etc/selinux/precompiled_sepolicy /system_root/sepolicy /system_root/sepolicy_debug /system_root/sepolicy.unlocked; do
    if [ -f "$MIRRORDIR$file" ]; then
        sepol="$file"
        break
    fi
done

if [ ! -z "$sepol" ]; then
    ui_print "- Restore sepolicy patch"
    backup_restore "$MIRRORDIR$sepol" && rm -rf "$MIRRORDIR$sepol".gz
fi


ui_print "- Removing Kyubi binaries"
rm -rf $MIRRORDIR/system/etc/init/*magisk* $MIRRORDIR/system/system/etc/init/*magisk* $MIRRORDIR/system_root/system/etc/init/*magisk* \
$MIRRORDIR/system/xbin/magisk $MIRRORDIR/system/xbin/.magisk || abort "! Cannot uninstall"

backup_restore "$MIRRORDIR/system/etc/init/bootanim.rc" && rm -rf "$MIRRORDIR/system/etc/init/bootanim.rc.gz"

else

abort "! No system-mode Kyubi installation found (Kyubi is system-mode only)"

fi

if $BOOTMODE; then
  ui_print "- Removing modules"
  magisk --remove-modules -n
fi

ui_print "- Removing Kyubi files"
rm -rf \
/cache/*magisk* /cache/unblock /data/*magisk* /data/cache/*magisk* /data/property/*magisk* \
/data/Magisk.apk /data/busybox /data/adb/*magisk* \
/data/adb/post-fs-data.d /data/adb/service.d /data/adb/modules* \
/data/unencrypted/magisk /metadata/magisk /persist/magisk /mnt/vendor/persist/magisk

cd /

ui_print "********************************************"
ui_print " The Kyubi app will uninstall itself, and"
ui_print " the device will reboot after a few seconds"
ui_print "********************************************"
sleep 8
if ! /system/bin/reboot; then
  # Reboot failed to even start (rather than silently not completing, which
  # this shell can't observe either way) -- don't leave the partitions we
  # remounted read-write above sitting open with nothing to close them.
  ui_print "! Reboot failed, remounting system partitions read-only"
  mount -o ro,remount /system_root 2>/dev/null
  mount -o ro,remount /system 2>/dev/null
  mount -o ro,remount /vendor 2>/dev/null
  mount -o ro,remount /odm 2>/dev/null
fi

rm -rf $TMPDIR
exit 0
