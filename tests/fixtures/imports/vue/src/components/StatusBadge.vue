<script>
import { formatName } from '~lib/format'

export default {
  props: { label: { type: String, required: true } },
  computed: {
    pretty() {
      return formatName(this.label)
    },
  },
}
</script>

<template>
  <span>{{ pretty }}</span>
</template>
