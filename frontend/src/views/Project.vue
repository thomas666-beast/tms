<template>
  <div class="container-wide">
    <div class="crumbs">
      <router-link to="/projects">{{ t('projects.back') }}</router-link>
    </div>

    <p v-if="loading">{{ t('common.loading') }}</p>
    <p v-else-if="error" class="error">{{ error }}</p>

    <template v-else-if="project">
      <div v-if="!editing" class="file-header">
        <div>
          <h1 class="file-title">
            {{ project.name }}
            <span v-if="project.approved" class="badge status-approved">{{ t('projects.approved') }}</span>
            <span v-else-if="project.files_total > 0" class="badge">{{ t('projects.inProgress') }}</span>
          </h1>
          <div class="file-meta">
            <code>{{ project.slug }}</code>
            <span class="dot">·</span>
            <span>{{ t('projects.columns.sourceLang') }}: {{ project.default_source_lang }}</span>
            <span class="dot">·</span>
            <span>{{ project.files_total }} {{ t('projects.filesLabel') }}</span>
            <span class="dot">·</span>
            <span class="stat-approved">{{ project.files_approved }} {{ t('projects.approvedLabel') }}</span>
            <span class="dot">·</span>
            <span class="stat-open">{{ project.files_not_approved }} {{ t('projects.openLabel') }}</span>
            <span class="dot">·</span>
            <span>{{ formatNum(project.words_total) }} {{ t('projects.wordsLabel') }}</span>
          </div>
        </div>
        <div v-if="canManageMembers" class="row-actions">
          <button @click="startEdit" class="btn-link">{{ t('projects.edit') }}</button>
        </div>
      </div>

      <div v-else class="form-box">
        <h3>{{ t('projects.editTitle') }}</h3>
        <div class="form-grid">
          <label>{{ t('projects.editName') }}<input v-model="editDraft.name" /></label>
          <label>{{ t('projects.editLang') }}<input v-model="editDraft.default_source_lang" /></label>
        </div>
        <div class="row-actions">
          <button @click="saveEdit" :disabled="busy" class="primary">{{ t('projects.editSave') }}</button>
          <button @click="cancelEdit" class="ghost">{{ t('projects.editCancel') }}</button>
        </div>
      </div>

      <div class="row">
        <h2>{{ t('projects.members') }}</h2>
        <button v-if="canManageMembers" @click="startAddMember" class="primary">
          {{ t('projects.addMember') }}
        </button>
      </div>

      <div v-if="addingMember" class="form-box">
        <h3>{{ t('projects.addMemberTitle') }}</h3>
        <div class="form-grid">
          <label>
            {{ t('projects.memberUser') }}
            <select v-model="newMember.user_id">
              <option value="">—</option>
              <option v-for="u in candidates" :key="u.id" :value="u.id">
                {{ u.name }} ({{ u.email }})
              </option>
            </select>
          </label>
          <label>
            {{ t('projects.memberRole') }}
            <select v-model="newMember.role">
              <option value="translator">{{ t('members.role.translator') }}</option>
              <option value="lead">{{ t('members.role.lead') }}</option>
              <option value="admin">{{ t('members.role.admin') }}</option>
            </select>
          </label>
        </div>
        <div class="row-actions">
          <button @click="addMember" :disabled="!newMember.user_id || busy" class="primary">
            {{ t('projects.addMemberSubmit') }}
          </button>
          <button @click="cancelAddMember" class="ghost">{{ t('common.cancel') }}</button>
        </div>
      </div>

      <div v-if="members.length === 0" class="empty-block">
        <p>{{ t('projects.empty') }}</p>
      </div>
      <div v-else class="table-card">
        <table class="table">
          <thead>
            <tr>
              <th>{{ t('projects.memberUser') }}</th>
              <th>{{ t('users.columns.email') }}</th>
              <th>{{ t('projects.memberRole') }}</th>
              <th class="num">{{ t('projects.wordsTranslated') }}</th>
              <th class="actions-col"></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="m in members" :key="m.user_id">
              <td>{{ m.name }}</td>
              <td class="muted">{{ m.email }}</td>
              <td><span class="badge" :class="'role-' + m.role">{{ m.role }}</span></td>
              <td class="num">{{ formatNum(m.words_translated) }}</td>
              <td class="row-actions-cell">
                <button
                  v-if="canManageMembers && m.user_id !== auth.user?.id"
                  @click="removeMember(m.user_id)"
                  class="small ghost"
                >{{ t('projects.removeMember') }}</button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="row" style="margin-top: 32px;">
        <h2>{{ t('projects.files') }}</h2>
        <button v-if="canManageFiles && !uploadingFile" @click="startUpload" class="primary">
          {{ t('files.upload') }}
        </button>
      </div>

      <div v-if="uploadingFile" class="form-box">
        <h3>{{ t('files.uploadTitle') }}</h3>
        <div class="form-grid">
          <label>
            {{ t('files.uploadFormat') }}
            <select v-model="uploadDraft.format">
              <option v-if="!formats.length" value="">—</option>
              <option v-for="f in formats" :key="f.code" :value="f.code">
                {{ f.label }} (.{{ f.file_ext }})
              </option>
            </select>
          </label>
          <label>
            {{ t('files.uploadTarget') }}
            <input v-model="uploadDraft.target" list="target-langs" placeholder="fr" />
            <datalist id="target-langs">
              <option value="fr" /><option value="de" />
              <option value="es" /><option value="it" />
              <option value="pt" /><option value="ar" />
              <option value="ru" /><option value="zh" />
              <option value="ja" /><option value="ko" />
            </datalist>
          </label>
          <label>
            {{ t('files.uploadName') }}
            <input v-model="uploadDraft.name" placeholder="auth.php" />
          </label>
          <label>
            File
            <input ref="fileInput" type="file" />
          </label>
        </div>
        <div class="row-actions">
          <button
            @click="submitUpload"
            :disabled="!uploadDraft.format || !uploadDraft.target || !fileInput?.files?.length || uploading"
            class="primary"
          >{{ uploading ? t('files.uploading') : t('files.uploadSubmit') }}</button>
          <button @click="cancelUpload" class="ghost">{{ t('files.uploadCancel') }}</button>
        </div>
      </div>

      <div v-if="files.length === 0" class="empty-block">
        <p>{{ t('files.empty') }}</p>
      </div>
      <div v-else class="table-card">
        <table class="table">
          <thead>
            <tr>
              <th>{{ t('files.columns.name') }}</th>
              <th>{{ t('files.columns.format') }}</th>
              <th>{{ t('files.columns.target') }}</th>
              <th>{{ t('files.columns.status') }}</th>
              <th>{{ t('files.columns.assignedTo') }}</th>
              <th class="num">{{ t('files.columns.keys') }}</th>
              <th class="num">{{ t('files.columns.words') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="f in files" :key="f.id" class="clickable" @click="openFile(f.id)">
              <td>{{ f.name }}</td>
              <td><code>{{ f.format }}</code></td>
              <td>{{ f.target_lang }}</td>
              <td><span class="badge" :class="'status-' + f.status">{{ f.status }}</span></td>
              <td>{{ f.assigned_to_name || t('files.unassigned') }}</td>
              <td class="num">{{ f.keys_count }}</td>
              <td class="num">{{ formatNum(f.words_total) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted } from 'vue'
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
const files = ref([])
const candidates = ref([])
const formats = ref([])
const loading = ref(true)
const error = ref('')
const uploading = ref(false)
const busy = ref(false)

const editing = ref(false)
const editDraft = reactive({ name: '', default_source_lang: '' })

const addingMember = ref(false)
const newMember = reactive({ user_id: '', role: 'translator' })

const uploadingFile = ref(false)
const fileInput = ref(null)
const uploadDraft = reactive({ format: '', target: '', name: '' })

const isGlobalAdmin = computed(() => auth.user?.role === 'admin')
const myProjectRole = computed(() => {
  const me = members.value.find(m => m.user_id === auth.user?.id)
  return me?.role || null
})
const canManageMembers = computed(() =>
  isGlobalAdmin.value || myProjectRole.value === 'admin')
const canManageFiles = computed(() =>
  isGlobalAdmin.value || myProjectRole.value === 'admin')

async function loadFormats() {
  if (formats.value.length) return
  try {
    const data = await api.get('/api/v1/formats')
    formats.value = data.formats || []
    if (formats.value.length) uploadDraft.format = formats.value[0].code
  } catch (_) {}
}

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
    await loadFormats()
  } catch (e) {
    if (e.status === 401) return router.push('/login')
    if (e.status === 403) error.value = t('common.forbidden')
    else if (e.status === 404) error.value = t('projects.notFound')
    else error.value = e.message
  } finally { loading.value = false }
}

function startEdit() {
  editing.value = true
  editDraft.name = project.value.name
  editDraft.default_source_lang = project.value.default_source_lang
}
function cancelEdit() { editing.value = false }

async function saveEdit() {
  busy.value = true
  error.value = ''
  try {
    await api.patch(`/api/v1/projects/${route.params.id}`, {
      name: editDraft.name,
      default_source_lang: editDraft.default_source_lang,
    })
    editing.value = false
    await load()
  } catch (e) { error.value = e.message }
  finally { busy.value = false }
}

async function startAddMember() {
  try {
    const data = await api.get(`/api/v1/projects/${route.params.id}/candidates`)
    candidates.value = data.candidates || []
  } catch (e) { error.value = e.message; return }
  addingMember.value = true
  newMember.user_id = ''
  newMember.role = 'translator'
}
function cancelAddMember() { addingMember.value = false }

async function addMember() {
  busy.value = true
  error.value = ''
  try {
    await api.post(`/api/v1/projects/${route.params.id}/members`, {
      user_id: Number(newMember.user_id),
      role: newMember.role,
    })
    addingMember.value = false
    await load()
  } catch (e) { error.value = e.message }
  finally { busy.value = false }
}

async function removeMember(userId) {
  if (!window.confirm(t('projects.confirmRemoveMember'))) return
  busy.value = true
  error.value = ''
  try {
    await api.del(`/api/v1/projects/${route.params.id}/members/${userId}`)
    await load()
  } catch (e) { error.value = e.message }
  finally { busy.value = false }
}

function openFile(id) { router.push(`/files/${id}`) }

async function startUpload() {
  await loadFormats()
  uploadingFile.value = true
  uploadDraft.target = uploadDraft.target || ''
  uploadDraft.name = ''
}

function cancelUpload() {
  uploadingFile.value = false
  uploadDraft.name = ''
  if (fileInput.value) fileInput.value.value = ''
}

async function submitUpload() {
  const file = fileInput.value?.files?.[0]
  if (!file) return
  uploading.value = true
  error.value = ''
  try {
    const fd = new FormData()
    fd.append('file', file)
    fd.append('format', uploadDraft.format)
    fd.append('source_lang', project.value.default_source_lang)
    fd.append('target_lang', uploadDraft.target)
    fd.append('name', uploadDraft.name || file.name)

    const res = await fetch(`/api/v1/projects/${route.params.id}/files`, {
      method: 'POST',
      credentials: 'include',
      headers: { 'X-CSRF-Token': auth.csrf_token },
      body: fd,
    })
    if (!res.ok) {
      const j = await res.json().catch(() => ({}))
      throw new Error(j.error || `HTTP ${res.status}`)
    }
    cancelUpload()
    await load()
  } catch (e) { error.value = e.message }
  finally { uploading.value = false }
}

function formatNum(n) { return (n ?? 0).toLocaleString() }

onMounted(load)
</script>
