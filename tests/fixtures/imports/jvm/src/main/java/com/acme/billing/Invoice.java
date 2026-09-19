package com.acme.billing;

import com.acme.util.Money;
import java.time.Instant;

/** One invoice, plus the nested line type other packages import directly. */
public final class Invoice {

    /** Imported elsewhere as com.acme.billing.Invoice.Line. */
    public static final class Line {
        public final String sku;
        public final Money amount;

        public Line(String sku, Money amount) {
            this.sku = sku;
            this.amount = amount;
        }
    }

    public final String id;
    public final Instant issuedAt;

    public Invoice(String id, Instant issuedAt) {
        this.id = id;
        this.issuedAt = issuedAt;
    }
}
