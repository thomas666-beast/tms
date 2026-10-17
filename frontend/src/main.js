import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import router from './router'
import i18n from './i18n'
import './styles.css'
import { useAuthStore } from './stores/auth'

const pinia = createPinia()
const app = createApp(App)
app.use(pinia)
app.use(i18n)

async function boot() {
  // Restore the session BEFORE installing the router: app.use(router)
  // triggers the initial navigation, and the guard needs auth.user by then.
  const auth = useAuthStore(pinia)
  try { await auth.fetchMe() } catch {}

  app.use(router)
  await router.isReady()
  app.mount('#app')
}

boot()
