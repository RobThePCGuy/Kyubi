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

    val isSelected get() = Config.themeOrdinal == ordinal

    fun select() {
        Config.themeOrdinal = ordinal
    }

    companion object {
        val selected get() = values().getOrNull(Config.themeOrdinal) ?: Kyubi
    }

}
