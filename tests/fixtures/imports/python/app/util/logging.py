"""Project logger helper.

The filename shadows the stdlib ``logging`` module on purpose. It is the
commonest way a repo file gets wired to a stdlib import by accident: a
resolver that falls back to a unique-basename search finds exactly one
``logging.py`` in the tree and calls it the target of ``import logging``.

The import below is the stdlib module, reached by absolute import from
inside the file that shadows it - so the only honest outcome is no edge at
all, and specifically not a self-edge.
"""

import logging as _stdlib_logging

FORMAT = "%(name)s %(levelname)s %(message)s"


def get_logger(name: str):
    return _stdlib_logging.getLogger(name)
