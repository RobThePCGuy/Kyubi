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
# Optional app-only argument. Standalone flashable use has no manager identity.
MANAGER_PACKAGE=$4

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

# Use the same fallback as installation on kernels without /proc attr (#58).
MIRRORDIR=/ MIRRORTMP=
if $BOOTMODE; then
    setup_installer_mirror || abort "! Unable to set up uninstaller mirror"
    # abort/exit must also detach the fallback; never recursively remove it.
    trap 'cleanup_installer_mirror' EXIT
fi
ROOTDIR="$MIRRORDIR/system_root"
SYSTEMDIR="$MIRRORDIR/system"
VENDORDIR="$MIRRORDIR/vendor"
ODM_DIR="$MIRRORDIR/odm"

if $BOOTMODE; then
    # setup mirrors to get the original content
    if is_rootfs; then
        ROOTDIR=/
        mkdir "$SYSTEMDIR"
        force_bind_mount "/system" "$SYSTEMDIR" || abort "! Unable to mirror /system"
    else
        mkdir "$ROOTDIR"
        force_bind_mount "/" "$ROOTDIR" || abort "! Unable to mirror system root"
        if mountpoint -q /system; then
            mkdir "$SYSTEMDIR"
            force_bind_mount "/system" "$SYSTEMDIR" || abort "! Unable to mirror /system"
        else
            ln -fs ./system_root/system "$SYSTEMDIR"
        fi
    fi

    # check if /vendor is seperated fs
    if mountpoint -q /vendor; then
        mkdir "$VENDORDIR"
        force_bind_mount "/vendor" "$VENDORDIR" || abort "! Unable to mirror /vendor"
    else
        ln -fs ./system/vendor "$VENDORDIR"
    fi

    # check if /odm is seperated fs
    if mountpoint -q /odm; then
        mkdir "$ODM_DIR"
        force_bind_mount "/odm" "$ODM_DIR" || abort "! Unable to mirror /odm"
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

# The installer creates /sbin on guests that have none. rmdir only removes it
# while empty, so a populated stock /sbin stays put.
rmdir "$ROOTDIR/sbin" 2>/dev/null

else

abort "! No system-mode Kyubi installation found (Kyubi is system-mode only)"

fi

if $BOOTMODE; then
  ui_print "- Removing modules"
  magisk --remove-modules -n || abort "! Unable to remove modules"
fi

ui_print "- Removing Kyubi files"
rm -rf \
/cache/*magisk* /cache/unblock /data/*magisk* /data/cache/*magisk* /data/property/*magisk* \
/data/Magisk.apk /data/busybox /data/adb/*magisk* \
/data/adb/post-fs-data.d /data/adb/service.d /data/adb/modules* \
/data/unencrypted/magisk /metadata/magisk /persist/magisk /mnt/vendor/persist/magisk \
  || abort "! Unable to remove Kyubi files"

cd /

# Release mirrors before reboot; keep the EXIT trap as an error-path guard.
cleanup_installer_mirror || abort "! Unable to clean up uninstaller mirror"
MIRRORDIR= MIRRORTMP=

rm -rf "$TMPDIR" || abort "! Unable to remove uninstaller temporary files"

# Package removal kills the app. Finish cleanup first and let this root shell
# own the remaining sequence, rather than depending on an app callback after
# reboot. Capture pm output so it is not written to the app's closed log pipe.
remount_system_ro() {
  # System-as-root guests mount the system disk at / (see the rw remount above).
  mount -o ro,remount / 2>/dev/null
  mount -o ro,remount /system_root 2>/dev/null
  mount -o ro,remount /system 2>/dev/null
  mount -o ro,remount /vendor 2>/dev/null
  mount -o ro,remount /odm 2>/dev/null
}

if [ -n "$MANAGER_PACKAGE" ]; then
  ui_print "- Removing manager package: $MANAGER_PACKAGE"
  PM_RESULT=$(/system/bin/pm uninstall "$MANAGER_PACKAGE") \
    || abort "! Unable to remove manager package: $PM_RESULT"
  [ "$PM_RESULT" = Success ] || abort "! Unable to remove manager package: $PM_RESULT"
  # No reboot from the app: on the emulators Kyubi targets an in-guest reboot
  # never returns (BlueStacks' player hangs, MEmu's kernel faults in shutdown).
  # The uninstall dialog told the user to close and reopen the emulator.
  remount_system_ro
  exit 0
fi

ui_print "- System cleanup complete"
sleep 8
if /system/bin/reboot; then
  exit 0
else
  REBOOT_RESULT=$?
  # Reboot failed to even start (rather than silently not completing, which
  # this shell can't observe either way) -- don't leave the partitions we
  # remounted read-write above sitting open with nothing to close them.
  ui_print "! Reboot failed, remounting system partitions read-only"
  remount_system_ro
  exit "$REBOOT_RESULT"
fi
