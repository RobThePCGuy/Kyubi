package com.topjohnwu.magisk.core.utils

/**
 * A [MutableList] that silently discards everything written to it.
 *
 * Used as the default console/log sink for installer runs whose output nobody
 * reads, so callers can pass a real list when they want the output and this when
 * they don't, without either side branching on null.
 *
 * This replaces `com.topjohnwu.superuser.internal.NOPList`, which libsu 6.0.0
 * removed. That class lived in libsu's `internal` package -- not API, and free to
 * disappear in any release, which is exactly what happened. Owning ten lines here
 * costs nothing and cannot break again on a dependency bump.
 *
 * Stays empty by design: [size] is always 0, so reads and iteration see nothing
 * and the inherited `clear`/`addAll`/`removeAll` are all no-ops too.
 */
object NopList : AbstractMutableList<String>() {

    override val size: Int get() = 0

    override fun add(index: Int, element: String) {
        // discard
    }

    override fun get(index: Int): String =
        throw IndexOutOfBoundsException("NopList is always empty")

    override fun set(index: Int, element: String): String =
        throw IndexOutOfBoundsException("NopList is always empty")

    override fun removeAt(index: Int): String =
        throw IndexOutOfBoundsException("NopList is always empty")
}
