# Kyubi — maintenance notes

Kyubi is a **stripped, rebranded, emulator-only** build of the Magisk Delta /
Kitsune lineage, forked from the `VisionR1/KitsuneMagisk` snapshot (core version
**31000 / 31.0-kitsune**). This file records exactly what Kyubi changes on top of
that snapshot so a future maintainer can tell Kyubi's deltas from upstream.

## What Kyubi strips (the reductions that define it)

- **ABIs: x86 / x86_64 only.** `build.py` (`archs`, triples, target lists),
  `native/src/Application.mk` (`APP_ABI`), and `buildSrc/.../Setup.kt` (`syncLibs`)
  are all trimmed to the two x86 ABIs. No `armeabi-v7a`, no `arm64-v8a`. Output
  APKs are **not** universal.
- **No `magiskboot` / no boot-image path.** The `magiskboot` native module is
  dropped from the build (load-bearing: without it boot-image patching literally
  cannot run), and Kyubi installs **system-mode only**. `manager.sh`'s `env_check`
  no longer requires `magiskboot`/preinit (so a healthy offline install shows no
  "additional setup" nag). The entire boot-image install path is **removed**, not
  just hidden: `MagiskInstaller`'s `Patch`/`Direct`/`SecondSlot` + `patchBoot()` +
  boot/vbmeta/payload parsers; the install-method UI (patch/direct/inactive-slot)
  and its strings/dialog; `boot_patch.sh`, the ChromeOS signing tools, and
  `bootctl`; the addon.d survival script + the `install_addond` call/function; the
  recovery-flashable-zip metadata (`update_binary.sh`/`flash_script.sh` embedding);
  the obsolete AVD dev scripts + their `build.py` commands; and the dormant native
  `B_BOOT` wiring. **Still present (deliberate, coupled/inert):** the boot-image
  helpers in the shared `util_functions.sh` (used by the kept uninstaller, whose
  boot branch is now guarded by an explicit abort), the inert install-options
  card, `Info.patchBootVbmeta`, and `tools/ndk-bins/arm`.
- **Built-in Zygisk removed** (upstream commit `2ef8f00`, security). The dead
  Zygisk settings toggle is removed from the app. Use
  **[ReZygisk](https://github.com/PerformanC/ReZygisk)** for the Zygisk API;
  Kyubi's DenyList feeds it.

## Rebrand

- **Package id:** `io.github.robthepcguy.kyubi` (`app`/`stub` `applicationId`,
  and `JAVA_PACKAGE_NAME` in `native/src/include/consts.hpp`, which the daemon
  compiles in). If you change this, the BlueStacks-Root-GUI installer's
  `MANAGER_PACKAGE` must change to match.
- **Identity:** fox launcher + in-app mark, Kyubi dark theme (`Theme.kt` +
  `themes_md2.xml`), Kyubi strings/labels. Update feeds and the source/changelog
  URLs (`Const.kt`, stub `DownloadActivity`) point at Kyubi, not upstream.

## Build fixes carried from the VisionR1 snapshot

- **selinux submodule URL** (`.gitmodules`): the upstream `1q23lyc45/selinux`
  remote is unreachable (HTTP 404). Re-pointed to `LSPosed/selinux`, which hosts
  the **identical pinned commit `8c6acc0d7792cda5f203dfd8e94c633e9dbfdeae`**.
  Without this, `git submodule update` (and CI checkout) fails.
- **`init-ld` linker fix** (`native/src/Android.mk`): disable LTO for the tiny
  `libinit-ld.so` preloader (`-fno-lto`). The ondk r27.1 `lld` segfaults during
  LTO codegen for a shared object on some hosts (notably Windows); LTO is
  pointless for a single-file preloader, so this is behavior-neutral.

## Building

```sh
export ANDROID_SDK_ROOT=/path/to/android-sdk
python build.py ndk        # install the ondk (Magisk NDK, r27.1)
python build.py -r all     # release -> out/app-release.apk
python build.py all        # debug   -> out/app-debug.apk
```

APKs carry **x86 and x86_64** native libs only.

## Signing

Release APKs are signed with the **Kyubi key, which lives only in GitHub Actions
secrets** — never in the repo. `config.prop` carries no credentials; `*.jks` /
`*.keystore` are git-ignored. The signing secrets are exposed **only on a kitsune
push** (the "Set up release signing" step is skipped for PRs, `dev`, and manual
runs, so those never receive the key). The step decodes `KYUBI_KEYSTORE_B64` and
appends the config to `config.prop` from `KYUBI_KEYSTORE_PASS` / `KYUBI_KEY_ALIAS`
/ `KYUBI_KEY_PASS`; a kitsune push with no secret **fails closed**. The signing
config is then **stripped before the debug build**, so debug APKs are always
debug-signed, and CI asserts release certs == the pin and debug certs != the pin.
The cert pin is single-source: CI checks the stub's `DynLoad` pin against the
workflow `KYUBI_CERT_SHA256` and fails on drift.

## CI / releases

`.github/workflows/android.yml`:

- **Permissions:** read-only by default; only the `release` job elevates to
  `contents: write`. Checkouts use `persist-credentials: false`.
- **Triggers** on push to `dev`/`kitsune`, on **pull requests**, and manually
  (`workflow_dispatch`).
- **`build`** — release + debug for x86/x86_64. Release is signed from secrets
  (kitsune push only); the key is stripped before the debug build; certs verified.
- **`smoke`** — asserts Kyubi's build invariants on the release APK (package id,
  x86-only ABIs, no `magiskboot`, no flashable-zip updater / addon.d.sh, feeds
  point at Kyubi) and installs + launches it on a stock x86_64 emulator, failing
  on a crash. **Note:** this does not test the offline system-mode root install,
  which is BlueStacks-VHD-specific and can't be reproduced on a stock AVD — that
  validation happens on real emulator instances.
- **`release`** — publishes **only the cert-verified release** manager/stub APKs
  on a `kitsune` push, and **only if `build` and `smoke` both pass**, always as a
  **prerelease** (rolling candidate). Debug APKs stay private CI artifacts. Tag
  `v31.0-<short-commit>`.

**Stable releases are cut manually** (no tag-triggered job yet): after live
system-mode validation, publish a `kyubi-x.y.z` release from a validated commit's
`app-release.apk`/`stub-release.apk`. Automating this behind a protected
environment with manual approval is a tracked follow-up. **Also tracked:**
decouple the Android application `versionCode` (should be a monotonic build
number) from the Magisk core compat code (`31000`) before an update feed goes
live, or the updater can't tell two rolling builds apart.
