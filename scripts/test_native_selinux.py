#!/usr/bin/env python3
"""Native regressions on a disposable rooted Android guest (never reboots).

Run with --adb PATH --serial SERIAL --binary /absolute/path/to/magisk64.
Requires root adbd and Android's `su UID COMMAND` to test real DAC failures.
Only a uniquely named /data/local/tmp directory is changed and cleaned up.
Run on disabled and enabled (including permissive) SELinux kernels.
"""
import argparse
import json
import shlex
import subprocess
import unittest
import uuid


class NativeSelinux(unittest.TestCase):
    @classmethod
    def command(cls, command, check=True):
        p = subprocess.run([ARGS.adb, '-s', ARGS.serial, 'shell', command],
                           capture_output=True, text=True, timeout=15)
        print(json.dumps(dict(command=command, rc=p.returncode,
                              stdout=p.stdout, stderr=p.stderr)), flush=True)
        if check and p.returncode:
            raise AssertionError(f'{command}: {p.returncode}\n{p.stdout}{p.stderr}')
        return p

    @classmethod
    def setUpClass(cls):
        assert cls.command('id -u').stdout.strip() == '0', 'requires root adbd'
        assert cls.command('su 2000 id -u').stdout.strip() == '2000', 'requires UID switching'
        cls.selinux = cls.command('getenforce').stdout.strip()
        cls.command('cat /proc/sys/kernel/random/boot_id')
        cls.root = '/data/local/tmp/kyubi-native-test-' + uuid.uuid4().hex
        cls.command(f'mkdir {cls.root} && chmod 755 {cls.root}')
        cls.bin = cls.root + '/magisk64'
        cls.command(f'cp {shlex.quote(ARGS.binary)} {cls.bin} && chmod 755 {cls.bin}')

    @classmethod
    def tearDownClass(cls):
        cls.command(f'rm -rf {cls.root}')

    def setUp(self):
        self.dir = self.root + '/' + self._testMethodName
        self.command(f'mkdir {self.dir} && chmod 777 {self.dir}')
        self.src = self.dir + '/src'
        self.dst = self.dir + '/dst'
        self.command(f'echo native-copy-fixture > {self.src}; chmod 640 {self.src}')

    def clone(self, source=None, dest=None, uid=None):
        prefix = f'su {uid} ' if uid is not None else ''
        return self.command(f'{prefix}{self.bin} --clone {source or self.src} {dest or self.dst}', False)

    def test_auto_selinux_dispatches_next_option(self):
        plain = self.command(f'{self.bin} -c')
        auto = self.command(f'{self.bin} --auto-selinux -c')
        self.assertEqual(auto.stdout, plain.stdout)

    def test_copy_preserves_contents_mode_and_owner(self):
        self.command(f'chown 1234:2345 {self.src}')
        self.assertEqual(self.clone().returncode, 0)
        self.assertEqual(self.command(f'cat {self.dst}').stdout.strip(), 'native-copy-fixture')
        self.assertEqual(self.command(f'stat -c %a:%u:%g {self.dst}').stdout.strip(), '640:1234:2345')

    def test_recursive_copy_preserves_files_and_symlinks(self):
        tree = self.dir + '/tree'
        self.command(f'mkdir {tree}; cp {self.src} {tree}/file; ln -s file {tree}/link; chmod 750 {tree}')
        self.assertEqual(self.clone(tree).returncode, 0)
        self.assertEqual(self.command(f'cat {self.dst}/file; readlink {self.dst}/link; stat -c %a {self.dst}').stdout.split(),
                         ['native-copy-fixture', 'file', '750'])

    def test_enabled_selinux_preserves_label(self):
        if self.selinux == 'Disabled':
            self.skipTest('requires an enabled SELinux kernel')
        self.assertEqual(self.clone().returncode, 0)
        src = self.command(f'ls -Zd {self.src}').stdout.split()[0]
        dst = self.command(f'ls -Zd {self.dst}').stdout.split()[0]
        self.assertIn(':', src)
        self.assertEqual(dst, src)

    def test_enabled_probe_does_not_hide_missing_metadata_or_proc_context(self):
        if self.selinux != 'Disabled':
            self.skipTest('absence fixture requires disabled SELinux')
        # A private mount namespace supplies the enabled/permissive probe while
        # retaining the real absent proc context and security.selinux xattr.
        # Make mounts private BEFORE overlaying sysfs so nothing escapes the test.
        setup = 'mount -o rprivate none / && mount -t tmpfs tmpfs /sys/fs && mkdir /sys/fs/selinux && echo 0 > /sys/fs/selinux/enforce && '
        for args, error in [(f'--clone {self.src} {self.dst}', 'No data available'),
                            ('--auto-selinux -c', 'No such file')]:
            result = self.command('unshare -m sh -c ' + shlex.quote(setup + self.bin + ' ' + args), False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(error, result.stderr)

    def test_missing_source_fails(self):
        result = self.clone(self.dir + '/absent')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('No such file', result.stderr)

    def test_disabled_kernel_can_copy_from_filesystem_without_xattrs(self):
        if self.selinux != 'Disabled':
            self.skipTest('requires disabled SELinux and procfs without xattrs')
        expected = self.command('cat /proc/version').stdout
        self.assertEqual(self.clone('/proc/version').returncode, 0)
        self.assertEqual(self.command(f'cat {self.dst}').stdout, expected)

    def test_permission_change_failure_propagates(self):
        self.command(f'touch {self.dst}; chmod 644 {self.src} {self.dst}')
        result = self.command(f'su 2000 {self.bin} --clone-attr {self.src} {self.dst}', False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Operation not permitted', result.stderr)

    def test_unreadable_source_fails(self):
        self.command(f'chmod 600 {self.src}')
        result = self.clone(uid=2000)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Permission denied', result.stderr)

    def test_destination_creation_failure_propagates(self):
        result = self.clone(dest=self.dir + '/absent/dst')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('No such file', result.stderr)

    def test_ownership_failure_propagates(self):
        self.command(f'chmod 644 {self.src}')
        result = self.clone(uid=2000)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Operation not permitted', result.stderr)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', default='adb')
    parser.add_argument('--serial', required=True)
    parser.add_argument('--binary', required=True)
    ARGS, remaining = parser.parse_known_args()
    unittest.main(argv=[__file__, *remaining], verbosity=2)
