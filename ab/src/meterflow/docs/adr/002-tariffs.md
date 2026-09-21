# ADR 002: tariff precedence

A site can have several tariffs active on the same day during a switch.

**Decision.** Precedence is `capacity` > `timeOfUse` > `fixed`. Where two of
the same kind overlap, the one with the later `validFrom` wins.

**Consequence.** `activeTariffs` returns candidates in no particular order.
Callers must apply the precedence themselves; taking the first element is
wrong and produces silent undercharging.
