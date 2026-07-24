package com.topjohnwu.magisk.core

import android.os.Build
import android.os.Process

@Suppress("DEPRECATION")
object Const {

    val CPU_ABI: String get() = Build.SUPPORTED_ABIS[0]

    // Null if 32-bit only or 64-bit only
    val CPU_ABI_32 =
        if (Build.SUPPORTED_64_BIT_ABIS.isEmpty()) null
        else Build.SUPPORTED_32_BIT_ABIS.firstOrNull()

    // Paths
    const val MAGISK_PATH  = "/data/adb/modules"
    const val TMPDIR = "/dev/tmp"
    const val MAGISK_LOG = "/cache/magisk.log"

    // Misc
    val USER_ID = Process.myUid() / 100000

    object Version {
        const val MIN_VERSION = "v22.0"
        const val MIN_VERCODE = 22000

        // These read the INSTALLED DAEMON's core code, not the APK's. They are not
        // dead: MIN_VERCODE admits daemons from 22000-30999, so someone upgrading
        // onto Kyubi from an older Magisk can genuinely hit `false` here.
        fun atLeast_24_0() = Info.env.coreVersionCode >= 24000
        fun atLeast_25_0() = Info.env.coreVersionCode >= 25000
    }

    object ID {
        const val DOWNLOAD_JOB_ID = 6
        const val CHECK_UPDATE_JOB_ID = 7
    }

    object Url {
        const val PATREON_URL = "https://www.patreon.com/topjohnwu"
        const val SOURCE_CODE_URL = "https://github.com/RobThePCGuy/Kyubi"

        val CHANGELOG_URL get() = Info.remote.kyubi.note

        const val GITHUB_RAW_URL = "https://raw.githubusercontent.com/"
        const val GITHUB_API_URL = "https://api.github.com/"
        const val GITHUB_PAGE_URL = "https://robthepcguy.github.io/Kyubi/"
        const val JS_DELIVR_URL = "https://cdn.jsdelivr.net/gh/"
    }

    object Key {
        // intents
        const val OPEN_SECTION = "section"
        const val PREV_PKG = "prev_pkg"
    }

    object Value {
        const val FLASH_ZIP = "flash"
        const val FLASH_MAGISK = "magisk"
        const val FLASH_MAGISK_SYSTEM = "magisk_system"
        const val UNINSTALL = "uninstall"
    }

    object Nav {
        const val HOME = "home"
        const val SETTINGS = "settings"
        const val MODULES = "modules"
        const val SUPERUSER = "superuser"
    }
}
