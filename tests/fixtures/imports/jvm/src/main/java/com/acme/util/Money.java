package com.acme.util;

import java.math.BigDecimal;
import java.util.Objects;

/** An immutable money amount. Leaf of the fixture graph: it imports nothing internal. */
public final class Money {

    public static final Money ZERO = new Money(BigDecimal.ZERO, "USD");

    private final BigDecimal amount;
    private final String currency;

    public Money(BigDecimal amount, String currency) {
        this.amount = Objects.requireNonNull(amount);
        this.currency = Objects.requireNonNull(currency);
    }

    public Money plus(Money other) {
        return new Money(amount.add(other.amount), currency);
    }

    @Override
    public String toString() {
        return currency + " " + amount;
    }
}
