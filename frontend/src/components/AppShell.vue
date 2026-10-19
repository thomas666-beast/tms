<template>
  <div class="shell">
    <aside class="sidebar" :class="{ 'sidebar-collapsed': collapsed }">
      <div class="brand">
        <span class="brand-mark">T</span>
        <span class="brand-name" v-if="!collapsed">{{ t('app.name') }}</span>
      </div>

      <nav class="nav">
        <router-link to="/" class="nav-link" active-class="active" exact-active-class="active" :title="t('nav.dashboard')">
          <span class="nav-icon">◉</span>
          <span v-if="!collapsed">{{ t('nav.dashboard') }}</span>
        </router-link>
        <router-link to="/projects" class="nav-link" active-class="active" :title="t('nav.projects')">
          <span class="nav-icon">▤</span>
          <span v-if="!collapsed">{{ t('nav.projects') }}</span>
        </router-link>
        <router-link v-if="isAdmin" to="/users" class="nav-link" active-class="active" :title="t('nav.users')">
          <span class="nav-icon">◍</span>
          <span v-if="!collapsed">{{ t('nav.users') }}</span>
        </router-link>
      </nav>

      <div class="sidebar-user">
        <div class="user-meta" v-if="!collapsed">
          <router-link to="/profile" class="user-name" style="text-decoration: none; color: inherit;">
            {{ auth.user?.name }}
          </router-link>
          <div class="user-role">{{ auth.user?.role }}</div>
        </div>
        <button @click="onLogout" class="ghost small" :title="t('nav.signOut')">
          <span class="nav-icon">⏻</span>
          <span v-if="!collapsed">{{ t('nav.signOut') }}</span>
        </button>
      </div>
    </aside>

    <main class="content">
      <div class="content-topbar">
        <button @click="collapsed = !collapsed" class="ghost small" title="Toggle Sidebar">
          ☰
        </button>
        
        <div class="row-actions">
          <button @click="toggleTheme" class="ghost small" :title="isDark ? 'Light mode' : 'Dark mode'">
            {{ isDark ? '☀' : '☾' }}
          </button>
          <NotificationsBell />
        </div>
      </div>
      <slot />
    </main>
  </div>
</template>

<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '../stores/auth'
import { useNotificationsStore } from '../stores/notifications'
import { useDarkMode } from '../composables/useDarkMode'
import NotificationsBell from './NotificationsBell.vue'

const { t } = useI18n()
const auth = useAuthStore()
const router = useRouter()
const notifs = useNotificationsStore()
const { isDark, toggle: toggleTheme } = useDarkMode()

const collapsed = ref(false)
const isAdmin = computed(() => auth.user?.role === 'admin')

async function onLogout() {
  notifs.stopPolling()
  await auth.logout()
  router.push('/login')
}

onMounted(() => notifs.startPolling())
onUnmounted(() => notifs.stopPolling())
</script>
