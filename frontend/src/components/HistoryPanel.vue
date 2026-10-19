<template>
  <div v-if="visible" class="modal-backdrop" @click.self="$emit('close')">
    <div class="modal-card history-modal">
      <div class="row">
        <h3>{{ t('files.detail.historyTitle') }}</h3>
        <button @click="$emit('close')" class="ghost small">✕</button>
      </div>
      <p v-if="!ordered.length" class="muted">{{ t('files.detail.historyEmpty') }}</p>
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
                <span v-if="e.count > 1" class="count-badge">({{ e.count }}x)</span>
              </span>
              <span v-if="i === 0" class="badge status-approved small-chip">{{ t('files.detail.historyCurrent') }}</span>
            </td>
            <td class="history-text">{{ e.text }}</td>
            <td class="num muted">{{ e.word_count }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'

const props = defineProps({
  visible: { type: Boolean, default: false },
  events: { type: Array, default: () => [] },
})
defineEmits(['close'])
const { t } = useI18n()

const ordered = computed(() => {
  const copy = [...props.events]
  copy.sort((a, b) => {
    if (a.created_at < b.created_at) return -1
    if (a.created_at > b.created_at) return 1
    return a.id - b.id
  })

  const grouped = []
  for (const e of copy) {
    const prev = grouped[grouped.length - 1]
    if (
      prev &&
      prev.action === 'validate' &&
      e.action === 'validate' &&
      prev.translated_by_user_id === e.translated_by_user_id &&
      prev.text === e.text
    ) {
      prev.count = (prev.count || 1) + 1
      prev.created_at = e.created_at
      prev.id = e.id
    } else {
      grouped.push({ ...e, count: 1 })
    }
  }
  return grouped.reverse()
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
