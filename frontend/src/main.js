import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import router from './router'
import './styles.css'
import { useAuthStore } from './stores/auth'

const app = createApp(App)
app.use(createPinia())
app.use(router)

async function boot() {
  const auth = useAuthStore()
  try { await auth.fetchMe() } catch {}
  app.mount('#app')
}

boot()
