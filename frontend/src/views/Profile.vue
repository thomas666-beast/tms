<template>
  <div class="container-wide">
    <h1>{{ t('nav.profile') }}</h1>

    <div class="card-grid" style="margin-bottom: 24px;">
      <div class="panel">
        <h3>Account Info</h3>
        <p><strong>Name:</strong> {{ auth.user?.name }}</p>
        <p><strong>Email:</strong> {{ auth.user?.email }}</p>
        <p><strong>Role:</strong> <span class="badge">{{ auth.user?.role }}</span></p>
      </div>
      
      <div class="panel">
        <h3>Lifetime Stats</h3>
        <div class="stat-row">
          <span class="stat-label">{{ t('files.detail.statsTranslated') }}</span>
          <span class="stat-value">{{ formatNum(stats.words_translated) }}</span>
        </div>
        <div class="stat-row">
          <span class="stat-label">{{ t('files.detail.statsCorrected') }}</span>
          <span class="stat-value">{{ formatNum(stats.words_corrected) }}</span>
        </div>
      </div>
    </div>

    <div class="panel">
      <h3>Change Password</h3>
      <form @submit.prevent="changePassword" style="max-width: 400px;">
        <label>
          Current Password
          <input v-model="oldPassword" type="password" required />
        </label>
        <label>
          New Password
          <input v-model="newPassword" type="password" required />
        </label>
        <button type="submit" :disabled="busy" class="primary">Update Password</button>
        <p v-if="error" class="error">{{ error }}</p>
        <p v-if="success" class="success-text">Password updated successfully.</p>
      </form>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '../stores/auth'
import { api } from '../api'

const { t } = useI18n()
const auth = useAuthStore()

const stats = ref({ words_translated: 0, words_corrected: 0 })
const oldPassword = ref('')
const newPassword = ref('')
const busy = ref(false)
const error = ref('')
const success = ref(false)

async function load() {
  try {
    const data = await api.get('/api/v1/me/dashboard')
    if (data.stats) {
      stats.value = data.stats
    }
  } catch (e) {
    console.error(e)
  }
}

async function changePassword() {
  busy.value = true
  error.value = ''
  success.value = false
  try {
    await api.post('/api/v1/me/password', {
      old_password: oldPassword.value,
      new_password: newPassword.value
    })
    success.value = true
    oldPassword.value = ''
    newPassword.value = ''
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}

function formatNum(n) { return (n ?? 0).toLocaleString() }

onMounted(load)
</script>
