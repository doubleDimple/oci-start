<script setup lang="ts">
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { ElMessage } from 'element-plus'
import PageBackButton from '@/components/PageBackButton.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import { copyCredentialText } from '@/utils/initialCredentials'
import {
  OPEN_API_ENDPOINTS,
  OPEN_API_GROUPS,
  buildCurlCommand,
  downloadOpenApiJson,
  resolveRequestUrl,
  type OpenApiEndpoint,
  type OpenApiLocale,
} from './api-tokens/openApiSpec'
import { sessionPlainToken, setSessionPlainToken } from './api-tokens/sessionTokenBridge'
import './api-tokens/api-docs.scss'

const { t, locale } = useI18n()
const router = useRouter()

const lang = computed<OpenApiLocale>(() => (locale.value.startsWith('en') ? 'en' : 'zh'))
const keyword = ref('')
const selectedId = ref(OPEN_API_ENDPOINTS[0].id)
const tokenVisible = ref(false)
const bearerToken = ref(sessionPlainToken.value)
const queryValues = reactive<Record<string, string>>({})
const headerValues = reactive<Record<string, string>>({})
const bodyText = ref('')
const responseMode = ref<'live' | 'example'>('live')
const sending = ref(false)
const liveStatus = ref<number | null>(null)
const liveDurationMs = ref<number | null>(null)
const liveResponseText = ref('')
const liveContentType = ref('')
let requestAbort: AbortController | null = null

const filteredGroups = computed(() => {
  const q = keyword.value.trim().toLowerCase()
  const groups: Array<{ key: 'ai' | 'storage'; title: string; items: OpenApiEndpoint[] }> = [
    { key: 'ai', title: OPEN_API_GROUPS.ai[lang.value], items: [] },
    { key: 'storage', title: OPEN_API_GROUPS.storage[lang.value], items: [] },
  ]
  for (const endpoint of OPEN_API_ENDPOINTS) {
    if (q) {
      const hay = [
        endpoint.path,
        endpoint.method,
        endpoint.summary.zh,
        endpoint.summary.en,
        endpoint.description.zh,
        endpoint.description.en,
      ].join(' ').toLowerCase()
      if (!hay.includes(q)) continue
    }
    const target = groups.find(g => g.key === endpoint.group)
    target?.items.push(endpoint)
  }
  return groups.filter(g => g.items.length > 0)
})

const selectedEndpoint = computed(
  () => OPEN_API_ENDPOINTS.find(item => item.id === selectedId.value) ?? OPEN_API_ENDPOINTS[0],
)

const origin = computed(() => (typeof window !== 'undefined' ? window.location.origin : ''))

const curlPreview = computed(() =>
  buildCurlCommand({
    origin: origin.value,
    endpoint: selectedEndpoint.value,
    token: bearerToken.value,
    queryValues,
    headerValues,
    bodyText: bodyText.value,
  }),
)

function resetEndpointInputs(endpoint: OpenApiEndpoint) {
  Object.keys(queryValues).forEach(k => delete queryValues[k])
  Object.keys(headerValues).forEach(k => delete headerValues[k])
  for (const param of endpoint.parameters) {
    if (param.in === 'query') queryValues[param.name] = param.defaultValue
    else headerValues[param.name] = param.defaultValue
  }
  bodyText.value = endpoint.defaultBody ? JSON.stringify(endpoint.defaultBody, null, 2) : ''
  liveStatus.value = null
  liveDurationMs.value = null
  liveResponseText.value = ''
  liveContentType.value = ''
}

watch(selectedEndpoint, endpoint => {
  requestAbort?.abort()
  resetEndpointInputs(endpoint)
  responseMode.value = 'example'
}, { immediate: true })

watch(bearerToken, value => {
  setSessionPlainToken(value)
})

function back() {
  if (typeof window !== 'undefined' && window.history.length > 1) {
    router.back()
    return
  }
  void router.push('/system/apiTokens')
}

function goTokenSettings() {
  void router.push('/system/apiTokens')
}

function handleExportSpec() {
  downloadOpenApiJson(origin.value)
  ElMessage.success(t('apiTokens.exportedOpenApi'))
}

async function copyText(text: string) {
  const ok = await copyCredentialText(text)
  if (ok) ElMessage.success(t('apiTokens.copied'))
  else ElMessage.error(t('apiTokens.copyFailed'))
}

async function sendTestRequest() {
  const endpoint = selectedEndpoint.value
  const token = bearerToken.value.trim()
  if (!token) {
    ElMessage.warning(t('apiTokens.docs.tokenRequired'))
    return
  }
  for (const param of endpoint.parameters) {
    if (param.in === 'query' && param.required && !(queryValues[param.name] ?? '').trim()) {
      ElMessage.warning(t('apiTokens.docs.paramRequired', { name: param.name }))
      return
    }
  }

  let parsedBody: string | undefined
  if (endpoint.method === 'POST') {
    try {
      const obj = JSON.parse(bodyText.value || '{}')
      parsedBody = JSON.stringify(obj)
    } catch {
      ElMessage.error(t('apiTokens.docs.invalidJson'))
      return
    }
  }

  requestAbort?.abort()
  const controller = new AbortController()
  requestAbort = controller
  sending.value = true
  responseMode.value = 'live'
  liveStatus.value = null
  liveDurationMs.value = null
  liveResponseText.value = ''
  liveContentType.value = ''

  const headers: Record<string, string> = {
    Authorization: `Bearer ${token}`,
  }
  for (const param of endpoint.parameters) {
    if (param.in !== 'header') continue
    const val = (headerValues[param.name] ?? '').trim()
    if (val) headers[param.name] = val
  }
  if (endpoint.method === 'POST') headers['Content-Type'] = 'application/json'

  const targetUrl = resolveRequestUrl('', endpoint, queryValues)
  const startedAt = performance.now()
  try {
    const res = await fetch(targetUrl, {
      method: endpoint.method,
      headers,
      body: parsedBody,
      signal: controller.signal,
    })
    liveStatus.value = res.status
    liveContentType.value = res.headers.get('content-type') || ''

    if (liveContentType.value.includes('text/event-stream') && res.body) {
      const reader = res.body.getReader()
      const decoder = new TextDecoder()
      while (true) {
        const { done, value } = await reader.read()
        if (done) break
        liveResponseText.value += decoder.decode(value, { stream: true })
      }
      liveResponseText.value += decoder.decode()
    } else {
      const rawText = await res.text()
      try {
        liveResponseText.value = JSON.stringify(JSON.parse(rawText), null, 2)
      } catch {
        liveResponseText.value = rawText
      }
    }
  } catch (cause: any) {
    if (cause?.name === 'AbortError') return
    liveStatus.value = 0
    liveResponseText.value = String(cause?.message || t('apiTokens.errors.requestFailed'))
  } finally {
    liveDurationMs.value = Math.round(performance.now() - startedAt)
    if (requestAbort === controller) sending.value = false
  }
}

onBeforeUnmount(() => {
  requestAbort?.abort()
})
</script>

<template>
  <section class="api-docs-page">
    <header class="api-docs-toolbar">
      <div class="api-docs-toolbar-lead">
        <PageBackButton @click="back" />
        <span class="api-docs-auth-badge">
          <i class="i-mdi-shield-lock-outline" aria-hidden="true" />
          {{ t('apiTokens.docs.protectedBadge', { count: OPEN_API_ENDPOINTS.length }) }}
        </span>
        <div class="api-docs-token-field">
          <i class="i-mdi-key-outline" aria-hidden="true" />
          <input
            v-model="bearerToken"
            :type="tokenVisible ? 'text' : 'password'"
            :placeholder="t('apiTokens.docs.tokenPlaceholder')"
            :aria-label="t('apiTokens.docs.tokenLabel')"
            autocomplete="off"
          />
          <button
            type="button"
            class="api-docs-icon-btn"
            :title="t(tokenVisible ? 'apiTokens.hide' : 'apiTokens.reveal')"
            :aria-label="t(tokenVisible ? 'apiTokens.hide' : 'apiTokens.reveal')"
            @click="tokenVisible = !tokenVisible"
          >
            <i :class="tokenVisible ? 'i-mdi-eye-off-outline' : 'i-mdi-eye-outline'" aria-hidden="true" />
          </button>
          <button
            v-if="bearerToken"
            type="button"
            class="api-docs-icon-btn"
            :title="t('apiTokens.docs.clearToken')"
            :aria-label="t('apiTokens.docs.clearToken')"
            @click="bearerToken = ''"
          >
            <i class="i-mdi-close" aria-hidden="true" />
          </button>
        </div>
      </div>

      <div class="api-docs-toolbar-actions">
        <GhostBtn @click="goTokenSettings">
          <i class="i-mdi-key-chain-variant" aria-hidden="true" />
          {{ t('apiTokens.docs.manageToken') }}
        </GhostBtn>
        <GhostBtn @click="handleExportSpec">
          <i class="i-mdi-code-json" aria-hidden="true" />
          {{ t('apiTokens.schema') }}
        </GhostBtn>
      </div>
    </header>

    <div class="api-docs-shell">
      <aside class="api-docs-sidebar" :aria-label="t('apiTokens.docs.directoryLabel')">
        <div class="api-docs-sidebar-head">
          <div class="api-docs-search">
            <i class="i-mdi-magnify" aria-hidden="true" />
            <input
              v-model="keyword"
              :placeholder="t('apiTokens.docs.searchPlaceholder')"
              :aria-label="t('apiTokens.docs.searchPlaceholder')"
              autocomplete="off"
              @keydown.esc.prevent="keyword = ''"
            />
          </div>
        </div>
        <div class="api-docs-nav-scroll">
          <div v-if="!filteredGroups.length" class="api-docs-empty">
            {{ t('apiTokens.docs.noMatch') }}
          </div>
          <div v-for="group in filteredGroups" :key="group.key">
            <h2 class="api-docs-group-title">{{ group.title }}</h2>
            <div class="api-docs-nav-list">
              <button
                v-for="item in group.items"
                :key="item.id"
                type="button"
                class="api-docs-nav-item"
                :class="{ 'is-active': item.id === selectedEndpoint.id }"
                @click="selectedId = item.id"
              >
                <div class="api-docs-nav-top">
                  <strong>{{ item.summary[lang] }}</strong>
                  <span class="api-method-badge" :class="`is-${item.method.toLowerCase()}`">{{ item.method }}</span>
                </div>
                <span class="api-docs-nav-path">{{ item.path }}</span>
              </button>
            </div>
          </div>
        </div>
      </aside>

      <main class="api-docs-detail">
        <div class="api-docs-detail-scroll">
          <header class="api-docs-endpoint-head">
            <h1>{{ selectedEndpoint.summary[lang] }}</h1>
            <div class="api-docs-endpoint-url-row">
              <span class="api-method-badge" :class="`is-${selectedEndpoint.method.toLowerCase()}`">{{ selectedEndpoint.method }}</span>
              <code>{{ selectedEndpoint.path }}</code>
              <GhostBtn @click="copyText(selectedEndpoint.path)">
                <i class="i-mdi-content-copy" aria-hidden="true" />
                {{ t('apiTokens.docs.copyPath') }}
              </GhostBtn>
            </div>
            <p>{{ selectedEndpoint.description[lang] }}</p>
          </header>

          <section v-if="selectedEndpoint.parameters.length" class="api-docs-section">
            <div class="api-docs-section-head">
              <h2>{{ t('apiTokens.docs.paramsTitle') }}</h2>
            </div>
            <table class="api-docs-schema-table">
              <thead>
                <tr>
                  <th>{{ t('apiTokens.docs.colName') }}</th>
                  <th>{{ t('apiTokens.docs.colIn') }}</th>
                  <th>{{ t('apiTokens.docs.colType') }}</th>
                  <th>{{ t('apiTokens.docs.colRequired') }}</th>
                  <th>{{ t('apiTokens.docs.colDesc') }}</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="param in selectedEndpoint.parameters" :key="param.name">
                  <td><code>{{ param.name }}</code></td>
                  <td><code>{{ param.in }}</code></td>
                  <td><code>{{ param.type }}</code></td>
                  <td>
                    <span class="api-docs-req-tag" :class="param.required ? 'is-required' : 'is-optional'">
                      {{ t(param.required ? 'apiTokens.docs.required' : 'apiTokens.docs.optional') }}
                    </span>
                  </td>
                  <td>{{ param.description[lang] }}</td>
                </tr>
              </tbody>
            </table>

            <div class="api-docs-param-inputs">
              <div v-for="param in selectedEndpoint.parameters" :key="`input-${param.name}`" class="api-docs-input-field">
                <label :for="`param-${param.name}`">
                  {{ param.name }}
                  <span>{{ param.in }} · {{ param.type }}</span>
                </label>
                <input
                  v-if="param.in === 'query'"
                  :id="`param-${param.name}`"
                  v-model="queryValues[param.name]"
                  :placeholder="param.defaultValue || param.description[lang]"
                />
                <input
                  v-else
                  :id="`param-${param.name}`"
                  v-model="headerValues[param.name]"
                  :placeholder="param.defaultValue || param.description[lang]"
                />
              </div>
            </div>
          </section>

          <section v-if="selectedEndpoint.method === 'POST'" class="api-docs-section">
            <div class="api-docs-section-head">
              <h2>{{ t('apiTokens.docs.bodyTitle') }}</h2>
              <GhostBtn @click="resetEndpointInputs(selectedEndpoint)">
                <i class="i-mdi-restore" aria-hidden="true" />
                {{ t('apiTokens.docs.resetExample') }}
              </GhostBtn>
            </div>
            <table class="api-docs-schema-table">
              <thead>
                <tr>
                  <th>{{ t('apiTokens.docs.colName') }}</th>
                  <th>{{ t('apiTokens.docs.colType') }}</th>
                  <th>{{ t('apiTokens.docs.colRequired') }}</th>
                  <th>{{ t('apiTokens.docs.colDesc') }}</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="field in selectedEndpoint.bodyFields" :key="field.name">
                  <td><code>{{ field.name }}</code></td>
                  <td><code>{{ field.type }}</code></td>
                  <td>
                    <span class="api-docs-req-tag" :class="field.required ? 'is-required' : 'is-optional'">
                      {{ t(field.required ? 'apiTokens.docs.required' : 'apiTokens.docs.optional') }}
                    </span>
                  </td>
                  <td>{{ field.description[lang] }}</td>
                </tr>
              </tbody>
            </table>
            <textarea
              v-model="bodyText"
              class="api-docs-body-editor"
              spellcheck="false"
              :aria-label="t('apiTokens.docs.bodyTitle')"
            />
          </section>

          <section class="api-docs-section">
            <div class="api-docs-play-bar">
              <div class="api-docs-play-actions">
                <PrimaryBtn :loading="sending" @click="sendTestRequest">
                  <i class="i-mdi-play-outline" aria-hidden="true" />
                  {{ t('apiTokens.docs.sendRequest') }}
                </PrimaryBtn>
                <GhostBtn @click="copyText(curlPreview)">
                  <i class="i-mdi-console-line" aria-hidden="true" />
                  {{ t('apiTokens.docs.copyCurl') }}
                </GhostBtn>
              </div>
              <div v-if="liveStatus !== null" class="api-docs-response-meta">
                <span class="api-docs-status-pill" :class="liveStatus >= 200 && liveStatus < 300 ? 'is-ok' : 'is-err'">
                  HTTP {{ liveStatus || 'ERR' }}
                </span>
                <span v-if="liveDurationMs !== null">{{ liveDurationMs }} ms</span>
                <span v-if="liveContentType">{{ liveContentType }}</span>
              </div>
            </div>
          </section>

          <section class="api-docs-section">
            <div class="api-docs-section-head">
              <h2>{{ t('apiTokens.docs.responseTitle') }}</h2>
              <div class="api-docs-tabs" role="tablist">
                <button
                  type="button"
                  role="tab"
                  :class="{ 'is-active': responseMode === 'live' }"
                  :aria-selected="responseMode === 'live'"
                  @click="responseMode = 'live'"
                >
                  {{ t('apiTokens.docs.liveTab') }}
                </button>
                <button
                  type="button"
                  role="tab"
                  :class="{ 'is-active': responseMode === 'example' }"
                  :aria-selected="responseMode === 'example'"
                  @click="responseMode = 'example'"
                >
                  {{ t('apiTokens.docs.exampleTab') }}
                </button>
              </div>
            </div>

            <pre v-if="responseMode === 'live'" class="api-docs-code-panel">{{ liveResponseText || t('apiTokens.docs.livePlaceholder') }}</pre>
            <template v-else>
              <pre class="api-docs-code-panel">{{ selectedEndpoint.responseExample }}</pre>
              <template v-if="selectedEndpoint.streamExample">
                <div class="api-docs-section-head">
                  <h2>{{ t('apiTokens.docs.streamExampleTitle') }}</h2>
                </div>
                <pre class="api-docs-code-panel">{{ selectedEndpoint.streamExample }}</pre>
              </template>
            </template>
          </section>

          <section class="api-docs-section">
            <div class="api-docs-section-head">
              <h2>{{ t('apiTokens.docs.curlTitle') }}</h2>
              <GhostBtn @click="copyText(curlPreview)">
                <i class="i-mdi-content-copy" aria-hidden="true" />
                {{ t('apiTokens.docs.copyCurl') }}
              </GhostBtn>
            </div>
            <pre class="api-docs-code-panel">{{ curlPreview }}</pre>
          </section>
        </div>
      </main>
    </div>
  </section>
</template>
