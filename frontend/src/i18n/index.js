import { createI18n } from 'vue-i18n'
import en from './en.js'

const SUPPORTED = { en }
const DEFAULT   = 'en'

function pickLocale() {
  const nav = (typeof navigator !== 'undefined' && navigator.language) || DEFAULT
  const short = nav.split('-')[0]
  return SUPPORTED[short] ? short : DEFAULT
}

const i18n = createI18n({
  legacy: false,
  globalInjection: true,
  locale: pickLocale(),
  fallbackLocale: DEFAULT,
  messages: SUPPORTED,
})

export default i18n
export { SUPPORTED, DEFAULT }
