package com.acme.util

import java.util.Locale

// One file, three top level declarations, none of them named Strings. A file
// level resolver can find this file from "com.acme.util.Strings" only; the
// names below are invisible to it.

private val NON_ALNUM = Regex("[^a-z0-9]+")

fun slugify(raw: String): String =
    NON_ALNUM.replace(raw.lowercase(Locale.ROOT), "-").trim('-')

data class Slug(val value: String) {
    override fun toString(): String = value
}

object Casing {
    fun shout(raw: String): String = raw.uppercase(Locale.ROOT)
}
