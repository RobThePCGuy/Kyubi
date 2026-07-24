package com.topjohnwu.magisk.core.repository

import com.topjohnwu.magisk.core.Config
import com.topjohnwu.magisk.core.Config.Value.PRERELEASE_CHANNEL
import com.topjohnwu.magisk.core.Info
import com.topjohnwu.magisk.core.data.GithubPageServices
import com.topjohnwu.magisk.core.data.RawServices
import retrofit2.HttpException
import timber.log.Timber
import java.io.IOException

class NetworkService(
    private val pages: GithubPageServices,
    private val raw: RawServices
) {
    suspend fun fetchUpdate() = safe {
        if (Config.updateChannel == PRERELEASE_CHANNEL)
            pages.fetchUpdateJSON("prerelease.json")
        else
            pages.fetchUpdateJSON("stable.json")
    }

    private inline fun <T> safe(factory: () -> T): T? {
        return try {
            if (Info.isConnected.value == true)
                factory()
            else
                null
        } catch (e: Exception) {
            Timber.e(e)
            null
        }
    }

    private inline fun <T> wrap(factory: () -> T): T {
        return try {
            factory()
        } catch (e: HttpException) {
            throw IOException(e)
        }
    }

    // Fetch files
    suspend fun fetchFile(url: String) = wrap { raw.fetchFile(url) }
    suspend fun fetchString(url: String) = wrap { raw.fetchString(url) }
    suspend fun fetchModuleJson(url: String) = wrap { raw.fetchModuleJson(url) }
}
