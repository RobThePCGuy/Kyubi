package com.topjohnwu.magisk.ui.install

import android.os.Bundle
import android.os.Parcelable
import android.text.Spanned
import android.text.SpannedString
import androidx.databinding.Bindable
import androidx.lifecycle.viewModelScope
import com.topjohnwu.magisk.BR
import com.topjohnwu.magisk.BuildConfig
import com.topjohnwu.magisk.arch.BaseViewModel
import com.topjohnwu.magisk.core.Const
import com.topjohnwu.magisk.core.Info
import com.topjohnwu.magisk.core.di.AppContext
import com.topjohnwu.magisk.core.repository.NetworkService
import com.topjohnwu.magisk.databinding.set
import com.topjohnwu.magisk.ui.flash.FlashFragment
import io.noties.markwon.Markwon
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.parcelize.Parcelize
import timber.log.Timber
import java.io.File
import java.io.IOException

class InstallViewModel(svc: NetworkService, markwon: Markwon) : BaseViewModel() {

    val isRooted get() = Info.isRooted
    val allowSystemInstall = isRooted

    private var methodId = -1

    @get:Bindable
    var method
        get() = methodId
        set(value) = set(value, methodId, { methodId = it }, BR.method)

    @get:Bindable
    var notes: Spanned = SpannedString("")
        set(value) = set(value, field, { field = it }, BR.notes)

    init {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val file = File(AppContext.cacheDir, "${BuildConfig.VERSION_CODE}.md")
                val text = when {
                    file.exists() -> file.readText()
                    Const.Url.CHANGELOG_URL.isEmpty() -> ""
                    else -> {
                        val str = svc.fetchString(Const.Url.CHANGELOG_URL)
                        file.writeText(str)
                        str
                    }
                }
                val spanned = markwon.toMarkdown(text)
                withContext(Dispatchers.Main) {
                    notes = spanned
                }
            } catch (e: IOException) {
                Timber.e(e)
            }
        }
    }

    fun install() {
        FlashFragment.flash(2).navigate(true)
    }

    override fun onSaveState(state: Bundle) {
        state.putParcelable(INSTALL_STATE_KEY, InstallState(methodId))
    }

    override fun onRestoreState(state: Bundle) {
        state.getParcelable<InstallState>(INSTALL_STATE_KEY)?.let {
            methodId = it.method
        }
    }

    @Parcelize
    class InstallState(
        val method: Int,
    ) : Parcelable

    companion object {
        private const val INSTALL_STATE_KEY = "install_state"
    }
}
