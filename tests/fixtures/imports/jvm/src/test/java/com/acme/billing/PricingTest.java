package com.acme.billing;

/*
 * The 2024 generator opened a Java text block here with """ and emitted
 *     import com.acme.report.Weekly;
 * into it. Both the block and the generator are gone. Nothing in this
 * comment is a dependency, and the real imports below must survive it:
 * a stripper that reacts to the """ above before it notices it is already
 * inside a block comment opens a raw string that never closes, swallows the
 * rest of this file, and silently loses both edges below.
 */

import static com.acme.util.Money.*;
import com.acme.util
        .Codec;
import org.junit.jupiter.api.Test;

/** Same package as PricingRules, so that needs no import declaration. */
final class PricingTest {

    @Test
    void zeroEncodesToSomething() {
        Codec text = new Codec();
        com.acme.billing.Codec wire = new com.acme.billing.Codec();
        assert text.encode(wire.encode(ZERO.toString())) != null;
    }
}
