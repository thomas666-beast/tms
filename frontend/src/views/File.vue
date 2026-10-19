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
          <div class="file-stats">
            <span><strong>{{ formatNum(file.words_total) }}</strong> {{ t('files.detail.statWords') }}</span>
            <span class="stat-approved"><strong>{{ formatNum(file.words_approved || 0) }}</strong> {{ t('files.detail.statApproved') }}</span>
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

        <button
          v-if="revisionOpen && canEditSomething"
          @click="translateFile"
          :disabled="busy || bulkRunning || !aiEnabled"
          class="primary translate-file-btn"
          :title="aiEnabled ? '' : t('files.detail.aiDisabled')"
        >
          <span v-if="!aiEnabled">{{ t('files.detail.aiNotConfigured') }}</span>
          <span v-else-if="bulkRunning">{{ t('files.detail.translating') }}</span>
          <span v-else>{{ t('files.detail.translateFile') }}</span>
        </button>

        <label v-if="hasPrevious" class="compare-toggle">
          <input type="checkbox" v-model="compare" @change="reload(1)" />
          {{ t('workflow.compareMode') }}
        </label>
      </div>

      <div v-if="bulkRunning" class="translate-banner">
        {{ t('files.detail.translatingHint') }}
      </div>
      <div v-else-if="lastBulk && lastBulk.total > 0" class="translate-banner translate-banner-ok">
        {{ t('files.detail.translateDone', {
          translated: lastBulk.translated,
          review: lastBulk.needs_review,
          errors: lastBulk.errors,
        }) }}
      </div>

      <div v-if="stats" class="stats-panel">
        <h3>{{ t('files.detail.statsTitle') }}</h3>
        <table class="table">
          <thead>
            <tr>
              <th>{{ t('files.detail.statsMember') }}</th>
              <th class="num">{{ t('files.detail.statsTranslated') }}</th>
              <th class="num">{{ t('files.detail.statsCorrected') }}</th>
              <th class="num">{{ t('files.detail.statsSelfEdits') }}</th>
              <th class="num">{{ t('files.detail.statsValidated') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="m in stats.members" :key="m.user_id">
              <td>{{ m.name }}</td>
              <td class="num">{{ formatNum(m.words_translated) }}</td>
              <td class="num">{{ formatNum(m.words_corrected) }}</td>
              <td class="num muted">{{ formatNum(m.words_self_edits) }}</td>
              <td class="num muted">{{ formatNum(m.words_validated) }}</td>
            </tr>
            <tr>
              <td class="muted">{{ t('files.detail.statsAiUnchecked') }}</td>
              <td colspan="4" class="num">{{ formatNum(stats.total.words_ai_unchecked) }}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div v-if="isInReview" class="review-layout">
        <div class="review-main">
          <div class="review-card">
            <h2>{{ t('workflow.reviewPanel') }}</h2>
            <div v-for="k in keys" :key="'rv-'+k.id" class="review-key">
              <code class="review-key-path">{{ k.key_path }}</code>
              <div class="review-key-body">
                <div class="review-cell">
                  <div class="review-cell-label">{{ t('files.detail.colTranslation') }}</div>
                  <div :class="'review-text status-' + (k.translation?.status || 'empty')">
                    {{ k.translation?.text || '—' }}
                  </div>
                  
                  <!-- New author line -->
                  <div class="review-author">
                    <span v-if="k.translation?.translated_by_ai" class="muted">
                      AI ({{ k.translation.ai_engine || '?' }})
                    </span>
                    <span v-else-if="k.translation?.author_name" class="muted">
                      {{ k.translation.author_name }}
                    </span>
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
                  <span v-if="k.contested" class="badge status-contested" :title="t('files.detail.contestedTip', { n: k.distinct_correctors })">
                    {{ t('files.detail.contested') }}
                  </span>
                </div>
              </div>
              <div class="review-history-toggle">
                <button class="small ghost" @click="toggleHistory(k.id)">
                  {{ t('files.detail.historyLink', { n: historyCounts[k.id] ?? '·' }) }}
                </button>
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
          <select v-model="filter" @change="reload(1)" :disabled="bulkRunning">
            <option value="all">{{ t('files.detail.filterAll') }}</option>
            <option value="empty">{{ t('files.detail.filterEmpty') }}</option>
            <option value="needs_review">{{ t('files.detail.filterNeeds') }}</option>
            <option value="translated">{{ t('files.detail.filterTrans') }}</option>
            <option value="approved">{{ t('files.detail.filterApproved') }}</option>
          </select>
        </label>
        <label>
          {{ t('files.detail.search') }}
          <input v-model="search" @change="reload(1)" placeholder="key or source" :disabled="bulkRunning" />
        </label>
        <label>
          {{ t('files.detail.attention') }}
          <select v-model="attention" @change="reload(1)" :disabled="bulkRunning">
            <option value="">{{ t('files.detail.attAll') }}</option>
            <option value="contested">{{ t('files.detail.attContested') }}</option>
            <option value="hot">{{ t('files.detail.attHot') }}</option>
            <option value="ai_unchecked">{{ t('files.detail.attAi') }}</option>
          </select>
        </label>
      </div>

      <div v-if="keys.length === 0" class="empty-block">
        <p>{{ t('files.detail.noKeys') }}</p>
      </div>

      <div v-else class="editor-table-wrap" :class="{ 'is-busy': bulkRunning }">
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
            <tr v-for="k in keys" :key="k.id" :class="rowClass(k)">
              <td><code>{{ k.key_path }}</code></td>
              <td class="source">{{ k.source_text || t('files.detail.emptyCell') }}</td>
              <td>
                <textarea
                  v-model="draft[k.id].text"
                  :disabled="!canEdit(k) || bulkRunning"
                  class="translation-input textarea-auto"
                ></textarea>
                <input
                  v-if="draft[k.id].status === 'needs_review'"
                  v-model="draft[k.id].note"
                  class="note-input"
                  :placeholder="t('files.detail.note')"
                  :disabled="!canEdit(k) || bulkRunning"
                />
              </td>
              <td>
                <span class="badge" :class="'status-' + (k.translation?.status || 'empty')">
                  {{ statusLabel(k.translation?.status) }}
                </span>
                <span v-if="k.contested" class="badge status-contested" :title="t('files.detail.contestedTip', { n: k.distinct_correctors })">
                  {{ t('files.detail.contested') }}
                </span>
              </td>
              <td class="row-actions-cell">
                <button v-if="canEdit(k)" @click="save(k)" :disabled="busy || bulkRunning" class="small">
                  {{ t('files.detail.save') }}
                </button>
                <button v-if="canEdit(k)" @click="openExpanded(k)" class="small ghost" title="Expand">⤢</button>
                <button
                  v-if="canEdit(k) && aiEnabled"
                  @click="aiOne(k)"
                  :disabled="busy || bulkRunning"
                  class="small ghost"
                >
                  {{ t('files.detail.ai') }}
                </button>
                <button class="small ghost" @click="toggleHistory(k.id)">
                  {{ t('files.detail.historyLink', { n: historyCounts[k.id] ?? '·' }) }}
                </button>
                <span v-if="draft[k.id].savedAt" class="saved">✓</span>
              </td>
            </tr>
          </tbody>
        </table>

        <div class="pagination">
          <span class="muted small-text">
            {{ t('files.detail.pagination', {
              from: (page - 1) * per_page + 1,
              to:   Math.min(page * per_page, total),
              total,
            }) }}
          </span>
          <div class="row-actions">
            <button @click="reload(page - 1)" :disabled="page <= 1 || bulkRunning" class="small ghost">{{ t('files.detail.prev') }}</button>
            <button @click="reload(page + 1)" :disabled="page >= totalPages || bulkRunning" class="small ghost">{{ t('files.detail.next') }}</button>
          </div>
        </div>
      </div>
    </template>
    
    <HistoryPanel 
      :visible="historyVisible" 
      :events="currentHistory.events" 
      @close="historyVisible = false" 
    />

    <div v-if="expandedKey" class="modal-backdrop" @click.self="closeExpanded">
      <div class="modal-card expanded-modal">
        <div class="row">
          <h3>{{ expandedKey.key_path }}</h3>
          <button @click="closeExpanded" class="ghost small">✕</button>
        </div>
        <div class="expanded-source">
          <strong>Source:</strong>
          <p>{{ expandedKey.source_text }}</p>
        </div>
        <div class="expanded-target">
          <textarea v-model="expandedDraft.text" rows="8" class="translation-input large-textarea"></textarea>
        </div>
        <div class="row-actions" style="justify-content: flex-end; margin-top: 16px;">
          <button @click="closeExpanded" class="ghost">Cancel</button>
          <button @click="saveExpanded" :disabled="busy" class="primary">Save</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '../stores/auth'
import { api } from '../api'
import HistoryPanel from '../components/HistoryPanel.vue'

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
const stats = ref(null)

const aiEnabled = ref(false)
const bulkRunning = ref(false)
const lastBulk = ref(null)

const loading = ref(true)
const busy = ref(false)
const error = ref('')

const filter = ref('all')
const search = ref('')
const attention = ref('')
const compare = ref(false)
const page = ref(1)
const per_page = ref(50)
const total = ref(0)
const totalPages = ref(0)
const draft = reactive({})
const assignChoice = ref('')
const approveComment = ref('')
const rejectComment = ref('')

const historyCounts = reactive({})
const currentHistory = reactive({ keyId: null, events: [] })
const historyVisible = ref(false)

const expandedKey = ref(null)
const expandedDraft = reactive({ text: '' })

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

function canEdit(k) {
  if (!revisionOpen.value) return false
  return isProjectLead.value || isAssigned.value
}
const canEditSomething = computed(() => isProjectLead.value || isAssigned.value)
const canSubmit = computed(() => revisionOpen.value && isProjectLead.value && file.value?.status !== 'in_review')
const canApprove = computed(() => isInReview.value && (isProjectLead.value || isGlobalAdmin.value))

const hasPrevious = computed(() => previousRevisionId.value != null)
const projectLink = computed(() => project.value ? `/projects/${project.value.id}` : '/projects')
function rowClass(k) { return `row-${k.translation?.status || 'empty'}` }
function statusLabel(s) { return t(`files.status.${s || 'empty'}`) }
function formatNum(n) { return (n ?? 0).toLocaleString() }

function errMsg(e) {
  const code = e?.data?.error
  if (code && t(`workflow.errors.${code}`) !== `workflow.errors.${code}`) {
    return t(`workflow.errors.${code}`)
  }
  return e.message
}

function openExpanded(k) {
  expandedKey.value = k
  expandedDraft.text = draft[k.id].text
}

function closeExpanded() {
  expandedKey.value = null
}

async function saveExpanded() {
  draft[expandedKey.value.id].text = expandedDraft.text
  await save(expandedKey.value)
  closeExpanded()
}

async function toggleHistory(keyId) {
  try {
    const data = await api.get(`/api/v1/keys/${keyId}/history`)
    currentHistory.events = data.events || []
    currentHistory.keyId = keyId
    historyVisible.value = true
    historyCounts[keyId] = (data.events || []).length
  } catch (_) {
    currentHistory.events = []
    currentHistory.keyId = keyId
    historyVisible.value = true
  }
}

async function loadEngines() {
  try {
    const data = await api.get('/api/v1/ai/engines')
    const list = data.engines || []
    aiEnabled.value = list.some(e => e.enabled && e.name === 'libretranslate')
  } catch (_) { aiEnabled.value = false }
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
    await reload(1)
    await loadStats()

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

async function loadStats() {
  try {
    stats.value = await api.get(`/api/v1/files/${file.value.id}/member_stats`)
  } catch (_) { stats.value = null }
}

async function reload(p = page.value) {
  if (p < 1) p = 1
  page.value = p
  const id = route.params.id
  const params = [`page=${p}`, `per_page=${per_page.value}`]
  if (filter.value !== 'all') params.push(`status=${filter.value}`)
  if (compare.value)         params.push('with_previous=1')
  if (attention.value)       params.push(`attention=${attention.value}`)
  if (search.value.trim())   params.push(`q=${encodeURIComponent(search.value.trim())}`)
  const data = await api.get(`/api/v1/files/${id}/keys?${params.join('&')}`)
  keys.value = data.keys || []
  previousRevisionId.value = data.previous_revision_id ?? null
  total.value = data.total || 0
  totalPages.value = data.total_pages || 0
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

async function refreshFile() {
  try {
    const data = await api.get(`/api/v1/files/${route.params.id}`)
    file.value = data.file
    revision.value = data.revision
  } catch (_) {}
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
  const current = k.translation?.text || ''
  const next = draft[k.id].text || ''
  const currentNote = k.translation?.note || ''
  const nextNote = draft[k.id].note || ''
  const currentStatus = k.translation?.status || 'empty'
  let nextStatus = draft[k.id].status || 'empty'

  if (nextStatus === 'ai_draft' || nextStatus === 'empty') {
    nextStatus = nextNote.length > 0 ? 'needs_review' : 'translated'
  }

  if (current === next && currentNote === nextNote && currentStatus === nextStatus) {
    draft[k.id].savedAt = Date.now()
    return
  }

  busy.value = true
  error.value = ''
  try {
    const body = { text: next, status: nextStatus }
    if (nextStatus === 'needs_review') {
      body.note = nextNote
    }
    const data = await api.patch(`/api/v1/keys/${k.id}/translation`, body)
    k.translation = data.translation
    draft[k.id].status = data.translation.status
    draft[k.id].note = data.translation.note || ''
    draft[k.id].savedAt = Date.now()
    delete historyCounts[k.id]
    await loadStats()
    await refreshFile()
  } catch (e) { error.value = errMsg(e) }
  finally { busy.value = false }
}

async function aiOne(k) {
  busy.value = true
  error.value = ''
  try {
    const data = await api.post(`/api/v1/keys/${k.id}/ai_translate`, {
      engine: 'libretranslate',
    })
    k.translation = data.translation
    draft[k.id].text = data.translation.text || ''
    draft[k.id].status = data.translation.status
    draft[k.id].note = data.translation.note || ''
    delete historyCounts[k.id]
    await loadStats()
    await refreshFile()
  } catch (e) { error.value = errMsg(e) }
  finally { busy.value = false }
}

async function translateFile() {
  bulkRunning.value = true
  error.value = ''
  lastBulk.value = null
  try {
    const data = await api.post(`/api/v1/files/${file.value.id}/ai_translate`, {
      engine: 'libretranslate',
    })
    lastBulk.value = data
    for (const k in historyCounts) delete historyCounts[k]
    await reload(1)
    await loadStats()
    await refreshFile()
  } catch (e) {
    error.value = errMsg(e)
  } finally {
    bulkRunning.value = false
  }
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

function formatLastAction(k) {
  if (!k.translation) return t('files.detail.emptyCell')
  if (k.translation.translated_by_ai) {
    return `AI (${k.translation.ai_engine || '?'})`
  }
  const author = k.translation.translated_by_user_id === auth.user?.id ? 'You' : `User #${k.translation.translated_by_user_id}`
  // We will improve this when the API sends user names in the translation object
  return `${t('files.detail.actionLabels.' + (k.translation.status || 'empty'))} by ${author}`
}

onMounted(load)
</script>
