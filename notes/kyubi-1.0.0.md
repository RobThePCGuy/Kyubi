## Kyubi 1.0.0

Emulator-only Magisk for x86 / x86_64 Android emulators, installed in **system
mode**. No boot-image patching, no `magiskboot`, no recovery or fastboot paths —
those are removed from this fork, not merely hidden.

- MagiskSU (root), Magisk modules, and a DenyList that holds up
- Zygisk via [ReZygisk](https://github.com/PerformanC/ReZygisk); Kyubi's DenyList feeds it
- Built from GPLv3 source, signed with the Kyubi release key

Install with [BlueStacks-Root-GUI](https://github.com/RobThePCGuy/BlueStacks-Root-GUI),
which performs the offline system-mode install.
