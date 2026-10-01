// Every import below must stay UNRESOLVED. Each names a file that exists, but
// reaches it through an alias that is not readable as a literal:
//   @api    - declared in vite.config.ts, but its value is a variable
//   @old    - declared only inside a comment in tsconfig.app.json
//   @legacy - declared only inside a comment in vite.config.ts
import { client } from '@api/client'
import { legacy } from '@old/legacy'
import { legacy as again } from '@legacy/legacy'

export const skipped = [client, legacy, again]
