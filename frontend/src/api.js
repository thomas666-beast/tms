import { useAuthStore } from './stores/auth'

async function request(method, url, body) {
  const auth = useAuthStore()
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

  if (!res.ok) {
    const err = new Error((data && data.error) || `HTTP ${res.status}`)
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
