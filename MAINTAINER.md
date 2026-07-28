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
  the obsolete AVD dev scripts + their `build.py` commands; the native `magiskboot`
  crate itself (`native/src/boot` — Rust + C++ source — dropped from the Cargo
  workspace, not merely excluded from the build targets); the boot-image helpers
  in the shared `util_functions.sh`
  (`find_boot_image`/`flash_image`/`install_magisk`/`sign_chromeos` + `boot_patch.sh`
  sourcing); and the uninstaller's boot-restore branch — `uninstaller.sh` is now
  system-mode only. `Info.patchBootVbmeta`/`isBootPatched` and the `patch_vbmeta`
  string are gone as well. The install-options card (`keepVerity`/`keepEnc`/recovery)
  and `tools/ndk-bins/arm` (ARM build-support prebuilts) have since been removed too,
  in a later pass — nothing phone-only remains in either the install UI or the
  bundled NDK prebuilts.
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

## Dependencies

**There is no upstream remote.** Kyubi was a clean import, not a GitHub fork:
`origin` is the only remote and no branch tracks anything else. The lineage
(topjohnwu -> HuskyDG -> 1q23lyc45 -> Kitsune) lives in the commit history, which
is where the GPL credit belongs -- but it also means **no upstream fix reaches
Kyubi automatically**. If Magisk ships a security fix in the daemon, someone has
to notice and port it by hand. Treat that as a standing maintenance duty, not a
one-time note.

**Submodules (9).** Every one is linked by something that ships:

| Submodule | Provides | Consumed by |
|---|---|---|
| `selinux` | `libsepol`, `libselinux` | `magiskpolicy` (via `libpolicy`), `busybox` |
| `pcre` | `libpcre2` | `libselinux` |
| `busybox` | `busybox` applet | shipped binary |
| `libcxx` | `libcxx` | `libbase`, `libsystemproperties` |
| `cxx-rs` | Rust/C++ bridge | every Rust crate |
| `system_properties` | `libsystemproperties` | `magisk`, `resetprop` |
| `parallel-hashmap` | `libphmap` | `magisk` |
| `_xDL` | `libxdl` | `magisk` |
| `termux-elf-cleaner` | build tool | `build.py` |

Five submodules were removed once `magiskboot` was dropped, because nothing
linked them any more: **`lz4`, `bzip2`, `zopfli`, `xz`, `zlib`** (`liblz4`,
`libbz2`, `libzopfli`, `liblzma`, `libz`). The vendored `xz-embedded` +
`xz_config` sources went with them -- `libxz` was magiskinit's ramdisk
decompressor, and the magiskinit rewrite (now a `--patch-sepol`-only tool) left
it unreferenced. They were still being cloned on every CI run and every fresh
checkout: pure supply-chain surface for zero shipped code.

If you ever need to re-check this, the test is mechanical: a static library in
`native/src/external/Android.mk` is live only if some `LOCAL_STATIC_LIBRARIES`
chain reaches it from `magisk`, `magiskinit`, `magiskpolicy`, `resetprop`, or
`busybox`. `ndk-build` does not build unreachable modules, so a clean build
(`rm -rf native/obj native/libs && python build.py binary`) is the proof --
beware stale `native/obj` artifacts, which will happily show you a `.a` for a
module nothing links any more.

**Dependabot** (`.github/dependabot.yml`) covers three ecosystems, in
blast-radius order: **gradle** (compiles into the shipped APK), **github-actions**
(keeps the deliberately SHA-pinned actions from rotting -- a pin never updates
itself), and **cargo** (the native build toolchain, mostly build-time only).
Cargo was the only ecosystem watched originally, which had it backwards: the
one that ships was unmonitored and the one that doesn't was.

## Building

**JDK:** the bundled Kotlin compiler cannot parse class files from the newest
JDKs — a default `JAVA_HOME` pointing at JDK 25+ fails with a Kotlin compiler
error that does not name the JDK as the cause. Build with JDK 17 or 21:

```sh
export JAVA_HOME=/c/path/to/jdk-21              # or jdk-17
export PATH="/c/path/to/jdk-21/bin:$PATH"       # build.py resolves javac via PATH
```

Adoptium installers nest the JDK one level down (e.g.
`C:\Android\jdk17\jdk-17.0.19+10`). Pointing `JAVA_HOME`/`PATH` at the *outer*
directory leaves the system `javac` winning, and the build then fails with
"JDK 17 is required, but javac NN is active" as though nothing were set at all.
Point both at the inner directory.

On Windows under Git Bash, use the `/c/...` form. A Windows-style
`C:/Users/.../jdk-21` is silently split on the colon as a PATH separator, so
`java` still resolves to the system JDK and the build fails as if `JAVA_HOME`
were never set. **`JAVA_HOME` alone is not sufficient here** -- `build.py`
resolves `javac` from `PATH`, so a newer `javac` earlier in `PATH` still wins
and the build fails with "JDK 17 is required, but javac NN is active". Prepend
the JDK bin directory to `PATH` as well.

**SDK location:** if `ANDROID_HOME` is also set (many toolchain installers set it),
Gradle aborts when the two disagree -- "Several environment variables and/or system
properties contain different paths to the SDK". Export **both** to the same root
for an APK build. `build.py binary` (native only) reads `ANDROID_SDK_ROOT` alone,
so the mismatch only surfaces once Gradle runs.

```sh
export ANDROID_SDK_ROOT=/path/to/android-sdk
export ANDROID_HOME="$ANDROID_SDK_ROOT"   # Gradle rejects a mismatch
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

- **Permissions:** read-only by default; the `release` job elevates to
  `contents: write` + `pages: write`. Checkouts use `persist-credentials: false`,
  **except** the `gh-pages` checkout in the feed-writing jobs, which must push.
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

## Versioning

Kyubi carries **two** version numbers, and conflating them is the bug this
scheme exists to prevent:

- **Core compatibility code** — `magisk.versionCode=31000` in `gradle.properties`.
  The Magisk core feature level the daemon implements; reported by `magisk -V`,
  compiled into `flags.h` and `util_functions.sh`, and exposed to the app as
  `BuildConfig.CORE_VER_CODE`. Compare this against an *installed daemon*.
- **Build code** — the APK's Android `versionCode`, computed as
  `31000 + commits since kyubi.buildCodeAnchor`. A monotonic ordering key, not an
  identity (the commit SHA is the identity). Compare this against a *feed entry*.

The anchor is the last commit shipped at `versionCode = 31000`. It is
ancestry-checked at build time: a rewritten lineage fails the build rather than
producing a plausible wrong count.

**If history is ever rewritten past the anchor, you must move BOTH values, as a
new epoch.** Moving `kyubi.buildCodeAnchor` alone lowers the build code, because
the count restarts from a later commit while the base stays at 31000 — which
reintroduces exactly the downgrade this scheme exists to prevent. Set:

- `LEGACY_BUILD_CODE_BASE` (in `buildSrc/src/main/java/Plugin.kt`) to the highest
  build code you have ever published, and
- `kyubi.buildCodeAnchor` to the commit carrying that high-water mark.

The next descendant commit then receives high-water-mark + 1. Verify with
`./build.py -vr all && ./scripts/kyubi_smoke.sh out/app-release.apk` before
publishing anything, and confirm against
`gh release list` that no published release carries a higher code.

Stable releases are promoted through `.github/workflows/promote.yml`, which
requires manual approval via the protected `release` environment.

**The `release` environment must exist with required reviewers configured**
(Settings → Environments). GitHub implicitly creates an environment referenced by
a workflow *with no protection rules*, so a missing configuration leaves promotion
looking gated while approving automatically. Keep **Prevent self-review OFF** —
with a single maintainer, enabling it makes promotion impossible.
