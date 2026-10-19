<template>
  <div v-if="visible" class="modal-backdrop" @click.self="$emit('close')">
    <div class="modal-card expanded-modal">
      <div class="row">
        <h3>{{ t('files.detail.exportPreview') }}</h3>
        <button @click="$emit('close')" class="ghost small">✕</button>
      </div>
      
      <p v-if="loading" class="muted">{{ t('common.loading') }}</p>
      <p v-else-if="error" class="error">{{ error }}</p>
      
      <template v-else>
        <div class="export-actions">
          <button @click="copyToClipboard" class="primary small">
            {{ copyLabel }}
          </button>
          <a :href="`/api/v1/files/${fileId}/export`" class="btn-link small" target="_blank">
            {{ t('files.detail.downloadFile') }}
          </a>
        </div>
        
        <pre class="code-preview"><code>{{ content }}</code></pre>
      </template>
    </div>
  </div>
</template>

<script setup>
import { ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { api } from '../api'

const props = defineProps({
  visible: { type: Boolean, default: false },
  fileId: { type: Number, required: true },
})

const emit = defineEmits(['close'])
const { t } = useI18n()

const loading = ref(false)
const error = ref('')
const content = ref('')
const copyLabel = ref('Copy to Clipboard')

async function fetchPreview() {
  loading.value = true
  error.value = ''
  try {
    const data = await api.post(`/api/v1/files/${props.fileId}/preview`)
    content.value = data.content
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

watch(() => props.visible, (newVal) => {
  if (newVal) {
    fetchPreview()
    copyLabel.value = t('files.detail.copyToClipboard')
  }
})

async function copyToClipboard() {
  try {
    await navigator.clipboard.writeText(content.value)
    copyLabel.value = t('files.detail.copied')
    setTimeout(() => { copyLabel.value = t('files.detail.copyToClipboard') }, 2000)
  } catch (e) {
    console.error('Failed to copy', e)
  }
}
</script>
