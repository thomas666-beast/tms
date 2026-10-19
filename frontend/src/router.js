import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from './stores/auth'

const routes = [
  { path: '/login', name: 'login', component: () => import('./views/Login.vue'), meta: { public: true } },
  { path: '/', name: 'dashboard', component: () => import('./views/Dashboard.vue') },
  { path: '/projects', name: 'projects', component: () => import('./views/Projects.vue') },
  { path: '/projects/:id', name: 'project', component: () => import('./views/Project.vue') },
  { path: '/files/:id', name: 'file', component: () => import('./views/File.vue') },
  { path: '/users', name: 'users', component: () => import('./views/Users.vue'), meta: { admin: true } },
  { path: '/profile', name: 'profile', component: () => import('./views/Profile.vue') },
  { path: '/projects/:id/audit', name: 'audit', component: () => import('./views/Audit.vue') },
  { path: '/:pathMatch(.*)*', redirect: '/' },
]

const router = createRouter({
  history: createWebHistory(),
  routes,
})

router.beforeEach((to) => {
  const auth = useAuthStore()
  if (to.meta.public) {
    if (auth.user && to.name === 'login') return { name: 'dashboard' }
    return true
  }
  if (!auth.user) return { name: 'login', query: { next: to.fullPath } }
  if (to.meta.admin && auth.user.role !== 'admin') return { name: 'dashboard' }
  return true
})

export default router
