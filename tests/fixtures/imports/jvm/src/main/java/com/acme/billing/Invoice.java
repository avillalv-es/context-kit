package com.acme.billing;

import com.acme.util.Money;
import java.time.Instant;

/** One invoice, plus the nested line type other packages import directly. */
public final class Invoice {

    /** Imported elsewhere as com.acme.billing.Invoice.Line. */
    public static final class Line {

        /** Imported elsewhere as com.acme.billing.Invoice.Line.Kind: a type
         *  nested TWO levels deep, so one member strip is not enough. */
        public enum Kind { GOODS, SERVICE }

        public final String sku;
        public final Money amount;
        public final Kind kind;

        public Line(String sku, Money amount, Kind kind) {
            this.sku = sku;
            this.amount = amount;
            this.kind = kind;
        }
    }

    public final String id;
    public final Instant issuedAt;

    public Invoice(String id, Instant issuedAt) {
        this.id = id;
        this.issuedAt = issuedAt;
    }
}
