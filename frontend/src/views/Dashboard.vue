<template>
  <div class="container">
    <header>
      <span>{{ auth.user?.name }} <small>({{ auth.user?.role }})</small></span>
      <button @click="onLogout">Sign out</button>
    </header>
    <h1>Dashboard</h1>
    <p>Nothing here yet. <router-link to="/projects">Go to projects →</router-link></p>
  </div>
</template>

<script setup>
import { useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const auth = useAuthStore()
const router = useRouter()

async function onLogout() {
  await auth.logout()
  router.push('/login')
}
</script>
