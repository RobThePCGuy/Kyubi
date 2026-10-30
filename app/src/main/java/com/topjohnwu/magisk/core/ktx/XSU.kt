package com.topjohnwu.magisk.core.ktx

import com.topjohnwu.superuser.Shell
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

suspend fun Shell.Job.await() = withContext(Dispatchers.IO) { exec() }
