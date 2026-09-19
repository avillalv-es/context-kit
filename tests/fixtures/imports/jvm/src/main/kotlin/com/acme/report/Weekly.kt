package com.acme.report

/** A class whose name DOES mirror its file name, so it is reachable. */
class Weekly(private val week: Int) {
    fun title(): String = "week $week"
}

/** A top level function. Reachable only with a symbol index. */
fun renderAll(weeks: List<Weekly>): String = weeks.joinToString { it.title() }
