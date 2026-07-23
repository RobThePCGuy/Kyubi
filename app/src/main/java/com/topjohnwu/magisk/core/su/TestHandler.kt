package com.topjohnwu.magisk.core.su

import android.os.Bundle
import com.topjohnwu.magisk.core.di.ServiceLocator
import com.topjohnwu.magisk.core.model.su.SuPolicy
import com.topjohnwu.magisk.core.tasks.MagiskInstaller
import com.topjohnwu.magisk.core.utils.RootUtils
import com.topjohnwu.superuser.Shell
import com.topjohnwu.superuser.internal.NOPList
import kotlinx.coroutines.runBlocking
import java.util.concurrent.TimeUnit

object TestHandler {

    fun run(method: String): Bundle {
        val r = Bundle()

        fun setup(): Boolean {
            val nop = NOPList.getInstance()
            return runBlocking {
                MagiskInstaller.Emulator(nop, nop).exec()
            }
        }

        fun test(): Boolean {
            // Skip Zygisk check since this version doesn't have Zygisk
            // Note: Zygisk functionality has been removed from this fork

            // Make sure the Magisk app can get root
            val shell = Shell.getShell()
            if (!shell.isRoot) {
                r.putString("reason", "shell not root")
                return false
            }

            // Make sure the root service is running
            RootUtils.Connection.await()

            // Grant ADB shell (uid 2000) a bounded, self-expiring allow so a
            // scripted `su` probe immediately following this call succeeds
            // without a manual tap. Scoped to the shell uid and time-limited
            // via `until`, unlike the old blanket `Config.suAutoResponse =
            // SU_AUTO_ALLOW`, which weakened su policy for every app on the
            // device with no way back until someone noticed and reverted it
            // by hand.
            runBlocking {
                ServiceLocator.policyDB.update(SuPolicy(2000).apply {
                    policy = SuPolicy.ALLOW
                    until = TimeUnit.MILLISECONDS.toSeconds(System.currentTimeMillis()) +
                        TimeUnit.MINUTES.toSeconds(5)
                })
            }
            return true
        }

        val b = runCatching {
            when (method) {
                "setup" -> setup()
                "test" -> test()
                else -> {
                    r.putString("reason", "unknown method")
                    false
                }
            }
        }.getOrElse {
            r.putString("reason", it.stackTraceToString())
            false
        }

        r.putBoolean("result", b)
        return r
    }
}