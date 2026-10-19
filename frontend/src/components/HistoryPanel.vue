<template>
  <div class="history-panel">
    <h4>{{ t('files.detail.historyTitle') }}</h4>
    <p v-if="!events.length" class="muted">{{ t('files.detail.historyEmpty') }}</p>
    <table v-else class="table">
      <thead>
        <tr>
          <th>{{ t('files.detail.historyWhen') }}</th>
          <th>{{ t('files.detail.historyWho') }}</th>
          <th>{{ t('files.detail.historyAction') }}</th>
          <th>{{ t('files.detail.historyText') }}</th>
          <th class="num">{{ t('files.detail.historyWords') }}</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="(e, i) in ordered" :key="e.id">
          <td class="muted small-text">{{ formatDate(e.created_at) }}</td>
          <td>
            <span v-if="e.translated_by_ai" class="muted">AI ({{ e.ai_engine || '?' }})</span>
            <span v-else>{{ e.user_name || '?' }}</span>
          </td>
          <td>
            <span class="badge" :class="'action-' + e.action">
              {{ t('files.detail.actionLabels.' + e.action) }}
            </span>
            <span v-if="i === 0" class="badge status-approved small-chip">{{ t('files.detail.historyCurrent') }}</span>
          </td>
          <td class="history-text">{{ e.text }}</td>
          <td class="num muted">{{ e.word_count }}</td>
        </tr>
      </tbody>
    </table>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'

const props = defineProps({ events: { type: Array, default: () => [] } })
const { t } = useI18n()

const ordered = computed(() => {
  const copy = [...props.events]
  copy.sort((a, b) => {
    if (a.created_at < b.created_at) return 1
    if (a.created_at > b.created_at) return -1
    return b.id - a.id
  })
  return copy
})

function formatDate(iso) {
  if (!iso) return ''
  const d = new Date(iso)
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  const hh = String(d.getHours()).padStart(2, '0')
  const mi = String(d.getMinutes()).padStart(2, '0')
  return `${y}-${m}-${day} ${hh}:${mi}`
}
</script>
