<template>
  <div class="container-wide">
    <div class="row">
      <h1>{{ t('dashboard.title') }}</h1>
    </div>

    <p v-if="loading">{{ t('common.loading') }}</p>
    <p v-else-if="error" class="error">{{ error }}</p>

    <template v-else>
      <div v-if="showGettingStarted" class="getting-started">
        <h2>{{ t('dashboard.gettingStartedTitle') }}</h2>
        <p>{{ t('dashboard.gettingStartedBody') }}</p>
        <router-link to="/projects" class="btn-link" style="display:inline-block; margin-top:8px;">
          {{ t('dashboard.gettingStartedCta') }}
        </router-link>
      </div>

      <!-- Notifications -->
      <section class="panel">
        <h2>{{ t('dashboard.notificationsTitle') }}</h2>
        <p v-if="!notifs.items.length" class="muted">{{ t('dashboard.notificationsEmpty') }}</p>
        <ul v-else class="notif-list">
          <li v-for="n in notifs.items.slice(0, 5)" :key="n.id" class="notif-item" @click="openNotif(n)">
            <span class="notif-type">{{ t('notifications.types.' + n.type) }}</span>
            <span v-if="n.payload.project_name" class="muted">— {{ n.payload.project_name }}</span>
          </li>
        </ul>
      </section>

      <!-- Assigned to me -->
      <section class="panel">
        <h2>{{ t('dashboard.assignedTitle') }}</h2>
        <p v-if="!assigned.length" class="muted">{{ t('dashboard.assignedEmpty') }}</p>
        <table v-else class="table">
          <thead>
            <tr>
              <th>{{ t('dashboard.columns.name') }}</th>
              <th>{{ t('dashboard.columns.project') }}</th>
              <th>{{ t('dashboard.columns.target') }}</th>
              <th>{{ t('dashboard.columns.status') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="f in assigned" :key="'a-'+f.id" class="clickable" @click="openFile(f.id)">
              <td>{{ f.name }}</td>
              <td>{{ f.project_name }}</td>
              <td>{{ f.target_lang }}</td>
              <td><span class="badge">{{ f.status }}</span></td>
            </tr>
          </tbody>
        </table>
      </section>

      <!-- Waiting for my review -->
      <section class="panel">
        <h2>{{ t('dashboard.reviewableTitle') }}</h2>
        <p v-if="!reviewable.length" class="muted">{{ t('dashboard.reviewableEmpty') }}</p>
        <table v-else class="table">
          <thead>
            <tr>
              <th>{{ t('dashboard.columns.name') }}</th>
              <th>{{ t('dashboard.columns.project') }}</th>
              <th>{{ t('dashboard.columns.target') }}</th>
              <th>{{ t('dashboard.columns.approvals') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="f in reviewable" :key="'r-'+f.id" class="clickable" @click="openFile(f.id)">
              <td>{{ f.name }}</td>
              <td>{{ f.project_name }}</td>
              <td>{{ f.target_lang }}</td>
              <td>{{ f.approval_count }}</td>
            </tr>
          </tbody>
        </table>
      </section>

      <!-- Recently approved -->
      <section class="panel">
        <h2>{{ t('dashboard.recentTitle') }}</h2>
        <p v-if="!recent_approved.length" class="muted">{{ t('dashboard.recentEmpty') }}</p>
        <table v-else class="table">
          <thead>
            <tr>
              <th>{{ t('dashboard.columns.name') }}</th>
              <th>{{ t('dashboard.columns.project') }}</th>
              <th>{{ t('dashboard.columns.target') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="f in recent_approved" :key="'p-'+f.id" class="clickable" @click="openFile(f.id)">
              <td>{{ f.name }}</td>
              <td>{{ f.project_name }}</td>
              <td>{{ f.target_lang }}</td>
            </tr>
          </tbody>
        </table>
      </section>

      <!-- Recent Activity -->
      <section class="panel">
        <h2>{{ t('dashboard.activityTitle') }}</h2>
        <p v-if="!recent_activity.length" class="muted">{{ t('dashboard.activityEmpty') }}</p>
        <ul v-else class="activity-list">
          <li v-for="a in recent_activity" :key="a.id">
            <div class="activity-icon">
              <span v-if="a.action === 'file.approve'" class="badge status-approved">✓</span>
              <span v-else-if="a.action === 'file.reject'" class="badge status-rejected">✕</span>
              <span v-else-if="a.action === 'file.submit'" class="badge">📤</span>
              <span v-else-if="a.action === 'translation.ai'" class="badge status-ai_draft">🤖</span>
            </div>
            <div class="activity-content">
              <p>
                <strong>{{ a.user_name }}</strong>
                <span v-if="a.action === 'file.approve'"> approved </span>
                <span v-else-if="a.action === 'file.reject'"> rejected </span>
                <span v-else-if="a.action === 'file.submit'"> submitted </span>
                <span v-else-if="a.action === 'translation.ai'"> ran AI translation on </span>
                <span>{{ a.project_name }}</span>
                <span v-if="a.file_name"> / {{ a.file_name }}</span>
              </p>
              <small class="muted">{{ formatTime(a.created_at) }}</small>
            </div>
          </li>
        </ul>
      </section>
    </template>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '../stores/auth'
import { useNotificationsStore } from '../stores/notifications'
import { api } from '../api'

const { t } = useI18n()
const auth = useAuthStore()
const router = useRouter()
const notifs = useNotificationsStore()

const assigned = ref([])
const reviewable = ref([])
const recent_approved = ref([])
const recent_activity = ref([])
const loading = ref(true)
const error = ref('')

const isAdmin = computed(() => auth.user?.role === 'admin')

const showGettingStarted = computed(() => {
  if (!isAdmin.value) return false
  return assigned.value.length === 0
      && reviewable.value.length === 0
      && recent_approved.value.length === 0
      && recent_activity.value.length === 0
      && notifs.items.length === 0
})

async function load() {
  loading.value = true
  error.value = ''
  try {
    const data = await api.get('/api/v1/me/dashboard')
    assigned.value = data.assigned || []
    reviewable.value = data.reviewable || []
    recent_approved.value = data.recent_approved || []
    recent_activity.value = data.recent_activity || []
  } catch (e) {
    if (e.status === 401) return router.push('/login')
    error.value = e.message
  } finally { loading.value = false }
}

function openFile(id) { router.push(`/files/${id}`) }

async function openNotif(n) {
  try { await notifs.markRead(n.id) } catch (_) {}
  if (n.entity_type === 'file' && n.entity_id) router.push(`/files/${n.entity_id}`)
}

function formatTime(iso) {
  if (!iso) return ''
  const d = new Date(iso)
  return d.toLocaleDateString() + ' ' + d.toLocaleTimeString([], { hour: '2-digit', minute:'2-digit' })
}

onMounted(load)
</script>
