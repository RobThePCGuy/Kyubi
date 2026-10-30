package com.topjohnwu.magisk.dialog

import com.topjohnwu.magisk.R
import com.topjohnwu.magisk.events.DialogBuilder
import com.topjohnwu.magisk.view.MagiskDialog

// Kyubi runs on emulators, where a reboot requested from inside Android does
// not come back (BlueStacks' player hangs; MEmu's kernel faults in shutdown).
// Closing and reopening the emulator is the restart, so tell the user that
// instead of issuing a reboot.
class RestartEmulatorDialog : DialogBuilder {

    override fun build(dialog: MagiskDialog) {
        dialog.apply {
            setTitle(R.string.restart_emulator_title)
            setMessage(R.string.restart_emulator_msg)
            setButton(MagiskDialog.ButtonType.POSITIVE) {
                text = android.R.string.ok
            }
        }
    }
}
