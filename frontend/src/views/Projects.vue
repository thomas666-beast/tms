<template>
  <div class="container">
    <header>
      <span>{{ auth.user?.name }}</span>
      <button @click="onLogout">{{ t('nav.signOut') }}</button>
    </header>
    <h1>{{ t('projects.title') }}</h1>
    <p>{{ t('projects.empty') }}</p>
    <p><router-link to="/">{{ t('projects.back') }}</router-link></p>
  </div>
</template>

<script setup>
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '../stores/auth'

const { t } = useI18n()
const auth = useAuthStore()
const router = useRouter()

async function onLogout() {
  await auth.logout()
  router.push('/login')
}
</script>
