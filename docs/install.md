# Installing Kyubi

Kyubi installs **system-mode only**, on x86 / x86_64 Android emulators. There is
no boot-image patching, no `magiskboot`, no recovery flashing, and no fastboot
step — those paths are removed from this fork, not merely hidden.

1. Grab `app-release.apk` from [Releases](https://github.com/RobThePCGuy/Kyubi/releases).
2. Install it with [BlueStacks-Root-GUI](https://github.com/RobThePCGuy/BlueStacks-Root-GUI),
   which performs the offline system-mode install.
3. Launch Kyubi and confirm the home screen reports an active daemon.

For what Kyubi is and is not, see the [root README](../README.md).
