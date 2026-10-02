<script setup lang="ts">
import { useUser } from '@/stores/user'
import StatusBadge from './StatusBadge.vue'

const user = useUser()
</script>

<template>
  <section>
    <StatusBadge :label="user.name" />
  </section>
</template>
