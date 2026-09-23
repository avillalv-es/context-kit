<template>
  <div class="report">
    <p>
      To get started, first
      import your data from "CSV" files
      and click Run.
    </p>
  </div>
</template>

<script>
import { x } from './lib/b';

export default {
  name: 'Report',
  computed: {
    total() {
      return x;
    },
  },
};
</script>
