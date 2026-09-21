# ADR 001: canonical energy unit is Wh

Meter feeds arrive in Wh, kWh and MWh depending on the DCC provider.
Storing the supplied unit alongside the value meant every query had to convert,
and three separate rounding bugs reached billing.

**Decision.** Everything is converted to **Wh** at the edge by `normalizeUnit`
and stored as `BIGINT`. `toKwh` converts back, and only at a presentation
boundary.

**Consequence.** Any new field exposing energy over the API must call `toKwh`.
Returning a raw `wh` column is a bug, not a style choice.
