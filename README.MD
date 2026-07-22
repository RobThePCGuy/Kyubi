# Kyubi

**Kyubi is a stripped-down, emulator-only build of Magisk** — root for Android
emulators (BlueStacks and other x86/x86_64 guests), and nothing you don't need
there. It is a rebrand and reduction of the Magisk Delta / Kitsune lineage, kept
open under the GPL.

> Not affiliated with or endorsed by [topjohnwu](https://github.com/topjohnwu)
> (Magisk), HuskyDG (Magisk Delta), or the Kitsune Magisk maintainers. Kyubi
> builds on their GPL-licensed work — see **Lineage & credit** below.

## What "stripped-down" means

Kyubi is Magisk with everything an emulator never uses removed, so what ships is
smaller, faster to build, and has less surface to go wrong:

- **x86 / x86_64 only.** No ARM ABIs. Emulator guests are x86; ARM builds were
  dead weight (the APK is ~42% smaller for it).
- **No `magiskboot`, no boot-image patching.** The `magiskboot` native tool — the
  thing that unpacks and repacks a boot image — is stripped from the build, so
  boot-image patching cannot run. Kyubi installs in **system mode** only, writing
  into the guest's system partition. The boot-image install path is gone: the
  installer's boot-patch methods, `boot_patch.sh`, the ChromeOS signing tools, the
  addon.d survival script, and the recovery-flashable-zip metadata are all removed.
  Kyubi is not a recovery-flashable zip.
- **No built-in Zygisk.** The built-in Zygisk was removed upstream (commit
  `2ef8f00`) over security vulnerabilities. Use
  **[ReZygisk](https://github.com/PerformanC/ReZygisk)** for the Zygisk API;
  Kyubi's DenyList feeds it.

Everything else — MagiskSU (root), Magisk Modules, DenyList — works.

## Downloads

Grab a build from [**Releases**](https://github.com/RobThePCGuy/Kyubi/releases).
Every push to `kitsune` publishes a **rolling prerelease** tagged
`v31.0-<short-commit>` (the short hash is the build suffix in the version the app
reports). These are candidates: CI verifies the build and that it installs and
launches, but the system-mode root install is validated separately on a real
instance. A blessed **stable** milestone (e.g. `kyubi-1.0.0`) is cut manually
after that validation.

Each release attaches only the certificate-verified release APKs (debug builds
are not published):

- `app-release.apk` — the Kyubi manager (install this)
- `stub-release.apk` — the cert-pinned hidden-manager stub

## Building

```sh
export ANDROID_SDK_ROOT=/path/to/android-sdk
python build.py ndk        # install the ondk (Magisk NDK, r27.1)
python build.py -r all     # release -> out/app-release.apk
python build.py all        # debug   -> out/app-debug.apk
```

Output APKs carry native libs for **x86 and x86_64 only**. CI in
`.github/workflows/android.yml` builds and smoke-tests every push and pull
request, and publishes the release on pushes to `kitsune`. Maintenance notes and
the exact deltas from upstream live in [`MAINTAINER.md`](MAINTAINER.md).

## Bug reports

Report against a **debug** build and attach its log. For install issues, include
the install log; for runtime issues, `logcat` or `dmesg` from the emulator.

## Lineage & credit

Kyubi stands on a chain of GPL work, each link credited:

- **[Magisk](https://github.com/topjohnwu/Magisk)** — topjohnwu, the original.
- **Magisk Delta** — HuskyDG, which added the system-mode install Kyubi relies on.
- **[Kitsune Magisk](https://github.com/1q23lyc45/KitsuneMagisk)** — the
  continuation Kyubi forked from (core version `31.0-kitsune`, versionCode 31000).

The in-app credits screen names the upstream authors directly. Kyubi keeps the
lineage honest; it does not claim their work as its own.

## License

    Kyubi, including all git submodules, is free software: you can redistribute
    it and/or modify it under the terms of the GNU General Public License as
    published by the Free Software Foundation, either version 3 of the License,
    or (at your option) any later version.

    This program is distributed in the hope that it will be useful, but WITHOUT
    ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
    FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along with
    this program. If not, see <http://www.gnu.org/licenses/>.
