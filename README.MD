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
- **No `magiskboot`, no boot-image patching.** Kyubi installs in **system mode**
  only — it writes into the guest's system partition, it never unpacks or repacks
  a boot image. The entire boot-patch toolchain and its UI are gone.
- **No built-in Zygisk.** The built-in Zygisk was removed upstream (commit
  `2ef8f00`) over security vulnerabilities. Use
  **[ReZygisk](https://github.com/PerformanC/ReZygisk)** for the Zygisk API;
  Kyubi's DenyList feeds it.

Everything else — MagiskSU (root), Magisk Modules, DenyList — works.

## Downloads

Grab a build from [**Releases**](https://github.com/RobThePCGuy/Kyubi/releases).
Every push to `kitsune` publishes a full release tagged `v31.0-<short-commit>`
(the short hash is the version the app reports); stable milestones are tagged
separately (e.g. `kyubi-1.0.0`).

Each release attaches:

- `app-release.apk` — the Kyubi manager (install this)
- `app-debug.apk` — debug build, verbose logging (use this for bug reports)

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
