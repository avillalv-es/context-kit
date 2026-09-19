---
description: See the context layout as a graph - build it, serve it, or export an Obsidian vault
---

Use the `context-graph` skill.

With no argument, build the graph and report what it found. Recognised
arguments, passed through:

- `serve` — build, then serve it on http://127.0.0.1:8848
- `vault` — export an Obsidian vault of wikilinked notes
- `open` — print the `file://` URL for the viewer
- `--port N`, `--host H`, `--dir DIR`, `--out DIR` — passed straight through

Report the findings. Change nothing unless asked.

Argument, if any: $ARGUMENTS
