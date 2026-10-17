<template>
  <div class="container-wide">
    <div class="row">
      <h1>{{ t('users.title') }}</h1>
      <button @click="startCreate" class="primary">{{ t('users.newUser') }}</button>
    </div>

    <p v-if="loading">{{ t('common.loading') }}</p>
    <p v-else-if="error" class="error">{{ error }}</p>

    <template v-else>
      <div v-if="creating" class="form-box">
        <h3>{{ t('users.create.title') }}</h3>
        <div class="form-grid">
          <label>{{ t('users.create.email') }}<input v-model="newUser.email" type="email" /></label>
          <label>{{ t('users.create.name') }}<input v-model="newUser.name" /></label>
          <label>{{ t('users.create.password') }}<input v-model="newUser.password" type="password" /></label>
          <label>
            {{ t('users.create.role') }}
            <select v-model="newUser.role">
              <option value="translator">{{ t('users.roles.translator') }}</option>
              <option value="lead_translator">{{ t('users.roles.lead_translator') }}</option>
              <option value="admin">{{ t('users.roles.admin') }}</option>
            </select>
          </label>
        </div>
        <div class="row-actions">
          <button @click="createUser" :disabled="busy" class="primary">{{ t('users.create.submit') }}</button>
          <button @click="cancelCreate" class="ghost">{{ t('users.create.cancel') }}</button>
        </div>
      </div>

      <div class="table-card">
        <table class="table">
          <thead>
            <tr>
              <th>{{ t('users.columns.email') }}</th>
              <th>{{ t('users.columns.name') }}</th>
              <th>{{ t('users.columns.role') }}</th>
              <th>{{ t('users.columns.active') }}</th>
              <th>{{ t('users.columns.created') }}</th>
              <th class="actions-col">{{ t('users.columns.actions') }}</th>
            </tr>
          </thead>
          <tbody>
            <template v-for="u in users" :key="u.id">
              <tr :class="{ inactive: !u.is_active }">
                <td>{{ u.email }}</td>
                <td>
                  <span v-if="editingId !== u.id">{{ u.name }}</span>
                  <input v-else v-model="editDraft.name" />
                </td>
                <td>
                  <span v-if="editingId !== u.id" class="badge" :class="'role-' + u.role">{{ u.role }}</span>
                  <select v-else v-model="editDraft.role">
                    <option value="translator">{{ t('users.roles.translator') }}</option>
                    <option value="lead_translator">{{ t('users.roles.lead_translator') }}</option>
                    <option value="admin">{{ t('users.roles.admin') }}</option>
                  </select>
                </td>
                <td>
                  <span v-if="editingId !== u.id" class="status-dot" :class="u.is_active ? 'dot-on' : 'dot-off'">
                    {{ u.is_active ? t('users.yes') : t('users.no') }}
                  </span>
                  <input v-else type="checkbox" v-model="editDraft.is_active" />
                </td>
                <td class="muted">{{ formatDate(u.created_at) }}</td>
                <td class="row-actions-cell">
                  <template v-if="editingId === u.id">
                    <button @click="saveEdit(u)" :disabled="busy" class="small primary">{{ t('users.edit.save') }}</button>
                    <button @click="cancelEdit" class="small ghost">{{ t('users.edit.cancel') }}</button>
                  </template>
                  <template v-else>
                    <button @click="startEdit(u)" class="small">Edit</button>
                    <button @click="startReset(u)" class="small ghost">{{ t('users.resetPassword') }}</button>
                  </template>
                </td>
              </tr>
            </template>
          </tbody>
        </table>
      </div>
    </template>

    <div v-if="resettingId" class="modal-backdrop" @click.self="cancelReset">
      <div class="modal-card">
        <h3>{{ t('users.resetPasswordTitle') }}</h3>
        <p class="muted">{{ resetUserEmail }}</p>
        <label>
          {{ t('users.resetPasswordTitle') }}
          <input v-model="resetPassword" type="password" autofocus />
        </label>
        <div class="row-actions">
          <button @click="submitReset" :disabled="busy || !resetPassword" class="primary">{{ t('users.resetPasswordSubmit') }}</button>
          <button @click="cancelReset" class="ghost">{{ t('common.cancel') }}</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { api } from '../api'

const { t } = useI18n()
const router = useRouter()

const users = ref([])
const loading = ref(true)
const error = ref('')
const busy = ref(false)

const creating = ref(false)
const newUser = reactive({ email: '', name: '', password: '', role: 'translator' })

const editingId = ref(null)
const editDraft = reactive({ name: '', role: 'translator', is_active: true })

const resettingId = ref(null)
const resetUserEmail = ref('')
const resetPassword = ref('')

async function load() {
  loading.value = true
  error.value = ''
  try {
    const data = await api.get('/api/v1/users')
    users.value = data.users || []
  } catch (e) {
    if (e.status === 401) return router.push('/login')
    if (e.status === 403) error.value = t('common.forbidden')
    else error.value = e.message
  } finally { loading.value = false }
}

function startCreate() {
  creating.value = true
  newUser.email = ''; newUser.name = ''; newUser.password = ''; newUser.role = 'translator'
}
function cancelCreate() { creating.value = false }

async function createUser() {
  busy.value = true
  error.value = ''
  try {
    await api.post('/api/v1/users', {
      email: newUser.email,
      name: newUser.name,
      password: newUser.password,
      role: newUser.role,
    })
    creating.value = false
    await load()
  } catch (e) { error.value = e.message }
  finally { busy.value = false }
}

function startEdit(u) {
  editingId.value = u.id
  editDraft.name = u.name
  editDraft.role = u.role
  editDraft.is_active = !!u.is_active
}
function cancelEdit() { editingId.value = null }

async function saveEdit(u) {
  busy.value = true
  error.value = ''
  try {
    await api.patch(`/api/v1/users/${u.id}`, {
      name: editDraft.name,
      role: editDraft.role,
      is_active: editDraft.is_active ? 1 : 0,
    })
    editingId.value = null
    await load()
  } catch (e) { error.value = e.message }
  finally { busy.value = false }
}

function startReset(u) {
  resettingId.value = u.id
  resetUserEmail.value = u.email
  resetPassword.value = ''
}
function cancelReset() {
  resettingId.value = null
  resetUserEmail.value = ''
  resetPassword.value = ''
}

async function submitReset() {
  busy.value = true
  error.value = ''
  try {
    await api.post(`/api/v1/users/${resettingId.value}/password`, { password: resetPassword.value })
    cancelReset()
  } catch (e) { error.value = e.message }
  finally { busy.value = false }
}

function formatDate(iso) { return iso ? new Date(iso).toLocaleDateString() : '' }

onMounted(load)
</script>
