<template>
  <div class="container-wide">
    <div class="crumbs">
      <router-link :to="`/projects/${projectId}`">← Back to project</router-link>
    </div>

    <h1>Activity Log</h1>

    <p v-if="loading">{{ t('common.loading') }}</p>
    <p v-else-if="error" class="error">{{ error }}</p>

    <div v-else class="table-card">
      <table class="table">
        <thead>
          <tr>
            <th style="width: 15%;">When</th>
            <th style="width: 20%;">Who</th>
            <th style="width: 20%;">Action</th>
            <th>Details</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="e in events" :key="e.id">
            <td class="muted small-text">{{ formatDate(e.created_at) }}</td>
            <td>
              <strong>{{ e.user_name }}</strong>
            </td>
            <td>
              <span class="badge">{{ e.action }}</span>
            </td>
            <td class="history-text">
              <router-link v-if="e.entity_type === 'file'" :to="`/files/${e.entity_id}`">
                File #{{ e.entity_id }}
              </router-link>
              <span v-else-if="e.entity_type === 'key'">Key #{{ e.entity_id }}</span>
              <span v-else>Project</span>
            </td>
          </tr>
        </tbody>
      </table>

      <div class="pagination">
        <span class="muted small-text">
          Showing page {{ page }} of {{ totalPages }} ({{ total }} events)
        </span>
        <div class="row-actions">
          <button @click="load(page - 1)" :disabled="page <= 1" class="small ghost">Prev</button>
          <button @click="load(page + 1)" :disabled="page >= totalPages" class="small ghost">Next</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { api } from '../api'

const { t } = useI18n()
const route = useRoute()
const router = useRouter()

const projectId = route.params.id
const events = ref([])
const loading = ref(true)
const error = ref('')
const page = ref(1)
const total = ref(0)
const totalPages = ref(0)

async function load(p = 1) {
  loading.value = true
  error.value = ''
  try {
    const data = await api.get(`/api/v1/projects/${projectId}/audit?page=${p}`)
    events.value = data.events || []
    page.value = data.page
    total.value = data.total
    totalPages.value = data.total_pages
  } catch (e) {
    if (e.status === 401) return router.push('/login')
    if (e.status === 403) error.value = t('common.forbidden')
    else error.value = e.message
  } finally {
    loading.value = false
  }
}

function formatDate(iso) {
  if (!iso) return ''
  const d = new Date(iso)
  return `${d.toLocaleDateString()} ${d.toLocaleTimeString()}`
}

onMounted(() => load(1))
</script>
