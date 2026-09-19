package com.acme.app

import com.acme.billing.PricingRules
import com.acme.util.Money as Amount
import com.acme.util.slugify
import com.fasterxml.jackson.databind.ObjectMapper

/** Renders a one line report. */
class Reporter(private val mapper: ObjectMapper = ObjectMapper()) {

    private val help = """
        usage: report <sku>
        to call this from Kotlin code instead, write
        import com.acme.billing.InvoiceService
    """.trimIndent()

    fun render(sku: String): String {
        val rules = PricingRules()
        val total: Amount = rules.priceFor(sku)
        return mapper.writeValueAsString(mapOf(slugify(sku) to total.toString())) + help
    }
}
