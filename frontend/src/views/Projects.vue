<template>
  <div class="container">
    <header>
      <span>{{ auth.user?.name }}</span>
      <button @click="onLogout">Sign out</button>
    </header>
    <h1>Projects</h1>
    <p>Coming next.</p>
    <p><router-link to="/">← Back</router-link></p>
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
