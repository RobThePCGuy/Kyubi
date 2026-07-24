package com.topjohnwu.magisk.ui.deny

import android.annotation.SuppressLint
import android.content.pm.PackageManager.MATCH_UNINSTALLED_PACKAGES
import androidx.databinding.Bindable
import androidx.lifecycle.viewModelScope
import com.topjohnwu.magisk.BR
import com.topjohnwu.magisk.R
import com.topjohnwu.magisk.arch.AsyncLoadViewModel
import com.topjohnwu.magisk.core.Config
import com.topjohnwu.magisk.core.Info
import com.topjohnwu.magisk.core.di.AppContext
import com.topjohnwu.magisk.core.ktx.await
import com.topjohnwu.magisk.core.ktx.concurrentMap
import com.topjohnwu.magisk.databinding.bindExtra
import com.topjohnwu.magisk.databinding.filterList
import com.topjohnwu.magisk.databinding.set
import com.topjohnwu.magisk.utils.TextHolder
import com.topjohnwu.magisk.utils.asText
import com.topjohnwu.superuser.Shell
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.asFlow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.toCollection
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

class DenyListViewModel : AsyncLoadViewModel() {

    var isShowSystem = false
        set(value) {
            field = value
            doQuery(query)
        }

    var isShowOS = false
        set(value) {
            field = value
            doQuery(query)
        }

    var query = ""
        set(value) {
            field = value
            doQuery(value)
        }

    // --- Enforcement header state -------------------------------------------
    // A command runs ONLY through onEnforcePressed -> requestEnforcementLocked.
    // Every other write is programmatic bindable state and never triggers a
    // command (the switch binds one-way to enforcementEnabled; intent enters
    // only via onEnforcePressed, so a programmatic revert cannot re-enter).
    //
    // ALL shell work -- the initial status query AND every toggle -- runs on
    // viewModelScope under one Mutex. viewModelScope makes it cancellable on
    // fragment destroy (a raw .submit{} callback is not); the Mutex serializes
    // the status refresh against a toggle, so a slow status result cannot
    // overwrite a newer enable/disable. onResume re-runs the loader, so this
    // contention is a real lifecycle path.

    private val sulistMode get() = Info.sulist
    private val enforcementMutex = Mutex()

    @get:Bindable
    var enforcementEnabled = Info.sulist || Config.denyList   // conservative until status arrives
        private set(value) = set(value, field, { field = it },
            BR.enforcementEnabled, BR.enforceBanner, BR.bannerVisible, BR.switchEnabled)

    // Not @get:Bindable: only switchEnabled (below) reads it, and its setter
    // notifies BR.switchEnabled directly. Nothing binds enforcementUpdating.
    var enforcementUpdating = false
        private set(value) = set(value, field, { field = it }, BR.switchEnabled)

    // False when a status query failed -- an unknown initial state must not look
    // like a usable off control.
    @get:Bindable
    var enforcementAvailable = true
        private set(value) = set(value, field, { field = it }, BR.switchEnabled)

    // Non-null; empty string when there is no error. Prioritized in the banner.
    @get:Bindable
    var enforcementError: TextHolder = TextHolder.EMPTY
        private set(value) = set(value, field, { field = it },
            BR.enforcementError, BR.enforceBanner, BR.bannerVisible)

    // Locked-on in applied SuList mode (native forbids disable), disabled while a
    // command is in flight, and disabled when status is unavailable.
    @get:Bindable
    val switchEnabled get() = enforcementAvailable && !enforcementUpdating && !sulistMode

    @get:Bindable
    val enforceTitle: TextHolder get() =
        (if (sulistMode) R.string.settings_sulist_title
         else R.string.settings_denylist_title).asText()

    // Non-null (TextHolder.EMPTY when blank) -- the android:text adapter takes a
    // non-null TextHolder. Error wins, then the SuList lock, then the off hint.
    @get:Bindable
    val enforceBanner: TextHolder get() = when {
        !enforcementError.isEmpty -> enforcementError
        sulistMode -> R.string.denylist_sulist_locked_hint.asText()
        !enforcementEnabled -> R.string.denylist_off_hint.asText()
        else -> TextHolder.EMPTY
    }

    @get:Bindable
    val bannerVisible get() = !enforceBanner.isEmpty

    fun onEnforcePressed() {
        if (!switchEnabled) return
        viewModelScope.launch {
            enforcementMutex.withLock { requestEnforcementLocked(!enforcementEnabled) }
        }
    }

    private suspend fun requestEnforcementLocked(enabled: Boolean) {
        val previous = enforcementEnabled
        enforcementUpdating = true
        enforcementError = TextHolder.EMPTY
        try {
            val result = Shell.cmd(
                "magisk magiskhide ${if (enabled) "enable" else "disable"}").await()
            if (result.isSuccess) {
                enforcementEnabled = enabled
                Config.denyList = enabled
            } else {
                enforcementEnabled = previous
                enforcementError = R.string.denylist_enforce_error.asText()
            }
        } finally {
            enforcementUpdating = false
        }
    }

    // Authoritative status -- Config.denyList is a first-read cache reflecting
    // only THIS process. Ask the daemon. Exit 0 = enforced, 1 = NOT enforced
    // (normal), other = error. Do NOT collapse "other" into off, and do NOT use
    // result.isSuccess (exit 1 is normal, not a failure).
    private suspend fun refreshEnforcementState() {
        enforcementMutex.withLock {
            enforcementUpdating = true
            try {
                when (Shell.cmd("magisk magiskhide status").await().code) {
                    0 -> {
                        enforcementAvailable = true
                        enforcementEnabled = true
                        Config.denyList = true
                        enforcementError = TextHolder.EMPTY
                    }
                    1 -> {
                        enforcementAvailable = true
                        if (sulistMode) {
                            // Inconsistent: SuList applied but enforcement reports
                            // off -- native forbids that combination. Surface it.
                            enforcementError = R.string.denylist_status_error.asText()
                        } else {
                            enforcementEnabled = false
                            Config.denyList = false
                            enforcementError = TextHolder.EMPTY
                        }
                    }
                    else -> {
                        // Daemon/command error -- do NOT touch enforcementEnabled
                        // or Config.denyList; the last known value stands.
                        enforcementAvailable = false
                        enforcementError = R.string.denylist_status_error.asText()
                    }
                }
            } finally {
                enforcementUpdating = false
            }
        }
    }

    val items = filterList<DenyListRvItem>(viewModelScope)
    val extraBindings = bindExtra {
        it.put(BR.viewModel, this)
    }

    @get:Bindable
    var loading = true
        private set(value) = set(value, field, { field = it }, BR.loading)

    @SuppressLint("InlinedApi")
    override suspend fun doLoadWork() {
        refreshEnforcementState()
        loading = true
        val apps = withContext(Dispatchers.Default) {
            val pm = AppContext.packageManager
            val denyList = Shell.cmd("magisk magiskhide ls").exec().out
                .map { CmdlineListItem(it) }
            val apps = pm.getInstalledApplications(MATCH_UNINSTALLED_PACKAGES).run {
                asFlow()
                    .filter { AppContext.packageName != it.packageName }
                    .concurrentMap { AppProcessInfo(it, pm, denyList) }
                    .filter { it.processes.isNotEmpty() }
                    .concurrentMap { DenyListRvItem(it) }
                    .toCollection(ArrayList(size))
            }
            apps.sort()
            apps
        }
        items.set(apps)
        doQuery(query)
    }

    private fun doQuery(s: String) {
        items.filter {
            fun filterSystem() = isShowSystem || !it.info.isSystemApp()

            fun filterOS() = (isShowSystem && isShowOS) || it.info.isApp()

            fun filterQuery(): Boolean {
                fun inName() = it.info.label.contains(s, true)
                fun inPackage() = it.info.packageName.contains(s, true)
                fun inProcesses() = it.processes.any { p -> p.process.name.contains(s, true) }
                return inName() || inPackage() || inProcesses()
            }

            (it.isChecked || (filterSystem() && filterOS())) && filterQuery()
        }
        loading = false
    }
}
