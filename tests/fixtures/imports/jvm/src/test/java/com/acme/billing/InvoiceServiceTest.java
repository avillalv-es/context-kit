package com.acme.billing;

import static com.acme.util.Money.ZERO;
import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

/** Same package as the class under test, so InvoiceService needs no import. */
final class InvoiceServiceTest {

    @Test
    void anEmptyInvoiceCostsNothing() {
        InvoiceService service = new InvoiceService();
        assertEquals(ZERO.toString(), service.total(service.lines("")).toString());
    }
}
