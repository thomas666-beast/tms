import { defineStore } from 'pinia'
import { ref } from 'vue'

let nextId = 1

export const useToastStore = defineStore('toast', () => {
  const items = ref([])

  function push(message, kind = 'info', ttl = 4000) {
    const id = nextId++
    items.value.push({ id, message, kind })
    setTimeout(() => {
      items.value = items.value.filter(t => t.id !== id)
    }, ttl)
  }

  function success(message) { push(message, 'success') }
  function error(message)   { push(message, 'error', 6000) }
  function info(message)    { push(message, 'info') }

  return { items, push, success, error, info }
})
