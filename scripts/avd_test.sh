#!/usr/bin/env bash

emu="$ANDROID_SDK_ROOT/emulator/emulator"
avd="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/avdmanager"
sdk="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
emu_args_base='-no-window -no-audio -no-boot-anim -gpu swiftshader_indirect -read-only -no-snapshot -show-kernel -memory $memory'
boot_timeout=600
emu_pid=

export PATH="$PATH:$ANDROID_SDK_ROOT/platform-tools"
export ANDROID_SDK_HOME=$ANDROID_SDK_ROOT

# We test at least these API levels for the following reason

# API 23: legacy rootfs w/o Treble
# API 26: legacy rootfs with Treble
# API 28: legacy system-as-root
# API 29: 2 Stage Init
# API 35: latest Android

api_list='23 26 28 29 35'

atd_min_api=30
atd_max_api=35
huge_ram_min_api=26

print_title() {
  echo -e "\n\033[44;39m${1}\033[0m\n"
}

print_error() {
  echo -e "\n\033[41;39m${1}\033[0m\n"
}

cleanup() {
  print_error "! An error occurred when testing $pkg"

  # Only restore the current API being tested, if variables are set
  if [ -n "$ramdisk" ] && [ -n "$features" ]; then
    restore_avd
  fi

  # Try to delete the test AVD, ignore errors if it doesn't exist
  "$avd" delete avd -n test 2>/dev/null || true
  pkill -INT -P $$
  wait
  trap - EXIT
  exit 1
}

wait_for_bootanim() {
  adb wait-for-device
  while true; do
    local result="$(adb exec-out getprop init.svc.bootanim)"
    if [ $? -ne 0 ]; then
      exit 1
    elif [ "$result" = "stopped" ]; then
      break
    fi
    sleep 2
  done
}

wait_for_boot() {
  adb wait-for-device
  while true; do
    local result="$(adb exec-out getprop sys.boot_completed)"
    if [ $? -ne 0 ]; then
      exit 1
    elif [ "$result" = "1" ]; then
      break
    fi
    sleep 2
  done
}

set_api_env() {
  local memory
  local type='default'
  if [ $1 -ge $atd_min_api -a $1 -le $atd_max_api ]; then
    # Use the lightweight ATD images if possible
    type='aosp_atd'
  fi
  # Old Linux kernels will not boot with memory larger than 3GB
  if [ $1 -lt $huge_ram_min_api ]; then
    memory=3072
  else
    memory=8192
  fi
  eval emu_args=\"$emu_args_base\"
  pkg="system-images;android-$1;$type;$arch"
  local img_dir="$ANDROID_SDK_ROOT/system-images/android-$1/$type/$arch"
  ramdisk="$img_dir/ramdisk.img"
  features="$img_dir/advancedFeatures.ini"
}

restore_avd() {
  if [ -f "${ramdisk}.bak" ]; then
    cp "${ramdisk}.bak" "$ramdisk" || echo "Warning: Failed to restore $ramdisk"
  fi
  if [ -f "${features}.bak" ]; then
    cp "${features}.bak" "$features" || echo "Warning: Failed to restore $features"
  fi
}

wait_emu() {
  local wait_fn=$1
  local which_pid

  timeout $boot_timeout bash -c $wait_fn &
  local wait_pid=$!

  # Handle the case when emulator dies earlier than timeout
  wait -p which_pid -n $emu_pid $wait_pid
  [ $which_pid -eq $wait_pid ]
}

run_content_cmd() {
  while true; do
    local out=$(adb shell echo "'content call --uri content://io.github.huskydg.magisk.provider --method $1'" \| /system/xbin/su | tee /dev/fd/2)
    if ! grep -q 'Bundle\[' <<< "$out"; then
      # The call failed, wait a while and retry later
      sleep 30
    else
      grep -q 'result=true' <<< "$out"
      return $?
    fi
  done
}

test_emu() {
  local variant=$1
  local api=$2

  print_title "* Testing $pkg ($variant)"

  "$emu" @test $emu_args &
  emu_pid=$!
  wait_emu wait_for_boot

  adb shell magisk -v

  # Install the Magisk app
  adb install -r -g out/app-${variant}.apk

  # Use the app to run setup and reboot
  run_content_cmd setup

  adb reboot
  wait_emu wait_for_boot

  # Run app tests
  run_content_cmd test
  adb shell echo 'su -c id' \| /system/xbin/su 2000 | tee /dev/fd/2 | grep -q 'uid=0'

}


run_test() {
  local api=$1

  set_api_env $api

  # Setup emulator
  "$sdk" --channel=3 $pkg
  echo no | "$avd" create avd -f -n test -k $pkg

  # Launch stock emulator
  print_title "* Launching $pkg"
  restore_avd
  "$emu" @test $emu_args &
  emu_pid=$!
  if ! wait_emu wait_for_bootanim; then
    print_error "Failed to boot emulator for $pkg"
    return 1
  fi

  # Patch and test debug build
  if ! ./build.py avd_patch -s "$ramdisk"; then
    print_error "Failed to patch ramdisk for debug build"
    kill -INT $emu_pid 2>/dev/null || true
    wait $emu_pid 2>/dev/null || true
    return 1
  fi
  kill -INT $emu_pid
  wait $emu_pid
  if ! test_emu debug $api; then
    print_error "Debug build test failed for $pkg"
    return 1
  fi

  # Re-patch and test release build
  if ! ./build.py -r avd_patch -s "$ramdisk"; then
    print_error "Failed to patch ramdisk for release build"
    kill -INT $emu_pid 2>/dev/null || true
    wait $emu_pid 2>/dev/null || true
    return 1
  fi
  kill -INT $emu_pid
  wait $emu_pid
  if ! test_emu release $api; then
    print_error "Release build test failed for $pkg"
    return 1
  fi

  # Cleanup
  kill -INT $emu_pid 2>/dev/null || true
  wait $emu_pid 2>/dev/null || true
  restore_avd
}

trap cleanup EXIT

export -f wait_for_boot
export -f wait_for_bootanim

set -xe

case $(uname -m) in
  'arm64'|'aarch64')
    arch=arm64-v8a
    ;;
  *)
    arch=x86_64
    ;;
esac

yes | "$sdk" --licenses > /dev/null
"$sdk" --channel=3 tools platform-tools emulator

if [ -n "$1" ]; then
  if ! run_test $1; then
    print_error "Test failed for API $1"
    exit 1
  fi
else
  for api in $api_list; do
    if ! run_test $api; then
      print_error "Test failed for API $api"
      exit 1
    fi
  done
fi

"$avd" delete avd -n test 2>/dev/null || true

trap - EXIT