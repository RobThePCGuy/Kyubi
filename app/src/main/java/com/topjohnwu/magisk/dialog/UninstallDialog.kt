package com.topjohnwu.magisk.dialog

import com.topjohnwu.magisk.R
import com.topjohnwu.magisk.arch.NavigationActivity
import com.topjohnwu.magisk.events.DialogBuilder
import com.topjohnwu.magisk.ui.flash.FlashFragment
import com.topjohnwu.magisk.view.MagiskDialog

class UninstallDialog : DialogBuilder {

    // Kyubi is system-mode only: there is no patched boot image to restore, so
    // the "Restore Images" path (restore_imgs) is removed. Only the complete
    // uninstall remains.
    override fun build(dialog: MagiskDialog) {
        dialog.apply {
            setTitle(R.string.uninstall_magisk_title)
            // The app removes itself, so this is the last chance to say how
            // to finish: the uninstaller no longer reboots the emulator.
            setMessage(context.getString(R.string.uninstall_magisk_msg) + "\n\n" +
                context.getString(R.string.uninstall_restart_note))
            setButton(MagiskDialog.ButtonType.POSITIVE) {
                text = R.string.complete_uninstall
                onClick { completeUninstall(dialog) }
            }
        }
    }

    private fun completeUninstall(dialog: MagiskDialog) {
        (dialog.ownerActivity as NavigationActivity<*>)
            .navigation.navigate(FlashFragment.uninstall())
    }

}
