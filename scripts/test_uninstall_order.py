#!/usr/bin/env python3
"""Execute the uninstaller with sandboxed Android boundaries; never touch a device."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class UninstallOrderTests(unittest.TestCase):
    def test_app_wrapper_forwards_hidden_identity_and_stops_on_extraction_failure(self):
        source = (ROOT / 'app/src/main/res/raw/manager.sh').read_text()
        for failure in ('', 'extract'):
            with self.subTest(failure=failure):
                # Source the real wrapper; intercept only host filesystem and
                # child-process boundaries. No Android absolute path is touched.
                harness = source + r'''
rm() { return 0; }
mkdir() { return 0; }
unzip() { [ "$FAILURE" != extract ]; }
sh() { printf 'CHILD:%s|%s|%s|%s|%s|%s\n' "$INSTALLER" "$1" "$2" "$3" "$4" "$5"; }
run_uninstaller '/data/app/hidden manager/base.apk' com.hidden.random_manager
'''
                result = subprocess.run(['bash'], input=harness, text=True,
                                        capture_output=True, timeout=5,
                                        env=dict(os.environ, FAILURE=failure))
                if failure:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn('CHILD:', result.stdout)
                else:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn('CHILD:/dev/tmp/install|/dev/tmp/install/assets/uninstaller.sh|dummy|1|/data/app/hidden manager/base.apk|com.hidden.random_manager', result.stdout)

    def run_case(self, package='io.github.robthepcguy.kyubi', failure=''):
        with tempfile.TemporaryDirectory() as temp:
            case = Path(temp)
            (case / 'assets').mkdir()
            (case / 'manager-present').touch()
            # All destructive/platform boundaries are intercepted. The actual
            # script, ordering, branching, arguments and exit status are tested.
            (case / 'assets/util_functions.sh').write_text(r'''
event() { echo "$*" >> "$CASE_ROOT/events"; }
ui_print() { echo "$*"; }
abort() { echo "$*" >&2; exit 1; }
setup_flashable() { BOOTMODE=true; TMPDIR="$CASE_ROOT/payload"; MAGISK_VER=31.0; }
print_title() { :; }
is_mounted() { return 0; }
mount_partitions() { :; }
check_data() { DATA_DE=true; }
get_flags() { :; }
api_level_arch_detect() { ABI=x86_64; }
grep_prop() { [ "$1" != SYSTEMMODE ] || echo true; }
setup_installer_mirror() { MIRRORDIR="$CASE_ROOT/mirror"; }
cleanup_installer_mirror() { event mirror-cleanup; [ "$FAILURE" != mirror ]; }
is_rootfs() { return 1; }
mountpoint() { return 1; }
force_bind_mount() { return 0; }
mkdir() { :; }
ln() { :; }
mount() { event mount; }
blockdev() { :; }
rm() {
  event "remove $*"
  case "$*" in
    *system/etc/init*) [ "$FAILURE" != system ] ;;
    *post-fs-data.d*) [ "$FAILURE" != files ] ;;
    *payload*) [ "$FAILURE" != temporary ] ;;
    *) return 0 ;;
  esac
}
magisk() { event modules; [ "$FAILURE" != modules ]; }
sleep() { :; }
pm() {
  event "pm $*"
  [ "$1" = uninstall ] || return 2
  [ "$2" = "$EXPECTED_PACKAGE" ] || return 3
  case "$FAILURE" in
    package) echo 'Failure [DELETE_FAILED_INTERNAL_ERROR]'; return 42 ;;
    package_output) echo 'Failure [DELETE_FAILED_INTERNAL_ERROR]'; return 0 ;;
  esac
  command rm "$CASE_ROOT/manager-present"
  echo Success
}
reboot() {
  event reboot
  [ "$FAILURE" != reboot ] || return 37
}
''')
            source = (ROOT / 'scripts/uninstaller.sh').read_text()
            source = source.replace('/system/bin/reboot', 'reboot')
            source = source.replace('/system/bin/pm', 'pm')
            source = source.replace('cd /\n', 'cd "$CASE_ROOT"\n')
            (case / 'uninstaller.sh').write_text(source)
            env = dict(os.environ, CASE_ROOT=case.as_posix(), INSTALLER=case.as_posix(),
                       EXPECTED_PACKAGE=package, FAILURE=failure)
            command = ['bash', (case/'uninstaller.sh').as_posix(),
                       'dummy', '1', 'fixture.apk', package]
            process = subprocess.Popen(command, env=env, stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE, text=True)
            try:
                stdout, stderr = process.communicate(timeout=2)
                result = subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
            except subprocess.TimeoutExpired:
                # Git Bash has a launcher process: kill this fixture's whole
                # tree so a hung fixture cannot hang the suite.
                if os.name == 'nt':
                    subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                                   capture_output=True, timeout=5)
                else:
                    process.kill()
                process.communicate(timeout=5)
                result = None
            events = (case/'events').read_text().splitlines()
            return result, events, (case/'manager-present').exists()

    def test_app_uninstall_removes_manager_without_reboot(self):
        # An in-guest reboot hangs the emulators Kyubi targets, so the app path
        # finishes cleanup, removes the manager, remounts read-only and exits.
        result, events, present = self.run_case()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(present)
        removal = events.index('pm uninstall io.github.robthepcguy.kyubi')
        self.assertLess(events.index('mirror-cleanup'), removal)
        self.assertTrue(any('payload' in e for e in events[:removal]))
        self.assertIn('mount', events[removal:])
        self.assertNotIn('reboot', events)

    def test_hidden_manager_uses_running_package_identity(self):
        result, events, present = self.run_case('com.hidden.random_manager')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(present)
        self.assertIn('pm uninstall com.hidden.random_manager', events)
        self.assertNotIn('pm uninstall io.github.robthepcguy.kyubi', events)

    def test_cleanup_failures_keep_manager_and_prevent_reboot(self):
        for failure in ('system', 'modules', 'files', 'mirror', 'temporary'):
            with self.subTest(failure=failure):
                result, events, present = self.run_case(failure=failure)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(present)
                self.assertFalse(any(e.startswith('pm ') for e in events))
                self.assertNotIn('reboot', events)

    def test_package_removal_failure_prevents_reboot(self):
        for failure in ('package', 'package_output'):
            with self.subTest(failure=failure):
                result, events, present = self.run_case(failure=failure)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(present)
                self.assertNotIn('reboot', events)

    def test_standalone_does_not_remove_an_assumed_package(self):
        result, events, present = self.run_case(package='')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(present)
        self.assertFalse(any(e.startswith('pm ') for e in events))
        self.assertIn('reboot', events)

    def test_reboot_command_failure_is_reported(self):
        result, _, _ = self.run_case(package='', failure='reboot')
        self.assertEqual(result.returncode, 37)


if __name__ == '__main__':
    unittest.main(verbosity=2)
