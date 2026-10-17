import { defineStore } from 'pinia'
import { ref } from 'vue'

export const useAuthStore = defineStore('auth', () => {
  const user = ref(null)
  const csrf_token = ref(null)
  const loading = ref(false)

  async function fetchMe() {
    loading.value = true
    try {
      const res = await fetch('/api/v1/auth/me', {
        credentials: 'include',
        headers: { 'Accept': 'application/json' },
      })
      if (!res.ok) {
        user.value = null
        csrf_token.value = null
        return
      }
      const data = await res.json()
      user.value = data.user || null
      csrf_token.value = data.csrf_token || null
    } finally {
      loading.value = false
    }
  }

  async function login(email, password) {
    const res = await fetch('/api/v1/auth/login', {
      method: 'POST',
      credentials: 'include',
      headers: { 'Accept': 'application/json', 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    })
    const data = await res.json().catch(() => ({}))
    if (!res.ok) {
      throw new Error(data.error || `HTTP ${res.status}`)
    }
    user.value = data.user
    csrf_token.value = data.csrf_token
  }

  async function logout() {
    try {
      await fetch('/api/v1/auth/logout', {
        method: 'POST',
        credentials: 'include',
        headers: {
          'Accept': 'application/json',
          ...(csrf_token.value ? { 'X-CSRF-Token': csrf_token.value } : {}),
        },
      })
    } finally {
      user.value = null
      csrf_token.value = null
    }
  }

  return { user, csrf_token, loading, fetchMe, login, logout }
})
