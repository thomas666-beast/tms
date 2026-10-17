<template>
  <div class="container-wide">
    <div class="row">
      <h1>{{ t('dashboard.title') }}</h1>
    </div>

    <p v-if="loading">{{ t('common.loading') }}</p>
    <p v-else-if="error" class="error">{{ error }}</p>

    <template v-else>
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
    </template>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { api } from '../api'

const { t } = useI18n()
const router = useRouter()

const assigned = ref([])
const reviewable = ref([])
const recent_approved = ref([])
const loading = ref(true)
const error = ref('')

async function load() {
  loading.value = true
  error.value = ''
  try {
    const data = await api.get('/api/v1/me/dashboard')
    assigned.value = data.assigned || []
    reviewable.value = data.reviewable || []
    recent_approved.value = data.recent_approved || []
  } catch (e) {
    if (e.status === 401) return router.push('/login')
    error.value = e.message
  } finally { loading.value = false }
}

function openFile(id) { router.push(`/files/${id}`) }

onMounted(load)
</script>
