---
description: Set or show the lean execution level (lite/full/ultra/off)
---

Use the `lean-execution` skill.

The session-start hook already handled the level change if the message was
exactly `/lean lite`, `/lean full`, `/lean ultra` or `/lean off`. In that case
confirm the new level in one line and stop.

Otherwise explain the levels and what each one changes, briefly.

Argument, if any: $ARGUMENTS
