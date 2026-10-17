<template>
  <div class="shell">
    <aside class="sidebar">
      <div class="brand">
        <span class="brand-mark">T</span>
        <span class="brand-name">{{ t('app.name') }}</span>
      </div>

      <nav class="nav">
        <router-link to="/" class="nav-link" active-class="active" exact-active-class="active">
          {{ t('nav.dashboard') }}
        </router-link>
        <router-link to="/projects" class="nav-link" active-class="active">
          {{ t('nav.projects') }}
        </router-link>
        <router-link v-if="isAdmin" to="/users" class="nav-link" active-class="active">
          {{ t('nav.users') }}
        </router-link>
      </nav>

      <div class="sidebar-user">
        <div class="user-meta">
          <div class="user-name">{{ auth.user?.name }}</div>
          <div class="user-role">{{ auth.user?.role }}</div>
        </div>
        <button @click="onLogout" class="ghost small">{{ t('nav.signOut') }}</button>
      </div>
    </aside>

    <main class="content">
      <slot />
    </main>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '../stores/auth'

const { t } = useI18n()
const auth = useAuthStore()
const router = useRouter()
const isAdmin = computed(() => auth.user?.role === 'admin')

async function onLogout() {
  await auth.logout()
  router.push('/login')
}
</script>
