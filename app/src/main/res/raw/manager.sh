##################################
# Magisk app internal scripts
##################################

run_delay() {
  (sleep $1; $2)&
}

env_check() {
  # Check only the binaries Kyubi actually ships, so a healthy offline install
  # reports env-OK instead of nagging "additional setup" on every launch.
  for file in busybox magiskinit util_functions.sh; do
    [ -f "$MAGISKBIN/$file" ] || return 1
  done
  if [ "$2" -ge 25000 ]; then
    [ -f "$MAGISKBIN/magiskpolicy" ] || return 1
  fi
  grep -xqF "MAGISK_VER='$1'" "$MAGISKBIN/util_functions.sh" || return 3
  grep -xqF "MAGISK_VER_CODE=$2" "$MAGISKBIN/util_functions.sh" || return 3
  return 0
}

cp_readlink() {
  if [ -z $2 ]; then
    cd $1 || return 1
  else
    cp -af $1/. $2 || return 1
    cd $2 || return 1
  fi
  for file in *; do
    if [ -L $file ]; then
      local full
      full=$(readlink -f $file) || return 1
      rm $file || return 1
      cp -af $full $file || return 1
    fi
  done
  chmod -R 755 . || return 1
  cd /
}

fix_env() {
  # Cleanup and make dirs -- fail fast so a partial/empty $MAGISKBIN can never be
  # reported as a successful install.
  rm -rf $MAGISKBIN/* || return 1
  mkdir -p $MAGISKBIN || return 1
  chmod 700 $NVBASE || return 1
  cp_readlink $1 $MAGISKBIN || return 1
  rm -rf $1 || return 1
  chown -R 0:0 $MAGISKBIN || return 1
}

run_uninstaller() {
  rm -rf /dev/tmp
  mkdir -p /dev/tmp/install
  unzip -o "$1" "assets/*" "lib/*" -d /dev/tmp/install
  INSTALLER=/dev/tmp/install sh /dev/tmp/install/assets/uninstaller.sh dummy 1 "$1"
}

add_hosts_module() {
  # Do not touch existing hosts module
  [ -d $NVBASE/modules/hosts ] && return
  cd $NVBASE/modules
  mkdir -p hosts/system/etc
  cat << EOF > hosts/module.prop
id=hosts
name=Systemless Hosts
version=1.0
versionCode=1
author=Magisk
description=Magisk app built-in systemless hosts module
EOF
  magisk --clone /system/etc/hosts hosts/system/etc/hosts
  touch hosts/update
  cd /
}

adb_pm_install() {
  local tmp=/data/local/tmp/temp.apk
  cp -f "$1" $tmp
  chmod 644 $tmp
  su 2000 -c pm install -g $tmp || pm install -g $tmp || su 1000 -c pm install -g $tmp
  local res=$?
  rm -f $tmp
  if [ $res = 0 ]; then
    ( magisk magiskhide sulist && magisk magiskhide add "$2" ) &
    appops set "$2" REQUEST_INSTALL_PACKAGES allow
  fi
  return $res
}

check_encryption() {
  if $ISENCRYPTED; then
    if [ $SDK_INT -lt 24 ]; then
      CRYPTOTYPE="block"
    else
      # First see what the system tells us
      CRYPTOTYPE=$(getprop ro.crypto.type)
      if [ -z $CRYPTOTYPE ]; then
        # If not mounting through device mapper, we are FBE
        if grep ' /data ' /proc/mounts | grep -qv 'dm-'; then
          CRYPTOTYPE="file"
        else
          # We are either FDE or metadata encryption (which is also FBE)
          CRYPTOTYPE="block"
          grep -q ' /metadata ' /proc/mounts && CRYPTOTYPE="file"
        fi
      fi
    fi
  else
    CRYPTOTYPE="N/A"
  fi
}

run_action() {
  local MODID="$1"
  cd "/data/adb/modules/$MODID"
  sh ./action.sh
  local RES=$?
  cd /
  return $RES
}

##########################
# Non-root util_functions
##########################

get_flags() {
  ISENCRYPTED=false
  [ "$(getprop ro.crypto.state)" = "encrypted" ] && ISENCRYPTED=true
}

run_migrations() { return; }

grep_prop() { return; }

get_sulist_status(){
    SULISTMODE=false
    if magisk magiskhide sulist; then
        SULISTMODE=true
    fi
}

##############################
# Magisk Delta Custom install script
##############################

# define
MAGISKSYSTEMDIR="/system/etc/init/magisk"

random_str(){
local FROM
local TO
FROM="$1"; TO="$2"
tr -dc A-Za-z0-9 </dev/urandom | head -c $(($FROM+$(($RANDOM%$(($TO-$FROM+1))))))
}

magiskrc(){
local MAGISKTMP="$1"

# use "magisk --auto-selinux" to automatically switching selinux state

cat <<EOF
on post-fs-data
    start logd
    exec u:r:su:s0 root root -- $MAGISKSYSTEMDIR/magiskpolicy --live --magisk
    exec u:r:magisk:s0 root root -- $MAGISKSYSTEMDIR/magiskpolicy --live --magisk
    exec u:r:update_engine:s0 root root -- $MAGISKSYSTEMDIR/magiskpolicy --live --magisk
    exec u:r:su:s0 root root -- $MAGISKSYSTEMDIR/$magisk_name --auto-selinux --setup-sbin $MAGISKSYSTEMDIR $MAGISKTMP
    exec u:r:su:s0 root root -- $MAGISKTMP/magisk --auto-selinux --post-fs-data
on nonencrypted
    exec u:r:su:s0 root root -- $MAGISKTMP/magisk --auto-selinux --service
on property:vold.decrypt=trigger_restart_framework
    exec u:r:su:s0 root root -- $MAGISKTMP/magisk --auto-selinux --service
on property:sys.boot_completed=1
    mkdir /data/adb/magisk 755
    exec u:r:su:s0 root root -- $MAGISKTMP/magisk --auto-selinux --boot-complete
   
on property:init.svc.zygote=restarting
    exec u:r:su:s0 root root -- $MAGISKTMP/magisk --auto-selinux --zygote-restart
   
on property:init.svc.zygote=stopped
    exec u:r:su:s0 root root -- $MAGISKTMP/magisk --auto-selinux --zygote-restart
EOF
}

remount_check(){
    local mode="$1"
    local part="$(realpath "$2")"
    local ignore_not_exist="$3"
    local i
    if ! grep -q " $part " /proc/mounts && [ ! -z "$ignore_not_exist" ]; then
        return "$ignore_not_exist"
    fi
    mount -o "$mode,remount" "$part"
    local IFS=$'\t\n ,'
    for i in $(cat /proc/mounts | grep " $part " | awk '{ print $4 }'); do
        test "$i" == "$mode" && return 0
    done
    return 1
}

backup_restore(){
    # if gz is not found and orig file is found, backup to gz
    if [ ! -f "${1}.gz" ] && [ -f "$1" ]; then
        gzip -k "$1" && return 0
    elif [ -f "${1}.gz" ]; then
    # if gz found, restore from gz
        rm -rf "$1" && gzip -kdf "${1}.gz" && return 0
    fi
    return 1
}

restore_from_bak(){
    backup_restore "$1" && rm -rf "${1}.gz"
}

cleanup_system_installation(){
    local mirror="${1:-$MIRRORDIR}"
    rm -rf "$mirror${MAGISKSYSTEMDIR}"
    rm -rf "$mirror${MAGISKSYSTEMDIR}.rc"
    backup_restore "$mirror/system/etc/init/bootanim.rc" \
    && rm -rf "$mirror/system/etc/init/bootanim.rc.gz"
    if [ -e "$mirror${MAGISKSYSTEMDIR}" ] || [ -e "$mirror${MAGISKSYSTEMDIR}.rc" ]; then
        return 1
    fi
}

restore_system_sepolicy(){
    local mirror="${1:-$MIRRORDIR}" file
    for file in /vendor/etc/selinux/precompiled_sepolicy /odm/etc/selinux/precompiled_sepolicy /system/etc/selinux/precompiled_sepolicy /system_root/sepolicy /system_root/sepolicy_debug /system_root/sepolicy.unlocked; do
        if [ -f "$mirror$file.gz" ]; then
            ui_print "- Restore sepolicy patch"
            restore_from_bak "$mirror$file" || return 1
            break
        fi
    done
}

installer_cleanup(){
    umount -l "/proc/$$/attr"
    mount -o ro,remount /
}

direct_install_system(){
    print_title "Kyubi (System Mode)"
    print_title "Magisk Delta lineage · powered by Magisk"
    api_level_arch_detect
    local INSTALLDIR="$1"

    ui_print "- Remount system partition as read-write"
    # Use kernel trick to clean up mirrors automatically when installer completed
    local MIRRORDIR="/proc/$$/attr" ROOTDIR SYSTEMDIR VENDORDIR

    ROOTDIR="$MIRRORDIR/system_root"
    SYSTEMDIR="$MIRRORDIR/system"
    VENDORDIR="$MIRRORDIR/vendor"
    ODM_DIR="$MIRRORDIR/odm"

    local MAGISKTMP_TO_INSTALL=/sbin

    if $BOOTMODE; then
        umount -l "/proc/$$/attr"
        # setup mirrors to get the original content
        mount -t tmpfs -o 'mode=0755' tmpfs "$MIRRORDIR" || return 1
        if is_rootfs; then
            ROOTDIR=/
            force_bind_mount "/" "$ROOTDIR" || return 1
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

        # we are modifying system directly so we need to create /sbin if it does not exist
        if [ ! -d "$ROOTDIR"/sbin ]; then
            rm -rf "$ROOTDIR"/sbin
            mkdir "$ROOTDIR"/sbin
            if [ ! -d "$ROOTDIR"/sbin ]; then
                ui_print "! Can't create tmpfs path /sbin"
                return 1;
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
        local MIRRORDIR="/" ROOTDIR SYSTEMDIR VENDORDIR
        ROOTDIR="$MIRRORDIR/system_root"
        SYSTEMDIR="$MIRRORDIR/system"
        VENDORDIR="$MIRRORDIR/vendor"
        ODM_DIR="$MIRRORDIR/odm"
        ui_print "- Mount system partitions as read-write..."
        remount_check rw "$ROOTDIR" 0 || { warn_system_ro; return 1; }
        remount_check rw "$SYSTEMDIR" 0 || { warn_system_ro; return 1; }
        remount_check rw "$VENDORDIR" 0 || { warn_system_ro; return 1; }
        remount_check rw "$ODM_DIR" 0 || { warn_system_ro; return 1; }

        # we are modifying system directly so we need to create /sbin if it does not exist
        if [ -d "$ROOTDIR" ] && [ ! -d "$ROOTDIR"/sbin ]; then
            rm -rf "$ROOTDIR"/sbin
            mkdir "$ROOTDIR"/sbin
            if [ ! -d "$ROOTDIR"/sbin ]; then
                ui_print "! Can't create tmpfs path /sbin"
                return 1;
            fi
        fi

    fi


    ui_print "- Cleaning up enviroment..."
    {
        local checkfile="$MIRRORDIR/system/.check_$(random_str 10 20)"
        # test write, need atleast 20mb
        dd if=/dev/zero of="$checkfile" bs=1024 count=20000 || \
            { rm -rf "$checkfile"; ui_print "! Insufficient free space or system write protection"; return 1; }
        rm -rf "$checkfile"
    }
    cleanup_system_installation || return 1

    local magisk_applet=magisk32 magisk_name=magisk32
    if [ "$IS64BIT" == true ]; then
        magisk_name=magisk64
        magisk_applet="magisk32 magisk64"
    fi

    ui_print "- Copy files to system partition"
    mkdir -p "$MIRRORDIR$MAGISKSYSTEMDIR" || return 1
    for magisk in $magisk_applet magiskpolicy magiskinit stub.apk; do
        cat "$INSTALLDIR/$magisk" >"$MIRRORDIR$MAGISKSYSTEMDIR/$magisk" || { ui_print "! Unable to write Magisk binaries to system"; return 1; }
    done
    echo -e "SYSTEMMODE=true\nRECOVERYMODE=false" >"$MIRRORDIR$MAGISKSYSTEMDIR/config" || { ui_print "! Unable to write Magisk config"; return 1; }
    chcon -R u:object_r:system_file:s0 "$MIRRORDIR$MAGISKSYSTEMDIR" || { ui_print "! Unable to set SELinux context on Magisk files"; return 1; }
    chmod -R 700 "$MIRRORDIR$MAGISKSYSTEMDIR" || { ui_print "! Unable to set permissions on Magisk files"; return 1; }

    if [ "$API" -gt 24 ]; then

        # test live patch
        {
            if $BOOTMODE; then
                ui_print "- Check if kernel supports dynamic SELinux Policy patch"
                if [ -d /sys/fs/selinux ] && ! "$INSTALLDIR/magiskpolicy" --live "permissive su" &>/dev/null; then
                    ui_print "! Kernel does not support dynamic SELinux Policy patch"
                    return 1
                fi
            else
                ui_print "W: It's impossible to check kernel compatible in recovery mode"
                ui_print "W: Please make sure your kernel can dynamic patch SELinux Policy"
            fi
            if ! is_rootfs; then
              {
                ui_print "- Patch sepolicy file"
                local sepol file
                for file in /vendor/etc/selinux/precompiled_sepolicy /odm/etc/selinux/precompiled_sepolicy /system/etc/selinux/precompiled_sepolicy /system_root/sepolicy /system_root/sepolicy_debug /system_root/sepolicy.unlocked; do
                    if [ -f "$MIRRORDIR$file" ]; then
                        sepol="$file"
                        break
                    fi
                done
                if [ -z "$sepol" ]; then
                    ui_print "! Cannot find sepolicy file"
                    return 1
                else
                    ui_print "- Target sepolicy is $sepol"
                    backup_restore "$MIRRORDIR$sepol" || { ui_print "! Backup failed"; return 1; }
                    # copy file to cache
                    cp -af "$MIRRORDIR$sepol" "$INSTALLDIR/sepol.in"
                    if ! "$INSTALLDIR/magiskinit" --patch-sepol "$INSTALLDIR/sepol.in" "$INSTALLDIR/sepol.out" || ! cp -af "$INSTALLDIR/sepol.out" "$MIRRORDIR$sepol"; then
                        ui_print "! Unable to patch sepolicy file"
                        restore_from_bak "$MIRRORDIR$sepol"
                        return 1
                    fi
                    ui_print "- Patching sepolicy file success!"
                fi
              }
            fi
        }
        ui_print "- Add init boot script"
        {
            hijackrc="$MIRRORDIR/system/etc/init/magisk.rc" 
            if [ -f "$MIRRORDIR/system/etc/init/bootanim.rc" ]; then
                backup_restore "$MIRRORDIR/system/etc/init/bootanim.rc" && hijackrc="$MIRRORDIR/system/etc/init/bootanim.rc"
            fi
        }
        echo "$(magiskrc "$MAGISKTMP_TO_INSTALL")" >>"$hijackrc" || return 1
    fi

    ui_print "[*] Reflash your ROM if your ROM is unable to start"
    ui_print "    and do not use this method to install Magisk" 

    true
    return 0
}



xdirect_install_system() {
  # Keep the writable mirror mounted until every step commits, so rollback can
  # restore both the original policy and init files after any later failure.
  local mirror="/proc/$$/attr"
  direct_install_system "$@" || {
    restore_system_sepolicy "$mirror"
    cleanup_system_installation "$mirror"
    installer_cleanup
    return 1
  }
  fix_env "$1" || {
    restore_system_sepolicy "$mirror"
    cleanup_system_installation "$mirror"
    installer_cleanup
    return 1
  }
  run_migrations || {
    restore_system_sepolicy "$mirror"
    cleanup_system_installation "$mirror"
    installer_cleanup
    return 1
  }
  installer_cleanup
  return 0
}



#############
# Initialize
#############

app_init() {
  get_flags
  run_migrations
  SHA1=$(grep_prop SHA1 $MAGISKTMP/.magisk/config)
  check_encryption
  get_sulist_status
}

export BOOTMODE=true
