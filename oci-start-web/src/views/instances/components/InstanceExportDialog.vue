<script setup lang="ts">
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import { computed, onBeforeUnmount, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { tenantError, tenantGet } from '@/api/tenant'
import GhostBtn from '@/components/GhostBtn.vue'

const emit = defineEmits<{ close: [] }>()
const { t } = useI18n()
const busy = ref(false)
const downloaded = ref(false)
const errorKey = ref('')
const errorText = ref('')
const error = computed(() => errorKey.value ? t(`instanceOperations.export.${errorKey.value}`) : errorText.value)
const controller = new AbortController()
let disposed = false

function close() {
  if (!busy.value) emit('close')
}

async function download() {
  if (busy.value || downloaded.value) return
  busy.value = true
  errorKey.value = ''
  errorText.value = ''
  try {
    // /oci/export always includes every tenant; it has no filter or verification-code parameters.
    const file = await tenantGet<Blob>('/oci/export', undefined, { responseType: 'blob', signal: controller.signal, timeout: 120000 })
    if (disposed) return
    if (!(file instanceof Blob) || !file.size || !file.type.toLowerCase().startsWith('text/plain')) {
      errorKey.value = 'format'
      return
    }
    const beginning = await file.slice(0, 128).text()
    if (disposed) return
    if (!beginning.startsWith('# OCI 实例导出')) { errorKey.value = 'format'; return }
    const url = URL.createObjectURL(file)
    const link = document.createElement('a')
    link.href = url
    link.download = `oci-instances-${new Date().toISOString().replace(/[:.]/g, '-')}.txt`
    document.body.append(link)
    link.click()
    link.remove()
    setTimeout(() => URL.revokeObjectURL(url), 1000)
    downloaded.value = true
  } catch (cause) {
    if (disposed) return
    const response = cause as { response?: { data?: unknown } }
    if (response?.response?.data instanceof Blob) errorKey.value = 'failed'
    else errorText.value = tenantError(cause)
  } finally {
    if (!disposed) busy.value = false
  }
}

onBeforeUnmount(() => { disposed = true; controller.abort() })
</script>

<template>
  <el-dialog
    :model-value="true" :title="t('instanceOperations.export.title')" width="540px" align-center
    class="instance-export-dialog" :close-on-click-modal="false" :close-on-press-escape="!busy" :show-close="!busy" @close="close"
  >
    <div class="export-scope">
      <strong>{{ t('instanceOperations.export.scope') }}</strong>
      <p>{{ t('instanceOperations.export.scopeHint') }}</p>
    </div>
    <el-alert :title="t('instanceOperations.export.warning')" type="warning" :closable="false" show-icon />
    <div class="export-contents">
      <strong>{{ t('instanceOperations.export.contents') }}</strong>
      <ul>
        <li>{{ t('instanceOperations.export.addresses') }}</li>
        <li class="export-passwords">{{ t('instanceOperations.export.passwords') }}</li>
        <li>{{ t('instanceOperations.export.configuration') }}</li>
      </ul>
    </div>
    <el-alert v-if="downloaded" :title="t('instanceOperations.export.success')" type="success" :closable="false" show-icon role="status" />
    <PageErrorNotice v-if="error" style="margin-top: 12px">{{ error }}</PageErrorNotice>
    <template #footer>
      <GhostBtn :disabled="busy" @click="close">{{ t(`instanceOperations.actions.${downloaded ? 'close' : 'cancel'}`) }}</GhostBtn>
      <GhostBtn v-if="!downloaded" danger :loading="busy" @click="download">{{ t('instanceOperations.actions.download') }}</GhostBtn>
    </template>
  </el-dialog>
</template>

<style>
.instance-export-dialog { max-width: calc(100vw - 32px); padding: 26px; font-family: var(--sans); font-size: var(--font-size-body); color: var(--text-primary); }
.instance-export-dialog .el-dialog__title { font-size: var(--font-size-dialog-title); font-weight: 600; }
.instance-export-dialog .el-alert__title { font-size: var(--font-size-body); }
.instance-export-dialog .el-alert__content { min-width: 0; overflow-wrap: anywhere; }
.instance-export-dialog .export-scope { padding: 16px; margin-bottom: 20px; border-radius: 14px; background: var(--bg-search); }
.instance-export-dialog .export-scope strong,
.instance-export-dialog .export-contents strong { font-weight: 600; color: var(--text-primary); }
.instance-export-dialog .export-scope p { margin: 6px 0 0; color: var(--text-secondary); font-size: var(--font-size-secondary); line-height: 1.65; }
.instance-export-dialog .export-contents { margin: 22px 0; }
.instance-export-dialog .export-contents ul { margin: 10px 0 0; padding-left: 22px; line-height: 1.85; }
.instance-export-dialog .export-passwords { color: var(--status-danger); }
.instance-export-dialog .el-dialog__footer { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: 8px; }
.instance-export-dialog .el-dialog__footer button { white-space: normal; }
</style>
