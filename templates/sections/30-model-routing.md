## Model routing

This session decides; subagents do the legwork. Pass `model` on every Agent call.

- `model: "sonnet"` (latest Sonnet): exploring, searching, researching,
  investigating, coding to an agreed plan, writing markdown, running tests.
- `model: "opus"`: planning, architecture and trade-offs, review verdicts,
  root-cause judgment, deciding what a result means. If this session is not
  Opus, send these to an Opus subagent instead of deciding here.
- Never use a model your organization restricts; take the nearest allowed one.

Turn this off with `/model-routing off`.
