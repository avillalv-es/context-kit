<script setup lang="ts">
import { computed } from 'vue'
import UserCard from '@/components/UserCard.vue'
import { StatusBadge } from '@/components'
// import Ghost from '@/components/Ghost.vue'
const hint = "import Ghost from '@/components/Ghost.vue'"
const sample = `
import Ghost from '@/components/Ghost.vue'
`

const title = computed(() => 'Dashboard' + hint.length + sample.length)
</script>

<template>
  <h1>{{ title }}</h1>
  <UserCard />
  <StatusBadge label="ready" />
</template>

<style scoped>
h1 {
  font-weight: 600;
}
</style>
