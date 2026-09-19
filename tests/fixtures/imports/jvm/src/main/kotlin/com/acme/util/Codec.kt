package com.acme.util

// Same basename as src/main/java/com/acme/billing/Codec.java, different
// package. Only the package components tell the two apart.
class Codec {
    fun encode(raw: String): String = raw.trim()
}
