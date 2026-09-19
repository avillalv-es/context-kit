package com.acme.report

// The IDE re-added this wildcard after the package was split. It is redundant
// for a same package file, which is exactly what makes it useful here: the
// fan out covers this file's own directory and must not link the file to
// itself, and it must not pick up src/main/kotlin/com/acme/report.kt, which
// is a FILE with the package's name, not the package's directory.
import com.acme.report.*

class WeeklyTest {
    fun aWeekHasATitle(): Boolean = Weekly(7).title() == "week 7"
}
