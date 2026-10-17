<template>
  <div class="container-wide">
    <div class="crumbs">
      <router-link :to="projectLink">{{ t('files.detail.backToProject') }}</router-link>
    </div>

    <p v-if="loading">{{ t('common.loading') }}</p>
    <p v-else-if="error" class="error">{{ error }}</p>

    <template v-else-if="file">
      <div class="file-header">
        <div>
          <h1 class="file-title">{{ file.name }}</h1>
          <div class="file-meta">
            <code>{{ file.format }}</code>
            <span class="dot">·</span>
            <span>{{ t('files.detail.sourceToTarget', { source: file.source_lang, target: file.target_lang }) }}</span>
            <span class="dot">·</span>
            <span class="badge">{{ file.status }}</span>
            <span v-if="revision" class="dot">·</span>
            <span v-if="revision" class="muted small-text">
              rev #{{ revision.revision_number }} · {{ revision.status }}
            </span>
          </div>
        </div>
        <div class="row-actions">
          <a :href="`/api/v1/files/${file.id}/export`" class="btn-link" target="_blank">
            {{ t('files.detail.exportCurrent') }}
          </a>
          <button @click="openFile('export-approved')" class="btn-link">
            {{ t('files.detail.exportApproved') }}
          </button>
        </div>
      </div>

      <div class="assign-bar">
        <span class="assign-label">{{ t('files.columns.assignedTo') }}:</span>
        <span v-if="file.assigned_to_name" class="assign-name">{{ file.assigned_to_name }}</span>
        <span v-else class="muted">{{ t('files.detail.unassigned') }}</span>

        <template v-if="canManageAssignment && !isInReview">
          <template v-if="assignableMembers.length">
            <select v-model="assignChoice" class="assign-select">
              <option value="">{{ t('files.detail.assignTo') }}…</option>
              <option v-for="m in assignableMembers" :key="m.user_id" :value="m.user_id">
                {{ m.name }} ({{ m.role }})
              </option>
            </select>
            <button @click="assign" :disabled="!assignChoice || busy" class="small">→</button>
          </template>
          <template v-else>
            <span class="muted">{{ t('files.detail.needMember') }}</span>
            <router-link :to="projectLink + '#members'">{{ t('files.detail.goToMembers') }}</router-link>
          </template>
          <button v-if="file.assigned_to_user_id" @click="unassign" :disabled="busy" class="small ghost">
            {{ t('files.detail.clearAssign') }}
          </button>
        </template>
      </div>

      <div class="workflow-bar">
        <button v-if="canSubmit" @click="submit" :disabled="busy" class="primary">
          {{ t('workflow.submit') }}
        </button>
        <label v-if="hasPrevious" class="compare-toggle">
          <input type="checkbox" v-model="compare" @change="reload" />
          {{ t('workflow.compareMode') }}
        </label>
      </div>

      <div v-if="isInReview" class="review-layout">
        <div class="review-main">
          <div class="review-card">
            <h2>{{ t('workflow.reviewPanel') }}</h2>
            <div v-for="k in keys" :key="'rv-'+k.id" class="review-key">
              <code class="review-key-path">{{ k.key_path }}</code>
              <div class="review-key-body">
                <div class="review-cell">
                  <div class="review-cell-label">{{ t('files.detail.colSource') }}</div>
                  <div class="review-text">{{ k.source_text }}</div>
                </div>
                <div class="review-cell">
                  <div class="review-cell-label">{{ t('files.detail.colTranslation') }}</div>
                  <div :class="'review-text status-' + (k.translation?.status || 'empty')">
                    {{ k.translation?.text || '—' }}
                  </div>
                  <small v-if="k.translation?.note" class="muted">{{ k.translation.note }}</small>
                  <div v-if="compare && k.previous_translation" class="review-previous">
                    <span class="muted small-text">{{ t('files.detail.previous') }}:</span>
                    <span>{{ k.previous_translation.text }}</span>
                  </div>
                </div>
                <div class="review-cell review-cell-status">
                  <span class="badge" :class="'status-' + (k.translation?.status || 'empty')">
                    {{ statusLabel(k.translation?.status) }}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <aside class="review-side">
          <div class="review-card">
            <h3>{{ t('workflow.approvals') }} ({{ approvalStats.approve_count }})</h3>
            <ul v-if="approvals.length" class="approvals-list">
              <li v-for="a in approvals" :key="a.id">
                <strong>{{ a.user_name }}</strong>
                <span class="badge" :class="a.decision === 'approve' ? 'status-approved' : 'status-rejected'">
                  {{ a.decision }}
                </span>
                <em v-if="a.comment" class="muted">— {{ a.comment }}</em>
              </li>
            </ul>
            <p :class="approvalStats.quorum_met ? 'ok' : 'pending'">
              {{ approvalStats.quorum_met ? t('workflow.quorumMet') : t('workflow.quorumPending') }}
            </p>

            <template v-if="canApprove">
              <div class="review-form">
                <label>
                  {{ t('workflow.approveComment') }}
                  <textarea v-model="approveComment" rows="2"></textarea>
                </label>
                <button @click="approve" :disabled="busy" class="primary">{{ t('workflow.approve') }}</button>
              </div>
              <div class="review-form">
                <label>
                  {{ t('workflow.rejectComment') }}
                  <textarea v-model="rejectComment" rows="2"></textarea>
                </label>
                <button @click="reject" :disabled="busy || !rejectComment.trim()" class="danger">{{ t('workflow.reject') }}</button>
              </div>
            </template>
          </div>
        </aside>
      </div>

      <div class="editor-toolbar">
        <label>
          {{ t('files.detail.filter') }}
          <select v-model="filter" @change="reload">
            <option value="all">{{ t('files.detail.filterAll') }}</option>
            <option value="empty">{{ t('files.detail.filterEmpty') }}</option>
            <option value="needs_review">{{ t('files.detail.filterNeeds') }}</option>
            <option value="translated">{{ t('files.detail.filterTrans') }}</option>
            <option value="approved">{{ t('files.detail.filterApproved') }}</option>
          </select>
        </label>
        <label>
          {{ t('files.detail.search') }}
          <input v-model="search" placeholder="key or source" />
        </label>
        <label v-if="aiEnabled">
          {{ t('files.detail.aiEngine') }}
          <select v-model="selectedEngine">
            <option v-for="e in enabledEngines" :key="e.name" :value="e.name">{{ e.label }}</option>
          </select>
        </label>
        <button v-if="canAiBulk && aiEnabled" @click="aiBulk" :disabled="busy || bulkRunning">
          {{ bulkRunning ? t('files.detail.aiRunning') : t('files.detail.aiTranslateAll') }}
        </button>
      </div>

      <div v-if="keys.length === 0" class="empty-block">
        <p>{{ t('files.detail.noKeys') }}</p>
      </div>

      <div v-else class="editor-table-wrap">
        <table class="table-keys">
          <thead>
            <tr>
              <th style="width: 18%;">{{ t('files.detail.colKey') }}</th>
              <th style="width: 27%;">{{ t('files.detail.colSource') }}</th>
              <th style="width: 38%;">{{ t('files.detail.colTranslation') }}</th>
              <th style="width: 9%;">{{ t('files.detail.colStatus') }}</th>
              <th style="width: 8%;">{{ t('files.detail.colActions') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="k in visibleKeys" :key="k.id" :class="rowClass(k)">
              <td><code>{{ k.key_path }}</code></td>
              <td class="source">{{ k.source_text || t('files.detail.emptyCell') }}</td>
              <td>
                <textarea v-model="draft[k.id].text" :disabled="!canEdit(k)" rows="2" class="translation-input"></textarea>
                <input v-if="draft[k.id].status === 'needs_review'" v-model="draft[k.id].note"
                  class="note-input" :placeholder="t('files.detail.note')" :disabled="!canEdit(k)" />
              </td>
              <td>
                <span class="badge" :class="'status-' + (k.translation?.status || 'empty')">
                  {{ statusLabel(k.translation?.status) }}
                </span>
              </td>
              <td class="row-actions-cell">
                <button v-if="canEdit(k)" @click="save(k)" :disabled="busy" class="small">
                  {{ t('files.detail.save') }}
                </button>
                <button v-if="canEdit(k) && aiEnabled" @click="aiOne(k)" :disabled="busy || bulkRunning" class="small ghost">
                  {{ t('files.detail.ai') }}
                </button>
                <span v-if="draft[k.id].savedAt" class="saved">✓</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <p v-if="!aiEnabled" class="muted small-text">
        {{ t('files.detail.aiDisabled') }}
      </p>
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

const file = ref(null)
const revision = ref(null)
const keys = ref([])
const approvals = ref([])
const approvalStats = ref({ approve_count: 0, quorum_met: 0, has_admin: 0 })
const members = ref([])
const project = ref(null)
const previousRevisionId = ref(null)

const engines = ref([])
const selectedEngine = ref(localStorage.getItem('tms.aiEngine') || 'libretranslate')
const bulkRunning = ref(false)
const bulkProgress = ref({ done: 0, total: 0 })

const loading = ref(true)
const busy = ref(false)
const error = ref('')

const filter = ref('all')
const search = ref('')
const compare = ref(false)
const draft = reactive({})
const assignChoice = ref('')
const approveComment = ref('')
const rejectComment = ref('')

const myProjectRole = computed(() => {
  const me = members.value.find(m => m.user_id === auth.user?.id)
  return me?.role || null
})
const isGlobalAdmin = computed(() => auth.user?.role === 'admin')
const isProjectAdmin = computed(() => isGlobalAdmin.value || myProjectRole.value === 'admin')
const isProjectLead = computed(() => isProjectAdmin.value || myProjectRole.value === 'lead')
const isAssigned = computed(() => file.value?.assigned_to_user_id === auth.user?.id)
const isInReview = computed(() => revision.value?.status === 'in_review')
const revisionOpen = computed(() => revision.value?.status === 'open')

const canManageAssignment = computed(() => isProjectAdmin.value)
const assignableMembers = computed(() =>
  members.value.filter(m => m.role === 'translator' || m.role === 'lead'))

const enabledEngines = computed(() => engines.value.filter(e => e.enabled))
const aiEnabled = computed(() => enabledEngines.value.length > 0)

function canEdit(k) {
  if (!revisionOpen.value) return false
  return isProjectLead.value || isAssigned.value
}
const canSubmit = computed(() => revisionOpen.value && isProjectLead.value && file.value?.status !== 'in_review')
const canApprove = computed(() => isInReview.value && (isProjectLead.value || isGlobalAdmin.value))
const canAiBulk = computed(() => revisionOpen.value && isProjectLead.value)

const hasPrevious = computed(() => previousRevisionId.value != null)
const projectLink = computed(() => project.value ? `/projects/${project.value.id}` : '/projects')
const visibleKeys = computed(() => {
  const q = search.value.trim().toLowerCase()
  if (!q) return keys.value
  return keys.value.filter(k =>
    k.key_path.toLowerCase().includes(q) ||
    (k.source_text || '').toLowerCase().includes(q))
})
function rowClass(k) { return `row-${k.translation?.status || 'empty'}` }
function statusLabel(s) { return t(`files.status.${s || 'empty'}`) }

function errMsg(e) {
  const code = e?.data?.error
  if (code && t(`workflow.errors.${code}`) !== `workflow.errors.${code}`) {
    return t(`workflow.errors.${code}`)
  }
  return e.message
}

async function loadEngines() {
  try {
    const data = await api.get('/api/v1/ai/engines')
    engines.value = data.engines || []
    if (aiEnabled.value && !enabledEngines.value.find(e => e.name === selectedEngine.value)) {
      selectedEngine.value = enabledEngines.value[0].name
    }
  } catch (_) { /* ignore */ }
}

async function load() {
  loading.value = true
  error.value = ''
  try {
    const id = route.params.id
    const data = await api.get(`/api/v1/files/${id}`)
    file.value = data.file
    revision.value = data.revision

    const proj = await api.get(`/api/v1/projects/${data.file.project_id}`)
    project.value = proj.project
    members.value = proj.members || []

    await loadEngines()
    await reload()

    if (revision.value?.status === 'in_review') {
      await loadApprovals(id)
    } else {
      approvals.value = []
      approvalStats.value = { approve_count: 0, quorum_met: 0, has_admin: 0 }
    }
  } catch (e) {
    if (e.status === 401) return router.push('/login')
    if (e.status === 403) error.value = t('common.forbidden')
    else error.value = e.message
  } finally { loading.value = false }
}

async function loadApprovals(id) {
  const appr = await api.get(`/api/v1/files/${id}/approvals`)
  approvals.value = appr.approvals || []
  approvalStats.value = {
    approve_count: appr.approve_count,
    quorum_met: appr.quorum_met,
    has_admin: appr.has_admin,
  }
}

async function reload() {
  const id = route.params.id
  const params = []
  if (filter.value !== 'all') params.push(`status=${filter.value}`)
  if (compare.value)         params.push('with_previous=1')
  const q = params.length ? '?' + params.join('&') : ''
  const data = await api.get(`/api/v1/files/${id}/keys${q}`)
  keys.value = data.keys || []
  previousRevisionId.value = data.previous_revision_id ?? null
  for (const k of keys.value) {
    if (!draft[k.id]) {
      draft[k.id] = {
        text: k.translation?.text || '',
        status: k.translation?.status || 'empty',
        note: k.translation?.note || '',
        savedAt: null,
      }
    } else {
      draft[k.id].status = k.translation?.status || 'empty'
    }
  }
}

function rememberEngine() {
  if (selectedEngine.value) localStorage.setItem('tms.aiEngine', selectedEngine.value)
}

async function assign() {
  if (!assignChoice.value) return
  busy.value = true
  error.value = ''
  try {
    await api.post(`/api/v1/files/${file.value.id}/assign`, { user_id: Number(assignChoice.value) })
    assignChoice.value = ''
    await load()
  } catch (e) { error.value = errMsg(e) }
  finally { busy.value = false }
}

async function unassign() {
  busy.value = true
  error.value = ''
  try {
    await api.post(`/api/v1/files/${file.value.id}/unassign`)
    await load()
  } catch (e) { error.value = errMsg(e) }
  finally { busy.value = false }
}

async function save(k) {
  busy.value = true
  error.value = ''
  try {
    const body = { text: draft[k.id].text }
    if (draft[k.id].status === 'needs_review') {
      body.status = 'needs_review'
      body.note = draft[k.id].note
    }
    const data = await api.patch(`/api/v1/keys/${k.id}/translation`, body)
    k.translation = data.translation
    draft[k.id].status = data.translation.status
    draft[k.id].note = data.translation.note || ''
    draft[k.id].savedAt = Date.now()
  } catch (e) { error.value = errMsg(e) }
  finally { busy.value = false }
}

async function aiOne(k) {
  rememberEngine()
  busy.value = true
  error.value = ''
  try {
    const data = await api.post(`/api/v1/keys/${k.id}/ai_translate`, { engine: selectedEngine.value })
    k.translation = data.translation
    draft[k.id].text = data.translation.text || ''
    draft[k.id].status = data.translation.status
    draft[k.id].note = data.translation.note || ''
  } catch (e) { error.value = errMsg(e) }
  finally { busy.value = false }
}

async function aiBulk() {
  rememberEngine()
  bulkRunning.value = true
  bulkProgress.value = { done: 0, total: 0 }
  error.value = ''
  try {
    const data = await api.post(`/api/v1/files/${file.value.id}/ai_translate`, { engine: selectedEngine.value })
    bulkProgress.value = {
      done: (data.translated || 0) + (data.needs_review || 0) + (data.errors || 0),
      total: data.total || 0,
    }
    await reload()
  } catch (e) { error.value = errMsg(e) }
  finally { bulkRunning.value = false }
}

async function submit() {
  if (!window.confirm(t('workflow.confirmSubmit'))) return
  busy.value = true
  try {
    await api.post(`/api/v1/files/${file.value.id}/submit`)
    await load()
  } catch (e) { error.value = errMsg(e) }
  finally { busy.value = false }
}

async function approve() {
  busy.value = true
  try {
    await api.post(`/api/v1/files/${file.value.id}/approve`, { comment: approveComment.value || undefined })
    approveComment.value = ''
    await load()
  } catch (e) { error.value = errMsg(e) }
  finally { busy.value = false }
}

async function reject() {
  if (!rejectComment.value.trim()) return
  busy.value = true
  try {
    await api.post(`/api/v1/files/${file.value.id}/reject`, { comment: rejectComment.value })
    rejectComment.value = ''
    await load()
  } catch (e) { error.value = errMsg(e) }
  finally { busy.value = false }
}

function openFile(kind) {
  if (kind === 'export-approved') {
    window.open(`/api/v1/files/${file.value.id}/export?revision=latest_approved`, '_blank')
  }
}

onMounted(load)
</script>
