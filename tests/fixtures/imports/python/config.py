"""Developer-machine overrides. Deliberately NOT ``app/config.py``.

This module is a decoy and nothing in the fixture imports it. It exists so
that two resolver mistakes have somewhere wrong to land:

1. a relative import that climbs past the top of the ``app`` package ends up
   at the repo root, where a module named ``config`` now exists;
2. a resolver that matches a module's last dotted segment against file
   basenames sees two candidates for ``config`` instead of one.

Both are silent: they produce a plausible edge to a real file.
"""

DEBUG = False
LOG_LEVEL = "warning"
