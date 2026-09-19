package com.acme

// The reporting code used to live in this one file. It is being split into
// the com.acme.report PACKAGE (src/main/kotlin/com/acme/report/), and during
// the migration the file and the directory sit side by side. Legal, and the
// reason "com.acme.report.<lowercase member>" is a trap: stripping the last
// segment lands on this file, which has nothing to do with the member.

fun legacyReport(sku: String): String = "legacy:$sku"
