<template>
  <div class="container-wider">
    <header>
      <span>{{ auth.user?.name }}</span>
      <button @click="onLogout">{{ t('nav.signOut') }}</button>
    </header>
    <div class="row">
      <h1>{{ t('projects.title') }}</h1>
      <button v-if="isAdmin" @click="createProject" class="primary">
        {{ t('projects.newProject') }}
      </button>
    </div>

    <div class="toolbar">
      <input v-model="search" :placeholder="t('projects.search')" />
    </div>

    <p v-if="loading">{{ t('common.loading') }}</p>
    <p v-else-if="error" class="error">{{ error }}</p>
    <p v-else-if="filtered.length === 0">{{ t('projects.empty') }}</p>

    <table v-else class="table">
      <thead>
        <tr>
          <th>{{ t('projects.columns.name') }}</th>
          <th>{{ t('projects.columns.slug') }}</th>
          <th>{{ t('projects.columns.sourceLang') }}</th>
          <th>{{ t('projects.columns.members') }}</th>
          <th>{{ t('projects.columns.created') }}</th>
          <th>{{ t('projects.columns.role') }}</th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="p in filtered"
          :key="p.id"
          @click="openProject(p.id)"
          class="clickable"
        >
          <td>{{ p.name }}</td>
          <td><code>{{ p.slug }}</code></td>
          <td>{{ p.default_source_lang }}</td>
          <td>{{ p.members_count ?? '—' }}</td>
          <td>{{ formatDate(p.created_at) }}</td>
          <td>{{ p.member_role || '—' }}</td>
        </tr>
      </tbody>
    </table>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '../stores/auth'
import { api } from '../api'

const { t } = useI18n()
const auth = useAuthStore()
const router = useRouter()

const projects = ref([])
const loading = ref(true)
const error = ref('')
const search = ref('')

const isAdmin = computed(() => auth.user?.role === 'admin')

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase()
  if (!q) return projects.value
  return projects.value.filter(p =>
    p.name.toLowerCase().includes(q) ||
    p.slug.toLowerCase().includes(q))
})

async function load() {
  loading.value = true
  error.value = ''
  try {
    const data = await api.get('/api/v1/projects')
    projects.value = data.projects || []
  } catch (e) {
    if (e.status === 401) return router.push('/login')
    error.value = e.message
  } finally {
    loading.value = false
  }
}

async function createProject() {
  const name = window.prompt(t('projects.promptName'))
  if (!name) return
  const lang = window.prompt(t('projects.promptLang'), 'en')
  if (!lang) return
  try {
    await api.post('/api/v1/projects', { name, default_source_lang: lang })
    await load()
  } catch (e) { error.value = e.message }
}

function openProject(id) { router.push(`/projects/${id}`) }
function formatDate(iso) { return iso ? new Date(iso).toLocaleDateString() : '' }

async function onLogout() {
  await auth.logout()
  router.push('/login')
}

onMounted(load)
</script>
