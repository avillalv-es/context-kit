"""Test-only helpers.

``from . import text`` with a trailing comment: the comment has to come off
before the imported name is read, or the name becomes
``text  # noqa: F401`` and resolves to nothing.
"""

from . import text  # noqa: F401 - re-exported for convenience
