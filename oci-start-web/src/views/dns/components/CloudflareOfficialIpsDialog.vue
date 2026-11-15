<script setup lang="ts">
import { ElMessage } from 'element-plus'
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import {
  CLOUDFLARE_OFFICIAL_IPV4_CIDRS,
  CLOUDFLARE_OFFICIAL_IPV6_CIDRS,
  cloudflareError,
  fetchCloudflareOfficialIps,
  formatCloudflareNginxRealIpConfig,
  type CloudflareIpFamily,
  type CloudflareOfficialIpEntry,
  type CloudflareOfficialIpsSource,
} from '@/api/cloudflare'
import { useCompactViewport } from '@/composables/useCompactViewport'
import { copyCredentialText } from '@/utils/initialCredentials'

const props = defineProps<{ visible: boolean }>()
const emit = defineEmits<{ close: [] }>()

const { t, locale } = useI18n()
const compact = useCompactViewport()

const loading = ref(false)
const source = ref<CloudflareOfficialIpsSource>('builtin')
const ipv4Cidrs = ref<string[]>([...CLOUDFLARE_OFFICIAL_IPV4_CIDRS])
const ipv6Cidrs = ref<string[]>([...CLOUDFLARE_OFFICIAL_IPV6_CIDRS])

const keyword = ref('')
const familyFilter = ref<'ALL' | CloudflareIpFamily>('ALL')
const copiedKey = ref('')

let activeController: AbortController | null = null
let copyResetTimer: ReturnType<typeof setTimeout> | null = null

const numberFormat = computed(() => new Intl.NumberFormat(locale.value === 'en' ? 'en-US' : 'zh-CN'))
function formatCount(value: number): string {
  return numberFormat.value.format(value)
}

const allEntries = computed<CloudflareOfficialIpEntry[]>(() => [
  ...ipv4Cidrs.value.map(cidr => ({ cidr, family: 'IPv4' as const })),
  ...ipv6Cidrs.value.map(cidr => ({ cidr, family: 'IPv6' as const })),
])

const filteredEntries = computed(() => {
  const query = keyword.value.trim().toLowerCase()
  const family = familyFilter.value
  return allEntries.value.filter(entry => {
    if (family !== 'ALL' && entry.family !== family) return false
    if (query && !entry.cidr.toLowerCase().includes(query)) return false
    return true
  })
})

const filteredIpv4Count = computed(() => filteredEntries.value.filter(entry => entry.family === 'IPv4').length)
const filteredIpv6Count = computed(() => filteredEntries.value.filter(entry => entry.family === 'IPv6').length)

const summaryText = computed(() => t('cloudflareDns.officialIps.summary', {
  total: formatCount(filteredEntries.value.length),
  ipv4: formatCount(filteredIpv4Count.value),
  ipv6: formatCount(filteredIpv6Count.value),
}))

function cancelPending(): void {
  activeController?.abort()
  activeController = null
}

function resetCopyFeedback(): void {
  if (copyResetTimer) {
    clearTimeout(copyResetTimer)
    copyResetTimer = null
  }
  copiedKey.value = ''
}

function setCopiedState(key: string): void {
  resetCopyFeedback()
  copiedKey.value = key
  copyResetTimer = setTimeout(() => {
    copiedKey.value = ''
    copyResetTimer = null
  }, 1800)
}

async function syncOfficialIps(): Promise<void> {
  cancelPending()
  const controller = new AbortController()
  activeController = controller
  loading.value = true
  try {
    const result = await fetchCloudflareOfficialIps(controller.signal)
    if (controller.signal.aborted) return
    ipv4Cidrs.value = result.ipv4
    ipv6Cidrs.value = result.ipv6
    source.value = result.source
  } catch (cause) {
    const parsed = cloudflareError(cause)
    if (controller.signal.aborted || parsed.key === 'cancelled') return
  } finally {
    if (activeController === controller) {
      activeController = null
      loading.value = false
    }
  }
}

async function copyPayload(key: string, payload: string, successText: string): Promise<void> {
  if (!payload) return
  const ok = await copyCredentialText(payload)
  if (!ok) {
    ElMessage.error(t('cloudflareDns.officialIps.copyFailed'))
    return
  }
  setCopiedState(key)
  ElMessage.success(successText)
}

function copySingleCidr(cidr: string): void {
  void copyPayload(cidr, cidr, t('cloudflareDns.officialIps.copiedOne', { cidr }))
}

function copyAllCidrs(): void {
  const list = filteredEntries.value.map(entry => entry.cidr)
  if (!list.length) return
  void copyPayload('__ALL__', list.join('\n'), t('cloudflareDns.officialIps.copiedAll', { count: list.length }))
}

function copyNginxConfig(): void {
  const list = filteredEntries.value.map(entry => entry.cidr)
  const config = formatCloudflareNginxRealIpConfig(list)
  if (!config) return
  void copyPayload('__NGINX__', config, t('cloudflareDns.officialIps.copiedNginx', { count: list.length }))
}

function handleVisibilityChange(open: boolean): void {
  if (!open) emit('close')
}

watch(() => props.visible, open => {
  if (open) {
    void syncOfficialIps()
  } else {
    cancelPending()
    resetCopyFeedback()
  }
}, { immediate: true })

onBeforeUnmount(() => {
  cancelPending()
  resetCopyFeedback()
})
</script>

<template>
  <el-drawer
    :model-value="visible"
    direction="rtl"
    :size="compact ? 'min(95vw, 480px)' : '680px'"
    class="cloudflare-ips-drawer cloudflare-official-ips-drawer"
    append-to-body
    destroy-on-close
    @update:model-value="handleVisibilityChange"
  >
    <template #header>
      <div class="cf-ips-header">
        <span class="cf-ips-header-icon" aria-hidden="true">
          <i class="i-mdi-cloud-outline" />
        </span>
        <div class="cf-ips-header-copy">
          <h2 class="cf-ips-header-title">{{ t('cloudflareDns.officialIps.title') }}</h2>
          <p class="cf-ips-header-subtitle">{{ t('cloudflareDns.officialIps.subtitle') }}</p>
        </div>
      </div>
    </template>

    <div class="cf-ips-body">
      <div class="cf-ips-controls">
        <div class="cf-ips-filter-row is-single">
          <el-input
            v-model="keyword"
            class="cf-ips-search"
            clearable
            :placeholder="t('cloudflareDns.officialIps.searchPlaceholder')"
          >
            <template #prefix>
              <i class="i-mdi-magnify" aria-hidden="true" />
            </template>
          </el-input>
        </div>

        <div class="cf-ips-bar-bottom">
          <div class="cf-ips-family-group" role="group" :aria-label="t('cloudflareDns.officialIps.title')">
            <button
              v-for="option in (['ALL', 'IPv4', 'IPv6'] as const)"
              :key="option"
              type="button"
              class="cf-ips-family-btn"
              :class="{ 'is-active': familyFilter === option }"
              :aria-pressed="familyFilter === option"
              @click="familyFilter = option"
            >
              {{ option === 'ALL' ? t('cloudflareDns.officialIps.allFamilies') : option }}
            </button>
          </div>
          <span class="cf-ips-summary">{{ summaryText }}</span>
          <span class="cf-ips-source-pill" :class="{ 'is-live': source === 'live' }">
            <i :class="source === 'live' ? 'i-mdi-cloud-check-outline' : 'i-mdi-database-outline'" aria-hidden="true" />
            {{ source === 'live' ? t('cloudflareDns.officialIps.sourceLive') : t('cloudflareDns.officialIps.sourceBuiltin') }}
          </span>
          <GhostBtn class="cf-ips-refresh-btn" :loading="loading" @click="syncOfficialIps">
            <i class="i-mdi-refresh" aria-hidden="true" />{{ t('cloudflareDns.officialIps.refresh') }}
          </GhostBtn>
        </div>
      </div>

      <div v-if="!filteredEntries.length" class="cf-ips-state">
        <i class="i-mdi-filter-off-outline" aria-hidden="true" />
        <p>{{ t('cloudflareDns.officialIps.noMatches') }}</p>
      </div>

      <ul v-else class="cf-ips-cidr-grid" :aria-busy="loading">
        <li v-for="entry in filteredEntries" :key="entry.cidr" class="cf-ips-item is-compact">
          <div class="cf-ips-item-top">
            <div class="cf-ips-address-wrap">
              <span class="cf-ips-family-pill" :class="entry.family === 'IPv6' ? 'is-ipv6' : 'is-ipv4'">
                {{ entry.family }}
              </span>
              <code class="cf-ips-address">{{ entry.cidr }}</code>
            </div>
            <button
              type="button"
              class="cf-ips-copy-btn"
              :class="{ 'is-copied': copiedKey === entry.cidr }"
              @click="copySingleCidr(entry.cidr)"
            >
              <i :class="copiedKey === entry.cidr ? 'i-mdi-check' : 'i-mdi-content-copy'" aria-hidden="true" />
              <span>{{ copiedKey === entry.cidr ? t('cloudflareDns.officialIps.copyDone') : t('cloudflareDns.officialIps.copyCidr') }}</span>
            </button>
          </div>
        </li>
      </ul>
    </div>

    <template #footer>
      <div class="cf-ips-footer">
        <GhostBtn @click="emit('close')">{{ t('cloudflareDns.close') }}</GhostBtn>
        <GhostBtn
          :disabled="!filteredEntries.length"
          @click="copyNginxConfig"
        >
          <i :class="copiedKey === '__NGINX__' ? 'i-mdi-check' : 'i-mdi-file-code-outline'" aria-hidden="true" />
          {{ t('cloudflareDns.officialIps.copyNginx') }}
        </GhostBtn>
        <PrimaryBtn
          :disabled="!filteredEntries.length"
          @click="copyAllCidrs"
        >
          <i :class="copiedKey === '__ALL__' ? 'i-mdi-check' : 'i-mdi-content-copy'" aria-hidden="true" />
          {{ t('cloudflareDns.officialIps.copyAll', { count: filteredEntries.length }) }}
        </PrimaryBtn>
      </div>
    </template>
  </el-drawer>
</template>

<style src="./cloudflare-ips-drawer.css" scoped></style>
