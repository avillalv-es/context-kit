"""Output adapters, registered by name.

The import below is the parenthesised form of ``from . import a, b``. The
module part of the statement is ``.`` on the first physical line and the two
names that actually identify the imported modules are on the lines after it.
This is the one Python import form where the first physical line is not
enough: an extractor that never joins lines resolves ``.`` to this very file
and emits a self-edge, which it then drops, losing both real edges without
reporting anything.
"""

from . import (
    csv_adapter,
    json_adapter,
)

__all__ = ["csv_adapter", "json_adapter"]
