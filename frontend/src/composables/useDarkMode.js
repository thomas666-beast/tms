import { ref, watch } from 'vue'

const isDark = ref(false)

export function useDarkMode() {
  function initTheme() {
    const stored = localStorage.getItem('tms-theme')
    if (stored === 'dark') {
      isDark.value = true
      document.documentElement.classList.add('dark')
    } else if (stored === 'light') {
      isDark.value = false
      document.documentElement.classList.remove('dark')
    } else if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
      isDark.value = true
      document.documentElement.classList.add('dark')
    }
  }

  function toggle() {
    isDark.value = !isDark.value
    if (isDark.value) {
      document.documentElement.classList.add('dark')
    } else {
      document.documentElement.classList.remove('dark')
    }
    localStorage.setItem('tms-theme', isDark.value ? 'dark' : 'light')
  }

  return { isDark, initTheme, toggle }
}
