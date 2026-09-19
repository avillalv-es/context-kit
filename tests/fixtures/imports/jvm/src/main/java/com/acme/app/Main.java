package com.acme.app;

import com.acme.billing.Invoice.Line;
import com.acme.billing.InvoiceService;
// Wrapped by an old formatter. This is still one import declaration.
import com.acme.util.
        Money;
import java.util.List;

/** Command line entry point. */
public final class Main {

    /**
     * Printed by --emit-stub. Everything inside the text block is template
     * data, not a dependency of this file.
     */
    private static final String STUB = """
            package com.acme.app;
            import com.acme.billing.PricingRules;

            public final class Stub {
            }
            """;

    private Main() {
    }

    public static void main(String[] args) {
        InvoiceService service = new InvoiceService();
        List<Line> lines = service.lines(args.length > 0 ? args[0] : "none");
        Money total = service.total(lines);
        System.out.println(total + (args.length > 1 ? STUB : ""));
    }
}
