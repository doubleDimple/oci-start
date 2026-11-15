<script setup lang="ts">
import { ElMessage } from 'element-plus'
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import GhostBtn from '@/components/GhostBtn.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import {
  cloudflareError, fetchCloudflareAllPublicIps,
  type CloudflareApiError, type CloudflareIpFamily, type CloudflarePublicIpGroup,
} from '@/api/cloudflare'
import { useCompactViewport } from '@/composables/useCompactViewport'
import { copyCredentialText } from '@/utils/initialCredentials'

const props = defineProps<{ visible: boolean }>()
const emit = defineEmits<{ close: [] }>()

const { t, locale } = useI18n()
const compact = useCompactViewport()

const loading = ref(false)
const loaded = ref(false)
const problem = ref<CloudflareApiError | null>(null)
const groups = ref<CloudflarePublicIpGroup[]>([])
const zones = ref<string[]>([])
const totalRecords = ref(0)

const keyword = ref('')
const familyFilter = ref<'ALL' | CloudflareIpFamily>('ALL')
const zoneFilter = ref('')
const copiedKey = ref('')

let activeController: AbortController | null = null
let copyResetTimer: ReturnType<typeof setTimeout> | null = null

const numberFormat = computed(() => new Intl.NumberFormat(locale.value === 'en' ? 'en-US' : 'zh-CN'))
function formatCount(value: number): string {
  return numberFormat.value.format(value)
}

const filteredGroups = computed(() => {
  const query = keyword.value.trim().toLowerCase()
  const zone = zoneFilter.value
  const family = familyFilter.value
  return groups.value.filter(group => {
    if (family !== 'ALL' && group.family !== family) return false
    const matchingRecords = zone ? group.records.filter(r => r.zoneName === zone) : group.records
    if (!matchingRecords.length) return false
    if (!query) return true
    if (group.ip.toLowerCase().includes(query)) return true
    return matchingRecords.some(r =>
      r.zoneName.toLowerCase().includes(query) || r.name.toLowerCase().includes(query),
    )
  })
})

const filteredRecordCount = computed(() => {
  const zone = zoneFilter.value
  return filteredGroups.value.reduce((sum, group) => {
    return sum + (zone ? group.records.filter(r => r.zoneName === zone).length : group.records.length)
  }, 0)
})

const visibleZones = computed(() => {
  const activeZones = new Set<string>()
  for (const group of filteredGroups.value) {
    for (const record of group.records) {
      if (!zoneFilter.value || record.zoneName === zoneFilter.value) {
        activeZones.add(record.zoneName)
      }
    }
  }
  return activeZones.size
})

const summaryText = computed(() => t('cloudflareDns.publicIps.summary', {
  ips: formatCount(filteredGroups.value.length),
  records: formatCount(filteredRecordCount.value),
  zones: formatCount(visibleZones.value),
}))

const problemMessage = computed(() => {
  if (!problem.value) return ''
  return problem.value.detail || t(`cloudflareDns.errors.${problem.value.key}`)
})

function visibleRecordsFor(group: CloudflarePublicIpGroup) {
  return zoneFilter.value ? group.records.filter(r => r.zoneName === zoneFilter.value) : group.records
}

function recordDisplayName(name: string, zoneName: string): string {
  if (!name || name === zoneName) return `@ (${zoneName})`
  return name
}

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

async function loadPublicIps(): Promise<void> {
  cancelPending()
  const controller = new AbortController()
  activeController = controller
  loading.value = true
  problem.value = null
  try {
    const result = await fetchCloudflareAllPublicIps(controller.signal)
    if (controller.signal.aborted) return
    groups.value = result.groups
    zones.value = result.zones
    totalRecords.value = result.totalRecords
    loaded.value = true
    if (zoneFilter.value && !result.zones.includes(zoneFilter.value)) {
      zoneFilter.value = ''
    }
  } catch (cause) {
    const parsed = cloudflareError(cause)
    if (controller.signal.aborted || parsed.key === 'cancelled') return
    problem.value = parsed
  } finally {
    if (activeController === controller) {
      activeController = null
      loading.value = false
    }
  }
}

async function copySingleIp(ip: string): Promise<void> {
  const ok = await copyCredentialText(ip)
  if (!ok) {
    ElMessage.error(t('cloudflareDns.publicIps.copyFailed'))
    return
  }
  setCopiedState(ip)
  ElMessage.success(t('cloudflareDns.publicIps.copiedOne', { ip }))
}

async function copyAllIps(): Promise<void> {
  const list = filteredGroups.value.map(group => group.ip)
  if (!list.length) return
  const ok = await copyCredentialText(list.join('\n'))
  if (!ok) {
    ElMessage.error(t('cloudflareDns.publicIps.copyFailed'))
    return
  }
  setCopiedState('__ALL__')
  ElMessage.success(t('cloudflareDns.publicIps.copiedAll', { count: list.length }))
}

function handleVisibilityChange(open: boolean): void {
  if (!open) emit('close')
}

watch(() => props.visible, open => {
  if (open) {
    void loadPublicIps()
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
    :size="compact ? 'min(95vw, 480px)' : '600px'"
    class="cloudflare-ips-drawer"
    append-to-body
    destroy-on-close
    @update:model-value="handleVisibilityChange"
  >
    <template #header>
      <div class="cf-ips-header">
        <span class="cf-ips-header-icon" aria-hidden="true">
          <i class="i-mdi-ip-network-outline" />
        </span>
        <div class="cf-ips-header-copy">
          <h2 class="cf-ips-header-title">{{ t('cloudflareDns.publicIps.title') }}</h2>
          <p class="cf-ips-header-subtitle">{{ t('cloudflareDns.publicIps.subtitle') }}</p>
        </div>
      </div>
    </template>

    <div class="cf-ips-body">
      <div class="cf-ips-controls">
        <div class="cf-ips-filter-row">
          <el-input
            v-model="keyword"
            class="cf-ips-search"
            clearable
            :placeholder="t('cloudflareDns.publicIps.searchPlaceholder')"
          >
            <template #prefix>
              <i class="i-mdi-magnify" aria-hidden="true" />
            </template>
          </el-input>
          <el-select
            v-model="zoneFilter"
            class="cf-ips-zone-select"
            clearable
            :placeholder="t('cloudflareDns.publicIps.allZones')"
          >
            <el-option :label="t('cloudflareDns.publicIps.allZones')" value="" />
            <el-option v-for="zone in zones" :key="zone" :label="zone" :value="zone" />
          </el-select>
        </div>

        <div class="cf-ips-bar-bottom">
          <div class="cf-ips-family-group" role="group" :aria-label="t('cloudflareDns.publicIps.title')">
            <button
              v-for="option in (['ALL', 'IPv4', 'IPv6'] as const)"
              :key="option"
              type="button"
              class="cf-ips-family-btn"
              :class="{ 'is-active': familyFilter === option }"
              :aria-pressed="familyFilter === option"
              @click="familyFilter = option"
            >
              {{ option === 'ALL' ? t('cloudflareDns.publicIps.allFamilies') : option }}
            </button>
          </div>
          <span class="cf-ips-summary">{{ summaryText }}</span>
          <GhostBtn class="cf-ips-refresh-btn" :loading="loading" @click="loadPublicIps">
            <i class="i-mdi-refresh" aria-hidden="true" />{{ t('cloudflareDns.publicIps.refresh') }}
          </GhostBtn>
        </div>
      </div>

      <div v-if="problem" class="cf-ips-alert" role="alert">
        <i class="i-mdi-alert-circle-outline" aria-hidden="true" />
        <span>{{ problemMessage }}</span>
      </div>

      <div v-if="loading && !loaded" class="cf-ips-state">
        <i class="i-mdi-loading cf-ips-spin" aria-hidden="true" />
        <p>{{ t('cloudflareDns.publicIps.loading') }}</p>
      </div>

      <div v-else-if="loaded && !groups.length" class="cf-ips-state">
        <i class="i-mdi-ip-outline" aria-hidden="true" />
        <p>{{ t('cloudflareDns.publicIps.empty') }}</p>
      </div>

      <div v-else-if="loaded && !filteredGroups.length" class="cf-ips-state">
        <i class="i-mdi-filter-off-outline" aria-hidden="true" />
        <p>{{ t('cloudflareDns.publicIps.noMatches') }}</p>
      </div>

      <ul v-else class="cf-ips-list" :aria-busy="loading">
        <li v-for="group in filteredGroups" :key="group.ip" class="cf-ips-item">
          <div class="cf-ips-item-top">
            <div class="cf-ips-address-wrap">
              <span class="cf-ips-family-pill" :class="group.family === 'IPv6' ? 'is-ipv6' : 'is-ipv4'">
                {{ group.family }}
              </span>
              <code class="cf-ips-address">{{ group.ip }}</code>
            </div>
            <button
              type="button"
              class="cf-ips-copy-btn"
              :class="{ 'is-copied': copiedKey === group.ip }"
              @click="copySingleIp(group.ip)"
            >
              <i :class="copiedKey === group.ip ? 'i-mdi-check' : 'i-mdi-content-copy'" aria-hidden="true" />
              <span>{{ copiedKey === group.ip ? t('cloudflareDns.publicIps.copyDone') : t('cloudflareDns.publicIps.copyIp') }}</span>
            </button>
          </div>
          <div class="cf-ips-records">
            <span
              v-for="record in visibleRecordsFor(group)"
              :key="record.id"
              class="cf-ips-record-tag"
              :title="`${record.type} · ${record.name} (${record.zoneName})`"
            >
              <span
                class="cf-ips-proxy-dot"
                :class="record.proxied === true ? 'is-proxied' : record.proxied === false ? 'is-dns-only' : 'is-unknown'"
                :aria-label="record.proxied === true ? t('cloudflareDns.proxied') : record.proxied === false ? t('cloudflareDns.dnsOnly') : t('cloudflareDns.unknown')"
              />
              <span class="cf-ips-record-name">{{ recordDisplayName(record.name, record.zoneName) }}</span>
              <span class="cf-ips-record-zone" v-if="record.name && record.name !== record.zoneName">{{ record.zoneName }}</span>
            </span>
          </div>
        </li>
      </ul>
    </div>

    <template #footer>
      <div class="cf-ips-footer">
        <GhostBtn @click="emit('close')">{{ t('cloudflareDns.close') }}</GhostBtn>
        <PrimaryBtn
          :disabled="loading || !filteredGroups.length"
          @click="copyAllIps"
        >
          <i :class="copiedKey === '__ALL__' ? 'i-mdi-check' : 'i-mdi-content-copy'" aria-hidden="true" />
          {{ t('cloudflareDns.publicIps.copyAll', { count: filteredGroups.length }) }}
        </PrimaryBtn>
      </div>
    </template>
  </el-drawer>
</template>

<style src="./cloudflare-ips-drawer.css" scoped></style>
