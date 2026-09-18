<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, reactive, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import PagePagination from '@/components/PagePagination.vue'
import SecuritySecretInput from '@/views/settings/security/SecuritySecretInput.vue'
import { normalizeVpnProxyInput, type VpnProxyApiError, type VpnProxyInput, type VpnProxyRecord, type VpnProxyTenant } from '@/api/vpnProxy'

const props = defineProps<{
  modelValue: boolean
  record: VpnProxyRecord | null
  tenants: VpnProxyTenant[]
  tenantsLoading: boolean
  tenantsProblem: VpnProxyApiError | null
  canSubmit: boolean
  pending: boolean
  problem: VpnProxyApiError | null
}>()
const emit = defineEmits<{
  'update:modelValue': [value: boolean]
  save: [input: VpnProxyInput]
  reloadTenants: []
}>()
const { t } = useI18n()
type PasswordMode = 'keep' | 'replace' | 'clear'
type FormDraft = {
  customName: string; proxyType: string; proxyHost: string; proxyPort: string
  proxyUsername: string; proxyPassword: string; availableStatus: 0 | 1 | ''; forceProxy: 0 | 1 | ''; tenantIds: string[]
}
const draft = reactive<FormDraft>({ customName: '', proxyType: 'HTTP', proxyHost: '', proxyPort: '', proxyUsername: '', proxyPassword: '', availableStatus: 1, forceProxy: 0, tenantIds: [] })
const passwordMode = ref<PasswordMode>('replace')
const phase = ref<'edit' | 'review'>('edit')
const query = ref('')
const tenantPage = ref(1)
const discard = ref(false)
const globalConfirmation = ref(false)
const invalid = ref(false)
const submitted = ref(false)
const reviewHeading = ref<HTMLElement>()
const errorNotice = ref<HTMLElement>()
const discardNotice = ref<HTMLElement>()
const globalNotice = ref<HTMLElement>()
const firstInput = ref<HTMLInputElement>()
let baseline = ''
let disposed = false
const pageSize = 7
const editing = computed(() => props.record !== null)
const locked = computed(() => props.pending || submitted.value)
const writeBlocked = computed(() => locked.value || !props.canSubmit || !!props.problem?.writeAttempted)
const formLocked = computed(() => locked.value || phase.value === 'review' || discard.value)
const legacyType = computed(() => props.record && !['HTTP', 'HTTPS'].includes(props.record.proxyType) ? props.record.proxyType : '')
const chosen = computed(() => new Set(draft.tenantIds))
const tenantMap = computed(() => new Map(props.tenants.map(tenant => [tenant.id, tenant])))
const matches = computed(() => {
  const needle = query.value.trim().toLowerCase()
  return props.tenants.filter(tenant => !needle || [tenant.name, tenant.region, tenant.id].some(value => value.toLowerCase().includes(needle)))
})
const pageCount = computed(() => Math.max(1, Math.ceil(matches.value.length / pageSize)))
const visibleTenants = computed(() => matches.value.slice((tenantPage.value - 1) * pageSize, tenantPage.value * pageSize))
const missingIds = computed(() => props.tenantsLoading || props.tenantsProblem ? [] : draft.tenantIds.filter(id => !tenantMap.value.has(id)))
const passwordSummary = computed(() => {
  if (passwordMode.value === 'keep') return t(props.record?.hasPassword ? 'vpnProxy.editor.passwordKeep' : 'vpnProxy.editor.reviewNoPassword')
  if (passwordMode.value === 'clear' || !draft.proxyPassword) return t('vpnProxy.editor.reviewNoPassword')
  return t('vpnProxy.editor.passwordReplace')
})
const dirty = computed(() => snapshot() !== baseline)

function snapshot(): string {
  // Only empty password drafts enter the baseline; replacement secrets remain local.
  return JSON.stringify({ ...draft, tenantIds: [...draft.tenantIds].sort(), passwordMode: passwordMode.value })
}
function initialize() {
  const record = props.record
  Object.assign(draft, {
    customName: record?.customName ?? '', proxyType: record?.proxyType ?? 'HTTP', proxyHost: record?.proxyHost ?? '',
    proxyPort: record?.proxyPort == null ? '' : String(record.proxyPort), proxyUsername: record?.proxyUsername ?? '', proxyPassword: '',
    availableStatus: record ? record.availableStatus ?? '' : 1, forceProxy: record ? record.forceProxy ?? '' : 0,
    tenantIds: record ? [...new Set(record.tenantIds)] : [],
  })
  passwordMode.value = record ? 'keep' : 'replace'
  phase.value = 'edit'; query.value = ''; tenantPage.value = 1
  discard.value = false; globalConfirmation.value = false; invalid.value = false; submitted.value = false
  baseline = snapshot()
}
function clearSecret() { draft.proxyPassword = '' }
function tenantLabel(id: string): string { return tenantMap.value.get(id)?.name || t('vpnProxy.editor.tenantUnavailable', { id }) }
function requestClose() {
  if (locked.value) return
  if (dirty.value) {
    discard.value = true
    void nextTick(() => { if (!disposed) discardNotice.value?.focus() })
    return
  }
  close()
}
function close() {
  if (locked.value) return
  clearSecret(); baseline = ''; discard.value = false; globalConfirmation.value = false
  emit('update:modelValue', false)
}
function keepEditing() {
  discard.value = false
  void nextTick(() => { if (!disposed) (phase.value === 'review' ? reviewHeading.value : firstInput.value)?.focus() })
}
function visibility(value: boolean) { if (!value) requestClose() }
function toggleTenant(id: string, event: Event) {
  const input = event.target as HTMLInputElement
  if (formLocked.value || globalConfirmation.value) { input.checked = chosen.value.has(id); return }
  if (chosen.value.has(id)) {
    if (draft.tenantIds.length === 1) { input.checked = true; requestGlobal(); return }
    draft.tenantIds = draft.tenantIds.filter(value => value !== id)
  } else draft.tenantIds.push(id)
  input.checked = chosen.value.has(id)
}
function requestGlobal() {
  if (formLocked.value || !draft.tenantIds.length) return
  globalConfirmation.value = true
  void nextTick(() => { if (!disposed) globalNotice.value?.focus() })
}
function applyGlobal() {
  if (formLocked.value) return
  draft.tenantIds = []; globalConfirmation.value = false
}
function changePage(value: number) {
  if (formLocked.value || props.tenantsLoading || globalConfirmation.value) return
  tenantPage.value = Math.max(1, Math.min(pageCount.value, value))
}
function changePasswordMode(value: unknown) {
  if (formLocked.value) return
  if (value === 'keep' || value === 'replace' || value === 'clear') { passwordMode.value = value; clearSecret() }
}
function payload(): VpnProxyInput {
  if (!/^\d+$/.test(draft.proxyPort) || draft.availableStatus === '' || draft.forceProxy === ''
    || (editing.value && passwordMode.value === 'replace' && !draft.proxyPassword)) throw new Error('Invalid proxy input')
  return normalizeVpnProxyInput({
    ...(props.record ? { id: props.record.id } : {}),
    customName: draft.customName, proxyType: draft.proxyType, proxyHost: draft.proxyHost,
    proxyPort: Number(draft.proxyPort), proxyUsername: draft.proxyUsername,
    ...(passwordMode.value === 'keep' ? {} : { proxyPassword: passwordMode.value === 'clear' ? '' : draft.proxyPassword }),
    availableStatus: draft.availableStatus, forceProxy: draft.forceProxy, tenantIds: [...draft.tenantIds],
  }, props.record ?? undefined)
}
async function review() {
  if (writeBlocked.value || discard.value || globalConfirmation.value || phase.value !== 'edit') return
  try { payload() } catch {
    invalid.value = true
    await nextTick()
    if (!disposed) errorNotice.value?.focus()
    return
  }
  invalid.value = false; phase.value = 'review'
  await nextTick()
  if (!disposed) reviewHeading.value?.focus()
}
function backToEdit() {
  if (locked.value) return
  phase.value = 'edit'; discard.value = false
  void nextTick(() => { if (!disposed) firstInput.value?.focus() })
}
function save() {
  if (writeBlocked.value || discard.value || phase.value !== 'review') return
  try {
    const input = payload()
    submitted.value = true
    emit('save', input)
    // A parent guard may decline the event before starting a request.
    void nextTick(() => { if (!disposed && !props.pending) submitted.value = false })
  } catch {
    invalid.value = true; phase.value = 'edit'
    void nextTick(() => { if (!disposed) errorNotice.value?.focus() })
  }
}
function formSubmit() { if (phase.value === 'edit') void review() }
function searchEnter(event: KeyboardEvent) { if (!event.isComposing) event.preventDefault() }
function reloadTenants() { if (!locked.value && !props.tenantsLoading) emit('reloadTenants') }

watch(() => [props.modelValue, props.record?.id], () => {
  if (props.modelValue) initialize()
  else { clearSecret(); baseline = ''; discard.value = false; globalConfirmation.value = false }
}, { immediate: true })
watch(query, () => { tenantPage.value = 1 })
watch(pageCount, value => { tenantPage.value = Math.min(tenantPage.value, value) })
watch(() => props.pending, (pending, previous) => {
  if (pending) submitted.value = true
  else if (previous) { submitted.value = false; phase.value = 'edit' }
})
watch(() => props.problem, problem => { if (problem && !props.pending) { submitted.value = false; phase.value = 'edit' } })
onBeforeUnmount(() => { disposed = true; clearSecret(); baseline = '' })
</script>

<template>
  <el-dialog :model-value="modelValue" width="980px" class="proxy-editor-dialog" append-to-body destroy-on-close
    :title="t(editing ? 'vpnProxy.editor.editTitle' : 'vpnProxy.editor.createTitle')"
    :close-on-click-modal="false" :close-on-press-escape="!locked" :show-close="!locked" :before-close="requestClose" @update:model-value="visibility">
    <div class="proxy-editor">
      <PageErrorNotice v-if="problem">{{ t(`vpnProxy.errors.${problem.key}`) }}</PageErrorNotice>
      <div v-if="discard" ref="discardNotice" class="proxy-editor-notice" role="alert" tabindex="-1">
        <p>{{ t('vpnProxy.editor.discardTitle') }}</p><div class="proxy-editor-actions"><GhostBtn @click="keepEditing">{{ t('vpnProxy.editor.keepEditing') }}</GhostBtn><GhostBtn danger @click="close">{{ t('vpnProxy.editor.discardChanges') }}</GhostBtn></div>
      </div>
      <form v-if="phase === 'edit'" id="proxy-editor-form" class="proxy-editor-form" :aria-busy="locked" @submit.prevent="formSubmit">
        <fieldset :disabled="formLocked">
          <div class="proxy-editor-split">
            <section class="proxy-editor-config" aria-labelledby="proxy-editor-config-title">
              <header class="proxy-editor-pane-title"><h3 id="proxy-editor-config-title">{{ t('vpnProxy.editor.configTitle') }}</h3><p>{{ t('vpnProxy.editor.configHint') }}</p></header>
              <div class="proxy-editor-field"><label for="proxy-editor-name">{{ t('vpnProxy.editor.customName') }}</label><input id="proxy-editor-name" ref="firstInput" v-model="draft.customName" type="text" maxlength="128" autocomplete="off" /></div>
              <div class="proxy-editor-field"><label for="proxy-editor-type">{{ t('vpnProxy.editor.type') }}</label><el-select id="proxy-editor-type" v-model="draft.proxyType" :disabled="formLocked" :teleported="true"><el-option v-if="legacyType" :value="legacyType" :label="legacyType" disabled /><el-option value="HTTP" label="HTTP" /><el-option value="HTTPS" label="HTTPS" /></el-select><small v-if="legacyType">{{ t('vpnProxy.editor.legacyTypeHint', { type: legacyType }) }}</small></div>
              <div class="proxy-editor-host-port">
                <div class="proxy-editor-field"><label for="proxy-editor-host">{{ t('vpnProxy.editor.host') }}</label><input id="proxy-editor-host" v-model="draft.proxyHost" type="text" required maxlength="128" autocomplete="off" autocapitalize="off" :spellcheck="false" /><small>{{ t('vpnProxy.editor.hostHint') }}</small></div>
                <div class="proxy-editor-field"><label for="proxy-editor-port">{{ t('vpnProxy.editor.port') }}</label><input id="proxy-editor-port" v-model="draft.proxyPort" type="text" required maxlength="5" inputmode="numeric" pattern="[0-9]+" autocomplete="off" /></div>
              </div>
              <div class="proxy-editor-field"><label for="proxy-editor-username">{{ t('vpnProxy.editor.username') }}</label><input id="proxy-editor-username" v-model="draft.proxyUsername" type="text" maxlength="64" autocomplete="off" autocapitalize="off" :spellcheck="false" /></div>
              <div v-if="editing" class="proxy-editor-field"><label for="proxy-editor-password-mode">{{ t('vpnProxy.editor.passwordMode') }}</label><el-select id="proxy-editor-password-mode" :model-value="passwordMode" :disabled="formLocked" :teleported="true" @update:model-value="changePasswordMode"><el-option value="keep" :label="t('vpnProxy.editor.passwordKeep')" /><el-option value="replace" :label="t('vpnProxy.editor.passwordReplace')" /><el-option value="clear" :label="t('vpnProxy.editor.passwordClear')" /></el-select><small>{{ t(passwordMode === 'clear' ? 'vpnProxy.editor.passwordClearHint' : 'vpnProxy.editor.passwordKeepHint') }}</small></div>
              <SecuritySecretInput v-if="passwordMode === 'replace'" id="proxy-editor-password" v-model="draft.proxyPassword" :label="t('vpnProxy.editor.password')" :disabled="formLocked" />
              <div class="proxy-editor-pair">
                <div class="proxy-editor-field"><label for="proxy-editor-status">{{ t('vpnProxy.editor.status') }}</label><el-select id="proxy-editor-status" v-model="draft.availableStatus" :disabled="formLocked" :teleported="true" :empty-values="[null, undefined]" aria-required="true"><el-option value="" label="—" disabled /><el-option :value="1" :label="t('vpnProxy.editor.statusAvailable')" /><el-option :value="0" :label="t('vpnProxy.editor.statusUnavailable')" /></el-select><small>{{ t('vpnProxy.editor.statusHint') }}</small></div>
                <div class="proxy-editor-field"><label for="proxy-editor-force">{{ t('vpnProxy.editor.force') }}</label><el-select id="proxy-editor-force" v-model="draft.forceProxy" :disabled="formLocked" :teleported="true" :empty-values="[null, undefined]" aria-required="true"><el-option value="" label="—" disabled /><el-option :value="0" :label="t('vpnProxy.editor.forceOff')" /><el-option :value="1" :label="t('vpnProxy.editor.forceOn')" /></el-select><small>{{ t('vpnProxy.editor.forceHint') }}</small></div>
              </div>
            </section>
            <section class="proxy-editor-tenants" aria-labelledby="proxy-editor-tenants-title">
              <header class="proxy-editor-pane-title"><h3 id="proxy-editor-tenants-title">{{ t('vpnProxy.editor.tenantTitle') }}</h3><p>{{ t('vpnProxy.editor.tenantHint') }}</p></header>
              <p v-if="tenants.length >= 1000" class="proxy-editor-help">{{ t('vpnProxy.editor.tenantLimitHint') }}</p>
              <div class="proxy-editor-selection"><strong role="status">{{ draft.tenantIds.length ? t('vpnProxy.editor.selectedCount', { count: draft.tenantIds.length }) : t('vpnProxy.editor.globalScope') }}</strong><GhostBtn :disabled="formLocked || !draft.tenantIds.length || globalConfirmation" @click="requestGlobal">{{ t('vpnProxy.editor.makeGlobal') }}</GhostBtn></div>
              <div v-if="globalConfirmation" ref="globalNotice" class="proxy-editor-notice" role="alert" tabindex="-1"><p>{{ t('vpnProxy.editor.globalConfirm') }}</p><div class="proxy-editor-actions"><GhostBtn @click="globalConfirmation = false">{{ t('vpnProxy.editor.cancel') }}</GhostBtn><GhostBtn @click="applyGlobal">{{ t('vpnProxy.editor.globalApply') }}</GhostBtn></div></div>
              <label class="proxy-editor-search"><span>{{ t('vpnProxy.editor.searchTenants') }}</span><input v-model="query" type="search" autocomplete="off" :disabled="formLocked || globalConfirmation" @keydown.enter="searchEnter" /></label>
              <PageErrorNotice v-if="tenantsProblem"><p>{{ t(`vpnProxy.errors.${tenantsProblem.key}`) }}</p><GhostBtn :loading="tenantsLoading" :disabled="locked" @click="reloadTenants">{{ t('vpnProxy.editor.reloadTenants') }}</GhostBtn></PageErrorNotice>
              <p v-if="tenantsLoading" class="proxy-editor-help" role="status">{{ t('vpnProxy.editor.tenantsLoading') }}</p>
              <div class="proxy-editor-tenant-list" :aria-busy="tenantsLoading">
                <label v-for="tenant in visibleTenants" :key="tenant.id" class="proxy-editor-tenant-row">
                  <input type="checkbox" :checked="chosen.has(tenant.id)" :disabled="formLocked || globalConfirmation || tenantsLoading" @change="toggleTenant(tenant.id, $event)" />
                  <span><b>{{ tenant.name || tenant.id }}</b><small>{{ tenant.region || '—' }} · {{ tenant.id }}</small></span>
                </label>
                <p v-if="!visibleTenants.length && !tenantsLoading && !tenantsProblem" class="proxy-editor-empty">{{ t('vpnProxy.editor.tenantEmpty') }}</p>
              </div>
              <PagePagination :current-page="tenantPage" :page-size="pageSize" :total="matches.length" :disabled="formLocked || globalConfirmation || tenantsLoading" embedded @current-change="changePage"><span>{{ t('vpnProxy.editor.tenantCount', { count: matches.length }) }}</span></PagePagination>
              <div v-if="missingIds.length" class="proxy-editor-missing"><p class="proxy-editor-help">{{ t('vpnProxy.editor.tenantMissingHint') }}</p><label v-for="id in missingIds" :key="id" class="proxy-editor-tenant-row"><input type="checkbox" checked :disabled="formLocked || globalConfirmation" @change="toggleTenant(id, $event)" /><span><b>{{ t('vpnProxy.editor.tenantUnavailable', { id }) }}</b><small>{{ id }}</small></span></label></div>
            </section>
          </div>
        </fieldset>
        <p v-if="invalid" ref="errorNotice" class="proxy-editor-notice is-error" role="alert" tabindex="-1">{{ t('vpnProxy.editor.invalidInput') }}</p>
      </form>
      <section v-else class="proxy-editor-review" aria-labelledby="proxy-editor-review-title">
        <h3 id="proxy-editor-review-title" ref="reviewHeading" tabindex="-1">{{ t('vpnProxy.editor.reviewTitle') }}</h3><p class="proxy-editor-help">{{ t('vpnProxy.editor.reviewHint') }}</p>
        <dl><dt>{{ t('vpnProxy.editor.customName') }}</dt><dd>{{ draft.customName.trim() || '—' }}</dd><dt>{{ t('vpnProxy.editor.type') }}</dt><dd>{{ draft.proxyType }}</dd><dt>{{ t('vpnProxy.editor.host') }}</dt><dd>{{ draft.proxyHost.trim() }}</dd><dt>{{ t('vpnProxy.editor.port') }}</dt><dd>{{ draft.proxyPort }}</dd><dt>{{ t('vpnProxy.editor.username') }}</dt><dd>{{ draft.proxyUsername || '—' }}</dd><dt>{{ t('vpnProxy.editor.password') }}</dt><dd>{{ passwordMode === 'clear' ? t('vpnProxy.editor.passwordClear') : passwordSummary }}</dd><dt>{{ t('vpnProxy.editor.status') }}</dt><dd>{{ t(draft.availableStatus === 1 ? 'vpnProxy.editor.statusAvailable' : 'vpnProxy.editor.statusUnavailable') }}</dd><dt>{{ t('vpnProxy.editor.force') }}</dt><dd>{{ t(draft.forceProxy === 1 ? 'vpnProxy.editor.forceOn' : 'vpnProxy.editor.forceOff') }}</dd><dt>{{ t('vpnProxy.editor.tenantTitle') }}</dt><dd><template v-if="draft.tenantIds.length"><span>{{ t('vpnProxy.editor.selectedCount', { count: draft.tenantIds.length }) }}</span><ul><li v-for="id in draft.tenantIds" :key="id">{{ tenantLabel(id) }} · {{ id }}</li></ul></template><span v-else>{{ t('vpnProxy.editor.globalScope') }}</span></dd></dl>
        <p class="proxy-editor-help">{{ t(draft.tenantIds.length ? 'vpnProxy.editor.reviewBindingHint' : 'vpnProxy.editor.reviewGlobalHint') }}</p>
      </section>
      <p v-if="locked" class="proxy-editor-notice" role="status">{{ t('vpnProxy.editor.submitting') }}</p>
    </div>
    <template #footer><div class="proxy-editor-footer"><GhostBtn :disabled="locked" @click="requestClose">{{ t('vpnProxy.editor.cancel') }}</GhostBtn><GhostBtn v-if="phase === 'review'" :disabled="locked || discard" @click="backToEdit">{{ t('vpnProxy.editor.backToEdit') }}</GhostBtn><PrimaryBtn v-if="phase === 'edit'" type="submit" form="proxy-editor-form" :disabled="writeBlocked || discard || globalConfirmation || (editing && !dirty)">{{ t('vpnProxy.editor.review') }}</PrimaryBtn><PrimaryBtn v-else :loading="locked" :disabled="writeBlocked || discard" @click="save">{{ t('vpnProxy.editor.confirmSave') }}</PrimaryBtn></div></template>
  </el-dialog>
</template>

<style scoped>
:global(.proxy-editor-dialog) { max-width: calc(100vw - 28px); margin-top: min(7vh, 56px); background: var(--bg-card); color: var(--text-primary); font-family: var(--sans); }
:global(.proxy-editor-dialog .el-dialog__title) { color: var(--text-primary); font: 600 var(--font-size-dialog-title)/1.5 var(--sans); }
:global(.proxy-editor-dialog .el-dialog__body) { max-height: calc(85vh - 130px); max-height: calc(85dvh - 130px); overflow-y: auto; scrollbar-gutter: stable; }
.proxy-editor { color: var(--text-primary); font: 400 var(--font-size-body)/1.5 var(--sans); }
.proxy-editor-form fieldset { min-width: 0; margin: 0; padding: 0; border: 0; }
.proxy-editor-split { display: grid; grid-template-columns: minmax(0, 1.1fr) minmax(0, 1fr); }
.proxy-editor-config, .proxy-editor-tenants { display: flex; flex-direction: column; min-width: 0; gap: 17px; }
.proxy-editor-config { padding-right: 25px; }
.proxy-editor-tenants { padding-left: 25px; border-left: 1px solid var(--border); }
.proxy-editor-pane-title h3, .proxy-editor-review h3 { margin: 0; color: var(--text-primary); font-size: var(--font-size-body); font-weight: 600; line-height: 1.5; }
.proxy-editor-pane-title p { margin: 6px 0 0; font-size: var(--font-size-secondary); color: var(--text-secondary); }
.proxy-editor-field, .proxy-editor-search { display: grid; min-width: 0; gap: 6px; }
.proxy-editor-field > label, .proxy-editor-search > span { color: var(--text-primary); font-size: var(--font-size-body); font-weight: 500; }
.proxy-editor-field input:where(:not(.el-select__input):not(.el-input__inner)), .proxy-editor-search input { box-sizing: border-box; width: 100%; min-width: 0; height: 36px; padding: 0 10px; border: 1px solid var(--border); border-radius: 8px; outline: none; background: var(--bg-card); color: var(--text-primary); font: inherit; }
.proxy-editor-field input:where(:not(.el-select__input):not(.el-input__inner)):focus, .proxy-editor-search input:focus { border-color: var(--brand); outline: 2px solid color-mix(in srgb, var(--brand) 18%, transparent); outline-offset: 1px; }
.proxy-editor-field > .el-select { width: 100%; min-width: 0; }
.proxy-editor-field :deep(.el-select__wrapper) { min-height: 36px; }
.proxy-editor-field :disabled { cursor: default; }
.proxy-editor-field small, .proxy-editor-help { margin: 0; color: var(--text-secondary); font-size: var(--font-size-secondary); line-height: 1.6; overflow-wrap: anywhere; }
.proxy-editor-host-port { display: grid; grid-template-columns: minmax(0, 1fr) 100px; gap: 14px; }
.proxy-editor-pair { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 14px; }
.proxy-editor-selection { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 8px; }
.proxy-editor-selection strong { font-size: var(--font-size-body); font-weight: 500; }
.proxy-editor-tenant-list { min-width: 0; }
.proxy-editor-tenant-row { display: flex; align-items: center; gap: 10px; min-width: 0; min-height: 53px; padding: 9px 0; box-sizing: border-box; border-bottom: 1px solid var(--border); cursor: pointer; }
.proxy-editor-tenant-row > input { flex: none; width: 16px; height: 16px; margin: 0; accent-color: var(--brand); }
.proxy-editor-tenant-row > input:focus-visible { outline: 2px solid var(--brand); outline-offset: 3px; }
.proxy-editor-tenant-row > span { display: grid; min-width: 0; gap: 2px; overflow-wrap: anywhere; }
.proxy-editor-tenant-row b { font-size: var(--font-size-body); font-weight: 500; }
.proxy-editor-tenant-row small { color: var(--text-secondary); font-size: var(--font-size-secondary); }
.proxy-editor-empty { margin: 0; padding: 24px 0; color: var(--text-secondary); font-size: var(--font-size-secondary); }
.proxy-editor-missing { max-height: 190px; overflow-y: auto; min-width: 0; }
.proxy-editor-notice { margin: 0 0 16px; padding: 12px 0; border-bottom: 1px solid var(--border); color: var(--text-primary); font-size: var(--font-size-body); }
.proxy-editor-notice p { margin: 0 0 10px; }
.proxy-editor-notice.is-error { color: var(--status-danger); }
.proxy-editor-notice:focus, .proxy-editor-review h3:focus { outline: 2px solid var(--brand); outline-offset: 3px; }
.proxy-editor-actions { display: flex; flex-wrap: wrap; align-items: center; gap: 9px; }
.proxy-editor-review > .proxy-editor-help { margin: 8px 0 0; }
.proxy-editor-review dl { display: grid; grid-template-columns: 155px minmax(0, 1fr); margin: 20px 0; }
.proxy-editor-review dt, .proxy-editor-review dd { margin: 0; padding: 10px 0; border-bottom: 1px solid var(--border); font-size: var(--font-size-body); overflow-wrap: anywhere; }
.proxy-editor-review dt { padding-right: 16px; color: var(--text-secondary); }
.proxy-editor-review ul { max-height: 180px; overflow-y: auto; margin: 6px 0 0; padding-left: 18px; }
.proxy-editor-footer { display: flex; justify-content: flex-end; flex-wrap: wrap; align-items: center; gap: 10px; color: var(--text-primary); font-family: var(--sans); }
.proxy-editor :deep(.btn), .proxy-editor-footer :deep(.btn) { min-height: 36px; padding: 7px 12px; font-size: var(--font-size-body); }
@media (max-width: 740px) {
  .proxy-editor-split { grid-template-columns: minmax(0, 1fr); gap: 24px; }
  .proxy-editor-config { padding-right: 0; }
  .proxy-editor-tenants { padding: 24px 0 0; border-left: 0; border-top: 1px solid var(--border); }
  .proxy-editor-review dl { grid-template-columns: 110px minmax(0, 1fr); }
}
@media (max-width: 400px) { .proxy-editor-pair { grid-template-columns: minmax(0, 1fr); } }
</style>
