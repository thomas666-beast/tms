import { useAuthStore } from './stores/auth'
import { useToastStore } from './stores/toast'
import router from './router'

async function request(method, url, body) {
  const auth = useAuthStore()
  const toast = useToastStore()
  const headers = { 'Accept': 'application/json' }
  if (body !== undefined) headers['Content-Type'] = 'application/json'
  if (method !== 'GET' && auth.csrf_token) headers['X-CSRF-Token'] = auth.csrf_token

  const res = await fetch(url, {
    method,
    headers,
    credentials: 'include',
    body: body === undefined ? undefined : JSON.stringify(body),
  })

  let data = null
  const ct = res.headers.get('content-type') || ''
  if (ct.includes('application/json')) data = await res.json()

  if (res.status === 401) {
    auth.user = null
    auth.csrf_token = null
    if (router.currentRoute.value.name !== 'login') {
      router.push({ name: 'login', query: { next: router.currentRoute.value.fullPath } })
    }
    const err = new Error('unauthorized')
    err.status = 401
    throw err
  }

  if (!res.ok) {
    const code = (data && data.error) || `HTTP ${res.status}`
    toast.error(code)
    const err = new Error(code)
    err.status = res.status
    err.data = data
    throw err
  }
  return data
}

export const api = {
  get:  (url)        => request('GET', url),
  post: (url, body)  => request('POST', url, body),
  patch:(url, body)  => request('PATCH', url, body),
  del:  (url)        => request('DELETE', url),
}
