package com.acme.billing

import com.acme.util.*
import kotlinx.coroutines.flow.Flow

// import com.acme.billing.Invoice   // dropped when the rules stopped needing the header

/*
 * Before the 2024 rewrite this file also had:
 *     import com.acme.legacy.RateTable
 */

class PricingRules(private val label: String = Casing.shout("standard")) {

    fun priceFor(sku: String): Money = if (sku.isEmpty()) Money.ZERO else Money.ZERO

    fun tag(sku: String): Slug = Slug(slugify(label + "-" + sku))

    fun stream(): Flow<Money>? = null
}
