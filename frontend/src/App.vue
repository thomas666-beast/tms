<template>
  <component :is="layout">
    <router-view />
  </component>
  <Toasts />
</template>

<script setup>
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import AppShell from './components/AppShell.vue'
import BlankLayout from './components/BlankLayout.vue'
import Toasts from './components/Toasts.vue'

const route = useRoute()
const layout = computed(() => route.meta.public ? BlankLayout : AppShell)
</script>
