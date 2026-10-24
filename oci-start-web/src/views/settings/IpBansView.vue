<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { onBeforeRouteLeave, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { loadIpBans, unbanIp, ipBanError, type IpBanApiError, type IpBanRecord } from '@/api/ipBans'
import { useCompactViewport } from '@/composables/useCompactViewport'
import PageBackButton from '@/components/PageBackButton.vue'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import PagePagination from '@/components/PagePagination.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import './ip-bans.scss'

const { t, te, locale } = useI18n(), router = useRouter(), compact = useCompactViewport()
const rows = ref<IpBanRecord[]>([]), total = ref(0), page = ref(1), size = ref(20)
const search = ref(''), submittedIp = ref(''), status = ref<'' | 0 | 1>('')
const loading = ref(false), loaded = ref(false), pending = ref(false), needsRefresh = ref(false)
const problem = ref<IpBanApiError | null>(null), mutationProblem = ref<IpBanApiError | null>(null)
const confirmation = ref<IpBanRecord | null>(null), receipt = ref<{ changed: boolean; ip: string } | null>(null)
const locked = computed(() => pending.value || !!confirmation.value)
const canMutate = computed(() => loaded.value && !loading.value && !problem.value && !needsRefresh.value && !locked.value)
let disposed = false, sequence = 0, controller: AbortController | undefined

function errorText(error: IpBanApiError) { return t(`ipBans.errors.${error.key}`) }
function sourceText(source: string) { return source && te(`ipBans.sources.${source}`) ? t(`ipBans.sources.${source}`) : source || '—' }
function dateText(value: string) { return value ? value.replace('T', ' ') : '—' }
async function load(): Promise<void> {
  controller?.abort()
  const request = new AbortController(), current = ++sequence
  controller = request; loading.value = true; problem.value = null
  try {
    const result = await loadIpBans({ page: page.value, size: size.value, ip: submittedIp.value,
      ...(status.value !== '' ? { status: status.value } : {}) }, request.signal)
    if (disposed || current !== sequence) return
    const lastPage = Math.max(1, Math.ceil(result.total / result.size))
    if (result.page > lastPage) { page.value = lastPage; await load(); return }
    rows.value = result.items; total.value = result.total; page.value = result.page; size.value = result.size
    loaded.value = true; needsRefresh.value = false; mutationProblem.value = null
  } catch (cause) {
    if (disposed || current !== sequence) return
    const error = ipBanError(cause)
    if (error.key !== 'cancelled') problem.value = error
  } finally { if (!disposed && current === sequence) loading.value = false }
}
function refresh() { if (!locked.value) void load() }
function applyFilter() {
  if (locked.value) return
  submittedIp.value = search.value.trim(); page.value = 1; void load()
}
function changeStatus(value: unknown) {
  if (locked.value || (value !== '' && value !== 0 && value !== 1)) return
  status.value = value; page.value = 1; void load()
}
function changePage(value: number) {
  if (locked.value || loading.value || value === page.value) return
  page.value = value; void load()
}
function changeSize(value: number) {
  if (locked.value || loading.value || value === size.value) return
  size.value = value; page.value = 1; void load()
}
function prepareUnban(record: IpBanRecord) {
  if (!canMutate.value || record.status !== 1) return
  mutationProblem.value = null; receipt.value = null
  confirmation.value = { ...record }
}
function closeConfirmation() { if (!pending.value) confirmation.value = null }
async function confirmUnban() {
  const record = confirmation.value
  if (!record || pending.value) return
  pending.value = true; mutationProblem.value = null; receipt.value = null
  try {
    const result = await unbanIp(record.id)
    if (disposed) return
    confirmation.value = null; receipt.value = { changed: result.changed, ip: record.ipAddress }
    await load()
  } catch (cause) {
    if (disposed) return
    confirmation.value = null; mutationProblem.value = ipBanError(cause); needsRefresh.value = true
  } finally { if (!disposed) pending.value = false }
}
function beforeUnload(event: BeforeUnloadEvent) {
  if (pending.value) { event.preventDefault(); event.returnValue = '' }
}
onBeforeRouteLeave(() => !pending.value)
onMounted(() => { void load(); window.addEventListener('beforeunload', beforeUnload) })
onBeforeUnmount(() => { disposed = true; ++sequence; controller?.abort(); window.removeEventListener('beforeunload', beforeUnload) })
</script>

<template>
  <section class="ip-bans-page">
    <header class="ip-bans-toolbar">
      <PageBackButton :disabled="locked" @click="router.push('/system/settings')" />
      <h1>{{ t('ipBans.title') }}</h1>
      <form class="ip-bans-filters" @submit.prevent="applyFilter">
        <input v-model="search" class="ip-bans-search" type="search" maxlength="64" :disabled="locked" :aria-label="t('ipBans.ip')" :placeholder="t('ipBans.searchPlaceholder')" />
        <el-select class="ip-bans-status-filter" :model-value="status" :disabled="locked" :aria-label="t('ipBans.status')" :placeholder="t('ipBans.all')" @change="changeStatus"><el-option value="" :label="t('ipBans.all')" /><el-option :value="1" :label="t('ipBans.active')" /><el-option :value="0" :label="t('ipBans.released')" /></el-select>
        <PrimaryBtn type="submit" :disabled="locked" :loading="loading"><i class="i-mdi-magnify" aria-hidden="true" />{{ t('ipBans.search') }}</PrimaryBtn>
      </form>
      <div class="ip-bans-toolbar-actions" data-page-error-anchor>
        <GhostBtn :loading="loading" :disabled="locked" @click="refresh"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('ipBans.refresh') }}</GhostBtn>
      </div>
    </header>
    <PageErrorNotice v-if="problem"><p>{{ errorText(problem) }}</p><p v-if="problem.detail">{{ problem.detail }}</p></PageErrorNotice>
    <p v-if="problem && loaded" class="ip-bans-notice is-warning" role="status">{{ t('ipBans.retained') }}</p>
    <PageErrorNotice v-if="mutationProblem"><p>{{ errorText(mutationProblem) }}</p><p v-if="mutationProblem.detail">{{ mutationProblem.detail }}</p></PageErrorNotice>
    <p v-if="needsRefresh" class="ip-bans-notice is-warning" role="status">{{ t('ipBans.review') }}</p>
    <p v-else-if="receipt" class="ip-bans-notice" role="status">{{ t(receipt.changed ? 'ipBans.unbanned' : 'ipBans.alreadyReleased', { ip: receipt.ip }) }} <span v-if="problem">{{ t('ipBans.readbackFailed') }}</span><span v-else-if="!loading">{{ t('ipBans.refreshed') }}</span></p>

    <div class="ip-bans-content" :aria-busy="loading">
      <p v-if="!loaded && loading" class="ip-bans-empty" role="status">{{ t('ipBans.loading') }}</p>
      <p v-else-if="loaded && rows.length === 0" class="ip-bans-empty" role="status">{{ t('ipBans.empty') }}</p>
      <div v-else-if="compact" class="ip-bans-mobile-list">
        <article v-for="row in rows" :key="row.id" class="ip-ban-card">
          <header><strong>{{ row.ipAddress }}</strong><span class="ip-ban-status" :class="{ active: row.status === 1 }">{{ t(row.status === 1 ? 'ipBans.active' : 'ipBans.released') }}</span></header>
          <dl>
            <div><dt>{{ t('ipBans.reason') }}</dt><dd>{{ row.reason || '—' }}</dd></div>
            <div><dt>{{ t('ipBans.source') }}</dt><dd>{{ sourceText(row.source) }}</dd></div>
            <div><dt>{{ t('ipBans.operator') }}</dt><dd>{{ row.operatorName || '—' }}</dd></div>
            <div><dt>{{ t('ipBans.created') }}</dt><dd>{{ dateText(row.createTime) }}</dd></div>
            <template v-if="row.status === 0">
              <div><dt>{{ t('ipBans.unbanTime') }}</dt><dd>{{ dateText(row.unbanTime) }}</dd></div>
              <div><dt>{{ t('ipBans.unbanOperator') }}</dt><dd>{{ row.unbanOperatorName || '—' }}</dd></div>
              <div><dt>{{ t('ipBans.unbanReason') }}</dt><dd>{{ row.unbanReason || '—' }}</dd></div>
            </template>
          </dl>
          <GhostBtn v-if="row.status === 1" :disabled="!canMutate" @click="prepareUnban(row)"><i class="i-mdi-lock-open-outline" aria-hidden="true" />{{ t('ipBans.unban') }}</GhostBtn>
        </article>
      </div>
      <table v-else-if="rows.length" class="ip-bans-table">
        <thead><tr><th scope="col">{{ t('ipBans.ip') }}</th><th scope="col">{{ t('ipBans.status') }}</th><th scope="col">{{ t('ipBans.reason') }}</th><th scope="col">{{ t('ipBans.source') }} / {{ t('ipBans.operator') }}</th><th scope="col">{{ t('ipBans.created') }}</th><th scope="col">{{ t('ipBans.unbanInfo') }}</th><th scope="col">{{ t('ipBans.actions') }}</th></tr></thead>
        <tbody><tr v-for="row in rows" :key="row.id">
          <td class="ip-ban-address">{{ row.ipAddress }}</td>
          <td><span class="ip-ban-status" :class="{ active: row.status === 1 }">{{ t(row.status === 1 ? 'ipBans.active' : 'ipBans.released') }}</span></td>
          <td class="ip-ban-reason">{{ row.reason || '—' }}</td>
          <td>{{ sourceText(row.source) }}<small>{{ row.operatorName || '—' }}</small></td>
          <td><time>{{ dateText(row.createTime) }}</time></td>
          <td class="ip-ban-release"><template v-if="row.status === 0"><time>{{ dateText(row.unbanTime) }}</time><small>{{ row.unbanOperatorName || '—' }}</small><small>{{ row.unbanReason || '—' }}</small></template><span v-else>—</span></td>
          <td><GhostBtn v-if="row.status === 1" :disabled="!canMutate" @click="prepareUnban(row)">{{ t('ipBans.unban') }}</GhostBtn><span v-else>—</span></td>
        </tr></tbody>
      </table>
    </div>
    <PagePagination :current-page="page" :page-size="size" :page-sizes="[20, 50, 100]" :total="total" :disabled="loading || locked" @update:current-page="changePage" @update:page-size="changeSize">{{ t('ipBans.total', { count: new Intl.NumberFormat(locale).format(total) }) }}</PagePagination>

    <el-dialog :model-value="!!confirmation" :title="t('ipBans.confirmTitle')" class="ip-ban-dialog" width="480px" append-to-body :close-on-click-modal="false" :close-on-press-escape="!pending" :show-close="!pending" :before-close="closeConfirmation">
      <dl v-if="confirmation" class="ip-ban-confirm-details"><div><dt>{{ t('ipBans.ip') }}</dt><dd>{{ confirmation.ipAddress }}</dd></div><div><dt>{{ t('ipBans.reason') }}</dt><dd>{{ confirmation.reason || '—' }}</dd></div><div><dt>{{ t('ipBans.created') }}</dt><dd>{{ dateText(confirmation.createTime) }}</dd></div></dl>
      <p>{{ t('ipBans.confirmHint') }}</p>
      <p v-if="pending" role="status">{{ t('ipBans.pending') }}</p>
      <template #footer><GhostBtn :disabled="pending" @click="closeConfirmation">{{ t('ipBans.cancel') }}</GhostBtn><PrimaryBtn :loading="pending" @click="confirmUnban">{{ t('ipBans.confirmUnban') }}</PrimaryBtn></template>
    </el-dialog>
  </section>
</template>
