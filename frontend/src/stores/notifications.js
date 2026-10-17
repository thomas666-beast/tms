import { defineStore } from 'pinia'
import { ref } from 'vue'
import { api } from '../api'

export const useNotificationsStore = defineStore('notifications', () => {
  const items = ref([])
  const unread = ref(0)
  let timer = null

  async function refresh() {
    try {
      const data = await api.get('/api/v1/notifications?unread=1')
      items.value = data.notifications || []
      unread.value = data.unread_count || 0
    } catch (_) { /* ignore */ }
  }

  async function markRead(id) {
    await api.post(`/api/v1/notifications/${id}/read`)
    items.value = items.value.filter(n => n.id !== id)
    if (unread.value > 0) unread.value--
  }

  async function markAllRead() {
    await api.post('/api/v1/notifications/read_all')
    items.value = []
    unread.value = 0
  }

  function startPolling() {
    stopPolling()
    refresh()
    timer = setInterval(refresh, 30000)
  }

  function stopPolling() {
    if (timer) { clearInterval(timer); timer = null }
  }

  return { items, unread, refresh, markRead, markAllRead, startPolling, stopPolling }
})
