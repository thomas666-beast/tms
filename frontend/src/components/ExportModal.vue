<template>
  <div v-if="visible" class="modal-backdrop" @click.self="$emit('close')">
    <div class="modal-card expanded-modal">
      <div class="row">
        <h3>Export Preview</h3>
        <button @click="$emit('close')" class="ghost small">✕</button>
      </div>
      
      <p v-if="loading" class="muted">Generating preview...</p>
      <p v-else-if="error" class="error">{{ error }}</p>
      
      <template v-else>
        <div class="export-actions">
          <button @click="copyToClipboard" class="primary small">Copy to Clipboard</button>
          <a :href="`/api/v1/files/${fileId}/export`" class="btn-link small" target="_blank">Download File</a>
        </div>
        
        <pre class="code-preview"><code>{{ content }}</code></pre>
      </template>
    </div>
  </div>
</template>

<script setup>
import { ref, watch } from 'vue'
import { api } from '../api'

const props = defineProps({
  visible: { type: Boolean, default: false },
  fileId: { type: Number, required: true },
})

const emit = defineEmits(['close'])

const loading = ref(false)
const error = ref('')
const content = ref('')
const filename = ref('')

async function fetchPreview() {
  loading.value = true
  error.value = ''
  try {
    const data = await api.post(`/api/v1/files/${props.fileId}/preview`)
    content.value = data.content
    filename.value = data.filename
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

watch(() => props.visible, (newVal) => {
  if (newVal) {
    fetchPreview()
  }
})

async function copyToClipboard() {
  try {
    await navigator.clipboard.writeText(content.value)
    // Could add a toast here
  } catch (e) {
    console.error('Failed to copy', e)
  }
}
</script>
