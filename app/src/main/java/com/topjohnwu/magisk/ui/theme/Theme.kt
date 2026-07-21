package com.topjohnwu.magisk.ui.theme

import com.topjohnwu.magisk.R
import com.topjohnwu.magisk.core.Config

enum class Theme(
    val themeName: String,
    val themeRes: Int
) {

    Kyubi(
        themeName = "Kyubi",
        themeRes = R.style.ThemeFoundationMD2_Kyubi
    ),
    KyubiAmoled(
        themeName = "Kyubi AMOLED",
        themeRes = R.style.ThemeFoundationMD2_KyubiAmoled
    );

    // Compare against the resolved `selected` (which falls back to Kyubi for an
    // out-of-range stored ordinal from the pruned theme set), not the raw ordinal
    // -- otherwise an upgrading user with an old ordinal shows nothing selected.
    val isSelected get() = selected == this

    fun select() {
        Config.themeOrdinal = ordinal
    }

    companion object {
        val selected get() = values().getOrNull(Config.themeOrdinal) ?: Kyubi
    }

}
