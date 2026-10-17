<template>
  <div class="container">
    <header>
      <span>{{ auth.user?.name }} <small>({{ auth.user?.role }})</small></span>
      <button @click="onLogout">{{ t('nav.signOut') }}</button>
    </header>
    <h1>{{ t('dashboard.title') }}</h1>
    <p>
      <router-link to="/projects">{{ t('nav.projects') }}</router-link>
      <template v-if="auth.user?.role === 'admin'">
        · <router-link to="/users">{{ t('nav.users') }}</router-link>
      </template>
    </p>
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
