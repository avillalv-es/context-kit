package com.acme.app

import com.acme.billing./* renamed from Cipher in 2024 */Codec
import com.acme.util.Codec as UtilCodec
import com.acme.billing.Invoice.Line.Kind
import com.acme.report.Weekly
import com.acme.report.renderAll
import com.acme.proto.Ticket

/**
 * Two classes named Codec, a type nested two levels deep, one reachable
 * member of com.acme.report, one unreachable one, and one ambiguous name.
 */
class Dashboard {

    private val wire = Codec()
    private val text = UtilCodec()

    // Not an import declaration. An unanchored search for the word "import"
    // finds it, and the string it holds is a real fully qualified class.
    private val importPath = "com.acme.billing.InvoiceService"

    fun render(ticket: Ticket, weeks: List<Weekly>, kind: Kind): String =
        wire.encode(ticket.id) + " " + kind + " " +
            text.encode(renderAll(weeks)) + " " + importPath
}
