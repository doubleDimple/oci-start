<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import { MENU, type NavItem } from '@/nav/menu'
import { useShellStore } from '@/stores/shell'

const { t } = useI18n()
const router = useRouter()
const shell = useShellStore()
const root = ref<HTMLElement>()
const input = ref<HTMLInputElement>()
const expanded = ref(false)
const active = ref(0)
const results = computed(() => {
  const query = shell.menuQuery.trim().toLowerCase()
  if (!query) return []
  return MENU.flatMap(group => group.children
    .filter(item => (!item.cloudTypes || item.cloudTypes.includes(shell.cloudType)) &&
      `${t(item.labelKey)} ${t(group.labelKey)} ${item.href}`.toLowerCase().includes(query))
    .map(item => ({ ...item, group: t(group.labelKey) })))
})
const showResults = computed(() => expanded.value && !!shell.menuQuery.trim())

watch(results, () => { active.value = 0 })
watch(() => router.currentRoute.value.fullPath, () => { expanded.value = false })

function clear() {
  shell.menuQuery = ''
  input.value?.focus()
}

function open(item: NavItem) {
  expanded.value = false
  shell.menuQuery = ''
  input.value?.blur()
  if (item.newTab) window.open(router.resolve(item.href).href, '_blank', 'noopener')
  else void router.push(item.href)
}

async function onKey(event: KeyboardEvent) {
  if (event.isComposing) return
  if (event.key === 'Escape') {
    event.stopPropagation()
    expanded.value = false
    shell.menuQuery = ''
  } else if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
    event.preventDefault()
    expanded.value = true
    if (!results.value.length) return
    const step = event.key === 'ArrowDown' ? 1 : -1
    active.value = (active.value + step + results.value.length) % results.value.length
    await nextTick()
    root.value?.querySelector('[aria-selected="true"]')?.scrollIntoView({ block: 'nearest' })
  } else if (event.key === 'Enter' && results.value[active.value]) {
    event.preventDefault()
    open(results.value[active.value]!)
  }
}

function shortcut(event: KeyboardEvent) {
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k' && !event.altKey) {
    // Keep focus inside an open dialog or mobile navigation.
    const openDialog = Array.from(document.querySelectorAll('.el-overlay-dialog, .el-overlay-message-box')).some(element => element.getClientRects().length > 0)
    if (openDialog || input.value?.closest('[inert]')) return
    event.preventDefault()
    input.value?.focus()
  }
}
function outside(event: PointerEvent) {
  if (!root.value?.contains(event.target as Node)) expanded.value = false
}
function focusOut(event: FocusEvent) {
  if (!root.value?.contains(event.relatedTarget as Node)) expanded.value = false
}
onMounted(() => {
  window.addEventListener('keydown', shortcut)
  document.addEventListener('pointerdown', outside)
})
onBeforeUnmount(() => {
  window.removeEventListener('keydown', shortcut)
  document.removeEventListener('pointerdown', outside)
  shell.menuQuery = ''
})
</script>

<template>
  <div ref="root" class="header-search" @focusout="focusOut">
    <div class="search-field">
      <i class="i-mdi-magnify" aria-hidden="true" />
      <input ref="input" v-model="shell.menuQuery" type="search" autocomplete="off"
        :placeholder="t('searchMenu')" :aria-label="t('header.search')" role="combobox"
        :aria-expanded="showResults" aria-controls="header-search-results" aria-autocomplete="list"
        :aria-activedescendant="showResults && results.length ? `header-result-${active}` : undefined"
        @focus="expanded = true" @input="expanded = true" @keydown="onKey" />
      <button v-if="shell.menuQuery" type="button" class="clear-search" :aria-label="t('header.clearSearch')" :title="t('header.clearSearch')" @click="clear">
        <i class="i-mdi-close" aria-hidden="true" />
      </button>
      <kbd v-else aria-hidden="true">⌘ / Ctrl K</kbd>
    </div>
    <Transition name="search-results">
      <div v-if="showResults" class="results-panel">
        <p class="result-count" role="status">{{ t('header.searchCount', { count: results.length }) }}</p>
        <ul id="header-search-results" role="listbox" :aria-label="t('header.searchResults')">
          <li v-for="(item, index) in results" :id="`header-result-${index}`" :key="item.id" role="option" :aria-selected="active === index"
            @pointermove="active = index" @mousedown.prevent @click="open(item)">
            <i :class="item.icon" aria-hidden="true" />
            <span>{{ t(item.labelKey) }}<small>{{ item.group }}</small></span>
            <i v-if="item.newTab" class="i-mdi-open-in-new" role="img" :aria-label="t('header.newTab')" />
            <i v-else class="i-mdi-arrow-top-left" aria-hidden="true" />
          </li>
        </ul>
        <p v-if="!results.length" class="no-results">{{ t('noMenu') }}</p>
        <p v-else class="result-hint">{{ t('header.searchHint') }}</p>
      </div>
    </Transition>
  </div>
</template>

<style scoped>
.header-search { flex: 1; max-width: 520px; min-width: 0; position: relative; font: var(--font-size-body)/1.47 var(--sans); }
.search-field { display: flex; align-items: center; gap: 8px; background: var(--bg-search); border: 1px solid transparent; border-radius: var(--r-pill); padding: 0 12px; height: 38px; color: var(--text-muted); transition: border-color 160ms ease, box-shadow 160ms ease; }
.search-field:focus-within { border-color: var(--brand); box-shadow: 0 0 0 3px color-mix(in srgb, var(--brand) 10%, transparent); }
.search-field > i { font-size: 18px; flex-shrink: 0; }
input { border: 0; outline: 0; background: transparent; width: 100%; min-width: 0; font: inherit; color: var(--text-primary); }
input::-webkit-search-cancel-button { display: none; }
kbd { flex-shrink: 0; font: var(--font-size-caption)/1 var(--sans); white-space: nowrap; }
.clear-search { border: 0; border-radius: 50%; display: grid; place-items: center; width: 26px; height: 26px; flex-shrink: 0; background: transparent; color: var(--text-secondary); cursor: pointer; }
.clear-search:hover { background: var(--bg-hover); }
.clear-search:focus-visible { outline: 2px solid var(--brand); outline-offset: 1px; }
.results-panel { position: absolute; top: calc(100% + 8px); left: 0; width: max(100%, 280px); max-width: calc(100vw - 96px); z-index: 100; background: var(--bg-card); border: 1px solid var(--border); border-radius: 16px; box-shadow: var(--shadow-card); overflow: hidden; }
.result-count, .result-hint, .no-results { margin: 0; padding: 10px 14px; color: var(--text-secondary); font-size: var(--font-size-secondary); }
.result-hint { border-top: 1px solid var(--border); }
ul { list-style: none; margin: 0; padding: 0 6px 6px; max-height: min(380px, 50dvh); overflow: auto; overscroll-behavior: contain; }
li { display: flex; align-items: center; gap: 10px; padding: 9px 10px; border-radius: 10px; color: var(--text-primary); cursor: pointer; }
li[aria-selected="true"] { background: var(--bg-hover); }
li > i:first-child { font-size: 18px; color: var(--brand); flex-shrink: 0; }
li > span { flex: 1; min-width: 0; }
li small { display: block; font-size: var(--font-size-secondary); color: var(--text-secondary); }
li > i:last-child { color: var(--text-muted); flex-shrink: 0; }
.search-results-enter-active, .search-results-leave-active { transition: opacity 140ms ease, transform 180ms cubic-bezier(.22,1,.36,1); }
.search-results-enter-from, .search-results-leave-to { opacity: 0; transform: translateY(-4px); }
@media (max-width: 960px) { kbd { display: none; } }
@media (max-width: 560px) { .header-search { order: 2; flex-basis: 100%; max-width: none; } }
@media (prefers-reduced-motion: reduce) { .search-field, .search-results-enter-active, .search-results-leave-active { transition: none; } }
</style>
