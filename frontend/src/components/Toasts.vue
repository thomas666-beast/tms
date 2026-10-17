<template>
  <div class="toast-stack">
    <div
      v-for="t in toast.items"
      :key="t.id"
      :class="['toast', 'toast-' + t.kind]"
    >{{ t.message }}</div>
  </div>
</template>

<script setup>
import { useToastStore } from '../stores/toast'
const toast = useToastStore()
</script>
