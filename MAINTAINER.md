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
  cannot run), and Kyubi installs **system-mode only**. The boot-patch install
  routes are both **hidden** (`InstallViewModel.allowBootPatch = false`) and
  **blocked** (`InstallViewModel.install()` always runs the system-mode flash and
  never navigates into a boot-image flow). `manager.sh`'s `env_check` no longer
  requires `magiskboot`/preinit (so a healthy offline install shows no "additional
  setup" nag). **Not yet stripped (tracked dead code):** `MagiskInstaller`'s
  `Patch`/`Direct`/`SecondSlot` + `patchBoot()`, and the ChromeOS boot-signing
  assets, are unreachable but still present; `boot_patch.sh` is deliberately kept
  because the addon.d survival path (`install_addond`) still consumes it. Removing
  that plumbing is a build-verified follow-up, not a quick delete. The upstream
  AVD boot-patch dev scripts (`scripts/avd_patch.sh`, `scripts/avd_test.sh`)
  exercise the removed path and are **not** run by CI.
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
`*.keystore` are git-ignored. CI's "Set up release signing" step decodes
`KYUBI_KEYSTORE_B64` and appends the signing config to `config.prop` from
`KYUBI_KEYSTORE_PASS` / `KYUBI_KEY_ALIAS` / `KYUBI_KEY_PASS`. With no secret set,
the build falls back to debug-signed.

## CI / releases

`.github/workflows/android.yml`:

- **Triggers** on push to `dev`/`kitsune`, on **pull requests**, and manually
  (`workflow_dispatch`).
- **`build`** — release + debug for x86/x86_64, signed from secrets, artifacts
  uploaded.
- **`smoke`** — asserts Kyubi's build invariants on the release APK (package id,
  x86-only ABIs, no `magiskboot`, feeds point at Kyubi) and installs + launches
  it on a stock x86_64 emulator, failing on a crash. **Note:** this does not test
  the offline system-mode root install, which is BlueStacks-VHD-specific and
  can't be reproduced on a stock AVD — that validation happens on real emulator
  instances.
- **`release`** — publishes only on a `kitsune` push, and **only if `build` and
  `smoke` both pass**. Tag `v31.0-<short-commit>`; the short hash is the exact
  version the APK reports. Releases never expire (unlike CI artifacts); prune old
  ones whenever.

To cut a blessed **stable** milestone (e.g. `kyubi-1.0.0`), tag the commit; the
per-commit releases are the rolling/canary line, a stable tag is additive.
