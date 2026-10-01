## Blast radius

Before a structural edit, use the `blast-radius` skill on the symbol or file and
read every depth-1 importer it lists. Structural means: changing an exported
function, type, class or signature; renaming, moving or deleting a file or
export; changing a shared module, schema, config key or route. Before
committing, run it on the diff and run the tests it names. A body-only change
inside one function does not need it.

Turn this off with `/context-init off blast-radius`.
