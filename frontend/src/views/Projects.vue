<template>
  <div class="container-wide">
    <div class="row">
      <h1>{{ t('projects.title') }}</h1>
      <div class="row-actions">
        <input v-model="search" :placeholder="t('projects.search')" class="search-input" />
        <button v-if="isAdmin" @click="createProject" class="primary">
          {{ t('projects.newProject') }}
        </button>
      </div>
    </div>

    <p v-if="loading">{{ t('common.loading') }}</p>
    <p v-else-if="error" class="error">{{ error }}</p>
    <div v-else-if="filtered.length === 0" class="empty-block">
      <p>{{ t('projects.empty') }}</p>
    </div>

    <div v-else class="card-grid">
      <router-link
        v-for="p in filtered"
        :key="p.id"
        :to="`/projects/${p.id}`"
        class="project-card"
      >
        <div class="project-card-title">
          <span class="project-name">{{ p.name }}</span>
          <span v-if="p.member_role" class="badge">{{ p.member_role }}</span>
        </div>
        <div class="project-card-meta">
          <code>{{ p.slug }}</code>
          <span class="dot">·</span>
          <span>{{ p.default_source_lang }}</span>
        </div>
        <div class="project-card-foot">
          <span>{{ t('projects.columns.members') }}: {{ p.members_count ?? 0 }}</span>
          <span>{{ formatDate(p.created_at) }}</span>
        </div>
      </router-link>
    </div>
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
  } finally { loading.value = false }
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

function formatDate(iso) { return iso ? new Date(iso).toLocaleDateString() : '' }

onMounted(load)
</script>
