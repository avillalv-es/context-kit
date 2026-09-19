package com.acme.billing;

/*
 * Ported from the 2023 service, which opened with:
 *     import com.acme.util.Strings;
 * The helper moved to Kotlin and that call site is gone.
 */

import com.acme.util.Money;
import com.acme.util.Slug;
import java.util.ArrayList;
import java.util.List;

/**
 * Builds invoice lines. Invoice is in this same package, so there is no
 * import declaration for it and therefore no file level edge to Invoice.java.
 */
public final class InvoiceService {

    public List<Invoice.Line> lines(String sku) {
        List<Invoice.Line> out = new ArrayList<>();
        out.add(new Invoice.Line(sku, Money.ZERO));
        return out;
    }

    public Money total(List<Invoice.Line> lines) {
        Money sum = Money.ZERO;
        for (Invoice.Line line : lines) {
            sum = sum.plus(line.amount);
        }
        return sum;
    }

    public Slug slugFor(Invoice invoice) {
        return new Slug(invoice.id);
    }
}
