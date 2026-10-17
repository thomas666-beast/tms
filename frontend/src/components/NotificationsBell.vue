<template>
  <div class="bell-wrap">
    <button class="bell" @click="open = !open">
      <span class="bell-icon">🔔</span>
      <span v-if="store.unread" class="bell-count">{{ store.unread }}</span>
    </button>

    <div v-if="open" class="bell-panel" @click.stop>
      <div class="bell-head">
        <span>{{ t('notifications.title') }}</span>
        <button v-if="store.items.length" @click="markAll" class="ghost small">
          {{ t('notifications.markAllRead') }}
        </button>
      </div>

      <ul v-if="store.items.length" class="bell-list">
        <li v-for="n in store.items" :key="n.id" @click="openItem(n)">
          <div class="bell-item-title">
            {{ t('notifications.types.' + n.type) }}
          </div>
          <div class="bell-item-meta">
            <span v-if="n.payload.project_name">{{ n.payload.project_name }}</span>
            <span v-if="n.payload.actor_name" class="dot">·</span>
            <span v-if="n.payload.actor_name">{{ n.payload.actor_name }}</span>
          </div>
          <div class="bell-item-time">{{ fmt(n.created_at) }}</div>
        </li>
      </ul>
      <p v-else class="muted" style="padding: 16px;">{{ t('notifications.empty') }}</p>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useNotificationsStore } from '../stores/notifications'

const { t } = useI18n()
const store = useNotificationsStore()
const router = useRouter()
const open = ref(false)

function fmt(iso) {
  if (!iso) return ''
  const d = new Date(iso)
  const m = String(d.getMinutes()).padStart(2, '0')
  return `${d.toLocaleDateString()} ${d.getHours()}:${m}`
}

async function openItem(n) {
  open.value = false
  try { await store.markRead(n.id) } catch (_) {}
  if (n.entity_type === 'file' && n.entity_id) {
    router.push(`/files/${n.entity_id}`)
  }
}

async function markAll() {
  try { await store.markAllRead() } catch (_) {}
}

function closeOnOutside(e) {
  if (!e.target.closest('.bell-wrap')) open.value = false
}
onMounted(() => document.addEventListener('click', closeOnOutside))
onUnmounted(() => document.removeEventListener('click', closeOnOutside))
</script>
