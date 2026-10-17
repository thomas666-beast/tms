<template>
  <div class="container">
    <header>
      <span>{{ auth.user?.name }}</span>
      <button @click="onLogout">{{ t('nav.signOut') }}</button>
    </header>
    <p><router-link to="/projects">{{ t('projects.back') }}</router-link></p>

    <p v-if="loading">{{ t('common.loading') }}</p>
    <p v-else-if="error" class="error">{{ error }}</p>

    <template v-else-if="project">
      <h1>{{ project.name }} <small>({{ project.default_source_lang }})</small></h1>

      <h2>{{ t('projects.members') }}</h2>
      <ul class="list">
        <li v-for="m in members" :key="m.user_id">
          {{ m.name }} <small>&lt;{{ m.email }}&gt;</small>
          — <span class="badge">{{ m.role }}</span>
        </li>
      </ul>

      <div class="row">
        <h2>{{ t('projects.files') }}</h2>
        <button v-if="canManageFiles" @click="upload" :disabled="uploading">
          {{ uploading ? t('files.uploading') : t('files.upload') }}
        </button>
      </div>

      <p v-if="files.length === 0">{{ t('files.empty') }}</p>
      <table v-else class="table">
        <thead>
          <tr>
            <th>{{ t('files.columns.name') }}</th>
            <th>{{ t('files.columns.format') }}</th>
            <th>{{ t('files.columns.target') }}</th>
            <th>{{ t('files.columns.status') }}</th>
            <th>{{ t('files.columns.assignedTo') }}</th>
            <th>{{ t('files.columns.keys') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="f in files" :key="f.id" class="clickable">
            <td>{{ f.name }}</td>
            <td><code>{{ f.format }}</code></td>
            <td>{{ f.target_lang }}</td>
            <td>{{ f.status }}</td>
            <td>{{ f.assigned_to_name || t('files.unassigned') }}</td>
            <td>{{ f.keys_count }}</td>
          </tr>
        </tbody>
      </table>
    </template>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '../stores/auth'
import { api } from '../api'

const { t } = useI18n()
const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

const project = ref(null)
const members = ref([])
const files   = ref([])
const loading = ref(true)
const error   = ref('')
const uploading = ref(false)

const canManageFiles = computed(() => {
  if (auth.user?.role === 'admin') return true
  const me = members.value.find(m => m.user_id === auth.user?.id)
  return me?.role === 'admin'
})

async function load() {
  loading.value = true
  error.value = ''
  try {
    const id = route.params.id
    const data = await api.get(`/api/v1/projects/${id}`)
    project.value = data.project
    members.value = data.members || []
    const fl = await api.get(`/api/v1/projects/${id}/files`)
    files.value = fl.files || []
  } catch (e) {
    if (e.status === 401) return router.push('/login')
    if (e.status === 403) error.value = t('common.forbidden')
    else if (e.status === 404) error.value = t('projects.notFound')
    else error.value = e.message
  } finally {
    loading.value = false
  }
}

async function upload() {
  const input = document.createElement('input')
  input.type = 'file'
  input.onchange = async () => {
    const file = input.files?.[0]
    if (!file) return
    const format = window.prompt(t('files.promptFormat'), 'laravel')
    if (!format) return
    const target = window.prompt(t('files.promptTarget'), 'fr')
    if (!target) return

    const fd = new FormData()
    fd.append('file', file)
    fd.append('format', format)
    fd.append('source_lang', project.value.default_source_lang)
    fd.append('target_lang', target)
    fd.append('name', file.name)

    uploading.value = true
    error.value = ''
    try {
      await fetch(`/api/v1/projects/${route.params.id}/files`, {
        method: 'POST',
        credentials: 'include',
        headers: { 'X-CSRF-Token': auth.csrf_token },
        body: fd,
      }).then(async r => {
        if (!r.ok) {
          const j = await r.json().catch(() => ({}))
          throw new Error(j.error || `HTTP ${r.status}`)
        }
      })
      await load()
    } catch (e) {
      error.value = e.message
    } finally {
      uploading.value = false
    }
  }
  input.click()
}

async function onLogout() {
  await auth.logout()
  router.push('/login')
}

onMounted(load)
</script>
