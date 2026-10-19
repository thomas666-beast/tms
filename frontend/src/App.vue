<template>
  <component :is="layout">
    <router-view />
  </component>
  <Toasts />
</template>

<script setup>
import { computed, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { useDarkMode } from './composables/useDarkMode'
import AppShell from './components/AppShell.vue'
import BlankLayout from './components/BlankLayout.vue'
import Toasts from './components/Toasts.vue'

const route = useRoute()
const { initTheme } = useDarkMode()

const layout = computed(() => route.meta.public ? BlankLayout : AppShell)

onMounted(() => {
  initTheme()
})
</script>
