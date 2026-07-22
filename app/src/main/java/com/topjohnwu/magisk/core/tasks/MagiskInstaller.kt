package com.topjohnwu.magisk.core.tasks

import android.system.Os
import android.widget.Toast
import androidx.annotation.WorkerThread
import androidx.core.os.postDelayed
import com.topjohnwu.magisk.BuildConfig
import com.topjohnwu.magisk.R
import com.topjohnwu.magisk.StubApk
import com.topjohnwu.magisk.core.AppApkPath
import com.topjohnwu.magisk.core.Const
import com.topjohnwu.magisk.core.Info
import com.topjohnwu.magisk.core.di.ServiceLocator
import com.topjohnwu.magisk.core.isRunningAsStub
import com.topjohnwu.magisk.core.ktx.reboot
import com.topjohnwu.magisk.core.ktx.toast
import com.topjohnwu.magisk.core.ktx.writeTo
import com.topjohnwu.magisk.core.utils.RootUtils
import com.topjohnwu.superuser.Shell
import com.topjohnwu.superuser.internal.NOPList
import com.topjohnwu.superuser.internal.UiThreadHandler
import com.topjohnwu.superuser.nio.ExtendedFile
import com.topjohnwu.superuser.nio.FileSystemManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import timber.log.Timber
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import java.util.zip.ZipEntry
import java.util.zip.ZipFile

// Kyubi installs in system mode only (see xdirect_install_system in manager.sh):
// extract the binaries, run the system-mode install, fix the env, and uninstall.
abstract class MagiskInstallImpl protected constructor(
    protected val console: MutableList<String> = NOPList.getInstance(),
    private val logs: MutableList<String> = NOPList.getInstance()
) {
    protected lateinit var installDir: ExtendedFile

    private val shell = Shell.getShell()
    protected val context get() = ServiceLocator.deContext
    private val useRootDir = shell.isRoot && Info.noDataExec

    private val rootFS get() = RootUtils.fs
    private val localFS get() = FileSystemManager.getLocal()

    private suspend fun extractFiles(): Boolean {
        console.add("- Device platform: ${Const.CPU_ABI}")
        console.add("- Installing: ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")

        installDir = localFS.getFile(context.filesDir.parent, "install")
        installDir.deleteRecursively()
        installDir.mkdirs()

        try {
            // Extract binaries
            if (isRunningAsStub) {
                val zf = ZipFile(StubApk.current(context))

                // Also extract magisk32 on non 64-bit only 64-bit devices
                val is32lib = Const.CPU_ABI_32?.let {
                    { entry: ZipEntry -> entry.name == "lib/$it/libmagisk32.so" }
                } ?: { false }

                zf.entries().asSequence().filter {
                    !it.isDirectory && (it.name.startsWith("lib/${Const.CPU_ABI}/") || is32lib(it))
                }.forEach {
                    val n = it.name.substring(it.name.lastIndexOf('/') + 1)
                    val name = n.substring(3, n.length - 3)
                    val dest = File(installDir, name)
                    zf.getInputStream(it).writeTo(dest)
                    dest.setExecutable(true)
                }
                zf.close()
            } else {
                val info = context.applicationInfo
                var libs = File(info.nativeLibraryDir).listFiles { _, name ->
                    name.startsWith("lib") && name.endsWith(".so")
                } ?: emptyArray()

                // Also symlink magisk32 on non 64-bit only 64-bit devices
                val lib32 = info.javaClass.getDeclaredField("secondaryNativeLibraryDir")
                    .get(info) as String?
                if (lib32 != null) {
                    libs += File(lib32, "libmagisk32.so")
                }

                for (lib in libs) {
                    val name = lib.name.substring(3, lib.name.length - 3)
                    Os.symlink(lib.path, "$installDir/$name")
                }
            }

            // Extract scripts
            for (script in listOf("util_functions.sh", "stub.apk")) {
                val dest = File(installDir, script)
                context.assets.open(script).writeTo(dest)
            }
        } catch (e: Exception) {
            console.add("! Unable to extract files")
            Timber.e(e)
            return false
        }

        if (useRootDir) {
            // Move everything to tmpfs to workaround Samsung bullshit
            rootFS.getFile(Const.TMPDIR).also {
                arrayOf(
                    "rm -rf $it",
                    "mkdir -p $it",
                    "cp_readlink $installDir $it",
                    "rm -rf $installDir"
                ).sh()
                installDir = it
            }
        }

        return true
    }

    private fun Array<String>.sh() = shell.newJob().add(*this).to(console, logs).exec()
    private fun String.sh() = shell.newJob().add(this).to(console, logs).exec()

    protected suspend fun direct_system() =
        extractFiles() && "xdirect_install_system \"$installDir\" \"dummy\" \"$AppApkPath\"".sh().isSuccess

    protected suspend fun fixEnv() = extractFiles() && "fix_env $installDir".sh().isSuccess

    protected fun uninstall() = "run_uninstaller $AppApkPath".sh().isSuccess

    // installDir is lateinit; a duplicate-session bail returns before it is set,
    // so only clean up when it was actually initialized. isInitialized is only
    // allowed in the declaring class, hence this helper.
    protected fun cleanupInstall() {
        // Synchronous (.exec, not .submit): the caller holds the session lock and
        // must not return until the failed attempt's files are actually gone.
        if (::installDir.isInitialized)
            Shell.cmd("rm -rf $installDir").exec()
    }

    @WorkerThread
    protected abstract suspend fun operations(): Boolean

    open suspend fun exec(): Boolean {
        // Exception-safe single-session lock: never leave haveActiveSession stuck
        // at true if operations() throws or the coroutine is cancelled.
        if (!haveActiveSession.compareAndSet(false, true))
            return false
        return try {
            withContext(Dispatchers.IO) {
                val result = operations()
                // Clean up a failed attempt synchronously and WHILE the lock is
                // still held, so an immediate retry can't recreate installDir and
                // then have this delete race away the new attempt's files.
                if (!result) cleanupInstall()
                result
            }
        } finally {
            haveActiveSession.set(false)
        }
    }

    companion object {
        private var haveActiveSession = AtomicBoolean(false)
    }
}

abstract class MagiskInstaller(
    console: MutableList<String>,
    logs: MutableList<String>
) : MagiskInstallImpl(console, logs) {

    override suspend fun exec(): Boolean {
        // Failure cleanup is handled synchronously inside super.exec() while the
        // session lock is held; here we only report the outcome.
        val success = super.exec()
        console.add(if (success) "- All done!" else "! Installation failed")
        return success
    }

    class Direct_system(
        console: MutableList<String>,
        logs: MutableList<String>
    ) : MagiskInstaller(console, logs) {
        override suspend fun operations() = direct_system()
    }

    class Emulator(
        console: MutableList<String>,
        logs: MutableList<String>
    ) : MagiskInstaller(console, logs) {
        override suspend fun operations() = fixEnv()
    }

    class Uninstall(
        console: MutableList<String>,
        logs: MutableList<String>
    ) : MagiskInstallImpl(console, logs) {
        override suspend fun operations() = uninstall()

        override suspend fun exec(): Boolean {
            val success = super.exec()
            if (success) {
                UiThreadHandler.handler.postDelayed(3000) {
                    Shell.cmd("pm uninstall ${context.packageName}").exec()
                }
            }
            return success
        }
    }

    class FixEnv(private val callback: () -> Unit) : MagiskInstallImpl() {
        override suspend fun operations() = fixEnv()

        override suspend fun exec(): Boolean {
            val success = super.exec()
            callback()
            context.toast(
                if (success) R.string.reboot_delay_toast else R.string.setup_fail,
                Toast.LENGTH_LONG
            )
            if (success)
                UiThreadHandler.handler.postDelayed(5000) { reboot() }
            return success
        }
    }
}
