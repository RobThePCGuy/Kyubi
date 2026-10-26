#!/usr/bin/env python3
"""Run installer control flow with sandbox files and simulated mount operations.

No host mounts, root access, Android device or system files are used. This proves
shell behavior, not that an APK installs or boots on a particular emulator.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

MANAGER = Path(__file__).resolve().parents[1] / "app/src/main/res/raw/manager.sh"
UTIL = MANAGER.parents[5] / "scripts/util_functions.sh"


class SystemInstallTests(unittest.TestCase):
    def test_backing_device_retry(self):
        helpers = UTIL.read_text().split("remount_check(){", 1)[1]
        helpers = "remount_check(){" + helpers.split("setup_installer_mirror(){", 1)[0]
        for scenario in ("readonly", "writable", "unknown", "setrw_fail", "retry_fail", "bind_fail", "normal", "nonblock", "missing"):
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as case:
                root = Path(case)
                device = "tmpfs" if scenario == "nonblock" else "/dev/block/sda6"
                (root / "mounts").write_text("" if scenario == "missing" else f"{device} /mirror ext4 ro 0 0\n")
                source = helpers.replace("/proc/mounts", '"$CASE_ROOT/mounts"')
                # The fixture represents a block device without creating host devices.
                source = source.replace('[ -b "$device" ]', '[ "$device" = /dev/block/sda6 ]')
                harness = source + r'''
ui_print() { echo "$*"; }
warn_system_ro() { return 1; }
realpath() { echo "$1"; }
mount() {
  echo "mount $*"
  case "$2" in
    bind,private) [ "$SCENARIO" != bind_fail ]; return $? ;;
  esac
  if [ "$SCENARIO" = normal ] || { [ "$unlocked" = yes ] && [ "$SCENARIO" != retry_fail ]; }; then
    echo '/dev/block/sda6 /mirror ext4 rw 0 0' > "$CASE_ROOT/mounts"
    return 0
  fi
  return 1
}
blockdev() {
  echo "blockdev $*" >&2
  case "$1" in
    --getro)
      case "$SCENARIO" in writable) echo 0;; unknown) return 1;; *) echo 1;; esac ;;
    --setrw) [ "$SCENARIO" != setrw_fail ] || return 1; unlocked=yes ;;
  esac
}
force_bind_mount / /mirror
'''
                run = subprocess.run(["bash"], input=harness, text=True, capture_output=True,
                                     env=dict(os.environ, CASE_ROOT=root.as_posix(), SCENARIO=scenario))
                if scenario in ("readonly", "normal"):
                    self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                else:
                    self.assertNotEqual(run.returncode, 0, run.stdout + run.stderr)
                if scenario in ("readonly", "setrw_fail", "retry_fail"):
                    self.assertIn("blockdev --setrw /dev/block/sda6", run.stderr)
                else:
                    self.assertNotIn("--setrw", run.stderr)

    def run_case(self, *, proc=False, proc_mount=True, fallback_mount=True,
                 selinux=False, failure="", cleanup_failure=False,
                 context_ok=False, bootmode=True, uninstall=False):
        with tempfile.TemporaryDirectory() as case:
            root = Path(case)
            (root / "payload").mkdir()
            for name in ("magisk64", "magiskpolicy", "magiskinit", "stub.apk"):
                (root / "payload" / name).write_text("fixture")
            if proc:
                (root / "proc").mkdir()
            if selinux:
                (root / "enforce").touch()
                (root / "selinux").mkdir()
            (root / "recovery/system_root/sbin").mkdir(parents=True)
            (root / "recovery/system/etc/init").mkdir(parents=True)
            # Load the real shared helpers without running Android-only presets.
            helpers = UTIL.read_text().split("setup_installer_mirror(){", 1)[1]
            helpers = "setup_installer_mirror(){" + helpers.split("##########\n# Presets", 1)[0]
            source = (helpers + MANAGER.read_text()).replace("/proc/$$/attr", "$CASE_ROOT/proc")
            source = source.replace("/dev/kyubi-mirror.", "$CASE_ROOT/kyubi-mirror.")
            source = source.replace("/sys/fs/selinux/enforce", "$CASE_ROOT/enforce")
            source = source.replace("/sys/fs/selinux", "$CASE_ROOT/selinux")
            source = source.replace("MIRRORDIR=/\n", 'MIRRORDIR="$CASE_ROOT/recovery"\n')
            if uninstall:
                snippet = (UTIL.parent / "uninstaller.sh").read_text().split(
                    "# Use the same fallback", 1)[1].split('ui_print "--- Uninstall', 1)[0]
                source += '\nuninstall_setup() {\n# Use the same fallback' + snippet + '\n}\n'
            (root / "manager.sh").write_text(source)
            harness = r'''
. "$CASE_ROOT/manager.sh"
BOOTMODE="$CASE_BOOTMODE"
ui_print() { echo "$*"; }
abort() { echo "$*"; exit 1; }
print_title() { :; }
api_level_arch_detect() { API=30; $BOOTMODE || API=23; IS64BIT=true; }
is_rootfs() { return 1; }
mountpoint() { return 1; }
remount_check() { return 0; }
mount() {
  echo "mount $*" >> "$CASE_ROOT/events"
  if [ "$1" = -t ]; then
    local dest="${@: -1}"
    if [ "$dest" = "$CASE_ROOT/proc" ]; then
      [ "$PROC_MOUNT" = true ] && [ -d "$dest" ]
    else
      [ "$FALLBACK_MOUNT" = true ]
    fi
  else return 0; fi
}
umount() {
  echo "umount $*" >> "$CASE_ROOT/events"
  [ "$CLEANUP_FAILURE" != true ] || return 1
  # Simulate the backing directory becoming empty after tmpfs is detached.
  case "$2" in
    "$CASE_ROOT"/kyubi-mirror.*|"$CASE_ROOT"/proc)
      command rm -rf "$2/system_root" "$2/system" "$2/vendor" "$2/odm" ;;
  esac
  return 0
}
force_bind_mount() {
  echo "bind $*" >> "$CASE_ROOT/events"
  [ "$FAILURE" != bind ] || return 1
  if [ "$1" = / ]; then
    mkdir -p "$2/system/etc/init" "$2/sbin"
    if [ -f "$CASE_ROOT/enforce" ]; then
      echo policy > "$2/sepolicy"
    fi
  fi
}
dd() {
  [ "$FAILURE" != write ]
}
chcon() {
  echo chcon >> "$CASE_ROOT/events"
  [ "$CONTEXT_OK" = true ]
}
cp() {
  echo "cp $*" >> "$CASE_ROOT/events"
  command cp "$@"
}
random_str() { echo fixture; }
fix_env() {
  echo fix_env >> "$CASE_ROOT/events"
  [ "$FAILURE" != fix_env ]
}
run_migrations() {
  echo migrations >> "$CASE_ROOT/events"
  [ "$FAILURE" != migrations ]
}
restore_system_sepolicy() {
  echo "restore $1" >> "$CASE_ROOT/events"
}
cleanup_system_installation() {
  echo "rollback $1" >> "$CASE_ROOT/events"
  return 0
}
magiskrc() { echo 'on boot'; }
if [ "$UNINSTALL" = true ]; then
  uninstall_setup
else
  xdirect_install_system "$CASE_ROOT/payload"
fi
result=$?
echo "RESULT=$result"
exit "$result"
'''
            env = dict(os.environ, CASE_ROOT=case, PROC_MOUNT=str(proc_mount).lower(),
                       FALLBACK_MOUNT=str(fallback_mount).lower(), FAILURE=failure,
                       CLEANUP_FAILURE=str(cleanup_failure).lower(),
                       CASE_BOOTMODE=str(bootmode).lower(), UNINSTALL=str(uninstall).lower(),
                       CONTEXT_OK=str(context_ok).lower())
            run = subprocess.run(["bash"], input=harness, text=True,
                                 capture_output=True, env=env)
            events = (root / "events").read_text() if (root / "events").exists() else ""
            leftovers = list(root.glob("kyubi-mirror.*"))
            return run, events.replace(case, "CASE"), leftovers

    def test_missing_proc_attr_uses_fallback_and_completes_without_selinux(self):
        run, events, leftovers = self.run_case()
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIn("kyubi-mirror.", events)
        self.assertIn("fix_env", events)
        self.assertNotIn("chcon", events)
        self.assertFalse(leftovers)

    def test_proc_mount_failure_uses_fallback(self):
        run, events, leftovers = self.run_case(proc=True, proc_mount=False)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIn("kyubi-mirror.", events)
        self.assertFalse(leftovers)

    def test_existing_proc_mirror_keeps_original_route(self):
        run, events, _ = self.run_case(proc=True)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertNotIn("kyubi-mirror.", events)

    def test_both_mounts_fail_before_any_system_write_or_rollback(self):
        run, events, leftovers = self.run_case(proc=True, proc_mount=False,
                                             fallback_mount=False)
        self.assertNotEqual(run.returncode, 0)
        self.assertIn("mirror", run.stdout.lower())
        self.assertNotIn("bind ", events)
        self.assertNotIn("rollback", events)
        self.assertFalse(leftovers)

    def test_failures_roll_back_using_selected_mirror(self):
        for failure in ("bind", "write", "fix_env", "migrations"):
            with self.subTest(failure=failure):
                run, events, leftovers = self.run_case(failure=failure)
                self.assertNotEqual(run.returncode, 0)
                self.assertIn("rollback CASE/kyubi-mirror.", events)
                self.assertLess(events.index("rollback"), events.rindex("umount"))
                self.assertFalse(leftovers)

    def test_selinux_enabled_still_requires_context_success(self):
        run, events, _ = self.run_case(selinux=True)
        self.assertNotEqual(run.returncode, 0)
        self.assertIn("chcon", events)
        self.assertIn("Unable to set SELinux context", run.stdout)

    def test_cleanup_failure_is_reported_without_deleting_mounted_tree(self):
        run, events, leftovers = self.run_case(cleanup_failure=True)
        self.assertNotEqual(run.returncode, 0)
        self.assertTrue(leftovers)
        self.assertIn("mirror", run.stdout.lower())

    def test_recovery_retains_context_requirement_and_existing_paths(self):
        run, events, _ = self.run_case(selinux=True, context_ok=True, bootmode=False)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIn("chcon", events)
        self.assertNotIn("kyubi-mirror.", events)

    def test_active_selinux_does_not_bypass_failed_live_policy_patch(self):
        run, _, _ = self.run_case(selinux=True, context_ok=True)
        self.assertNotEqual(run.returncode, 0)
        self.assertIn("Kernel does not support dynamic SELinux Policy patch", run.stdout)

    def test_uninstaller_uses_fallback_and_exit_cleanup(self):
        run, events, leftovers = self.run_case(uninstall=True)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIn("kyubi-mirror.", events)
        self.assertFalse(leftovers)

    def test_uninstaller_bind_failure_cleans_fallback_on_abort(self):
        run, events, leftovers = self.run_case(uninstall=True, failure="bind")
        self.assertNotEqual(run.returncode, 0)
        self.assertIn("Unable to mirror system root", run.stdout)
        self.assertIn("umount", events)
        self.assertFalse(leftovers)


if __name__ == "__main__":
    unittest.main()
