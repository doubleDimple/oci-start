<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { MENU, type NavItem } from '@/nav/menu'
import { useShellStore } from '@/stores/shell'
import { useUserStore } from '@/stores/user'
import { theme, themeMode, setTheme } from '@/composables/useTheme'
import { chrome, setSidebarColor, setPageColor, resetChrome, SIDEBAR_SWATCHES, PAGE_SWATCHES } from '@/composables/useChrome'
import { useLocale } from '@/composables/useLocale'
import HeaderSearch from '@/components/header/HeaderSearch.vue'
import HeaderMessages from '@/components/header/HeaderMessages.vue'
import HeaderAssets from '@/components/header/HeaderAssets.vue'
import HeaderVersion from '@/components/header/HeaderVersion.vue'

const { t } = useI18n()
const route = useRoute()
const router = useRouter()
const shell = useShellStore()
const user = useUserStore()
const { locale, setLocale, syncing: localeSyncing } = useLocale()
const assets = ref<InstanceType<typeof HeaderAssets>>()
const version = ref<InstanceType<typeof HeaderVersion>>()
const userRequest = new AbortController()
let disposed = false
// Reset any hidden provider retained by an already mounted development session.
if (shell.cloudType !== 1) shell.setCloud(1)
const userLabel = computed(() => user.username || t(user.loading ? 'header.loading' : 'header.user'))
const languageLabel = computed(() => `${t('header.language')} · ${locale.value === 'zh' ? '简体中文' : 'English'}`)
const themeIcon = computed(() => themeMode.value === 'system' ? 'i-mdi-monitor' : theme.value === 'dark' ? 'i-mdi-weather-night' : 'i-mdi-white-balance-sunny')
const avatarUrl = '/images/default-avatar.png'
const compactMedia = window.matchMedia('(max-width: 760px)')
const compactViewport = ref(compactMedia.matches)
const mobileNavOpen = ref(false)
const sidebarToggle = ref<HTMLButtonElement | null>(null)
const content = ref<HTMLElement | null>(null)
const sidebarCollapsed = computed(() => compactViewport.value ? !mobileNavOpen.value : shell.collapsed)

function updateViewport(event: MediaQueryListEvent) {
  compactViewport.value = event.matches
  mobileNavOpen.value = false
}

function toggleSidebar() {
  if (compactViewport.value) mobileNavOpen.value = !mobileNavOpen.value
  else shell.toggleCollapsed()
}

function closeMobileNav() {
  if (!mobileNavOpen.value) return
  mobileNavOpen.value = false
  sidebarToggle.value?.focus()
}

onMounted(() => {
  void user.load(userRequest.signal)
  compactMedia.addEventListener('change', updateViewport)
})
onBeforeUnmount(() => {
  disposed = true
  userRequest.abort()
  compactMedia.removeEventListener('change', updateViewport)
})

watch(() => route.path, async () => {
  mobileNavOpen.value = false
  await nextTick()
  content.value?.scrollTo({ top: 0, left: 0 })
})

const visibleGroups = computed(() => {
  const q = shell.menuQuery.trim().toLowerCase()
  return MENU.map((g) => ({
    ...g,
    children: g.children.filter((it) => {
      if (it.cloudTypes && !it.cloudTypes.includes(shell.cloudType)) return false
      if (!q) return true
      return `${t(it.labelKey)} ${t(g.labelKey)} ${it.href}`.toLowerCase().includes(q)
    }),
  })).filter((g) => g.children.length > 0)
})

function openItem(it: NavItem, event: MouseEvent) {
  if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button !== 0) return
  event.preventDefault()
  mobileNavOpen.value = false
  shell.menuQuery = ''
  if (it.newTab) window.open(router.resolve(it.href).href, '_blank', 'noopener')
  else void router.push(it.href)
}

function changeTheme(value: unknown) {
  if (value === 'dark' || value === 'light' || value === 'system') setTheme(value)
}

async function changeLocale(value: unknown) {
  if (value !== 'zh' && value !== 'en') return
  const succeeded = await setLocale(value)
  if (!succeeded && !disposed) ElMessage.error(t('header.localeFailed'))
}

async function signOut() {
  if (user.signingOut) return
  const succeeded = await user.signOut()
  if (!succeeded && !disposed) ElMessage.error(t('header.logoutFailed'))
}

function userCommand(value: unknown) {
  if (value === 'assets') assets.value?.open()
  else if (value === 'about') version.value?.open()
  else if (value === 'logout') void signOut()
  else if (value === 'retry') void user.load(userRequest.signal)
}

function isActive(it: NavItem) {
  return route.path === it.href
}

</script>

<template>
  <div class="shell" :class="{ collapsed: sidebarCollapsed, 'mobile-nav-open': mobileNavOpen }" @keydown.esc="closeMobileNav">
    <Transition name="navigation-shade"><button v-if="compactViewport && mobileNavOpen" class="mobile-nav-backdrop" type="button" tabindex="-1" :aria-label="t('header.collapseNav')" @click="closeMobileNav" /></Transition>
    <aside class="side">
      <div class="brand">
        <button ref="sidebarToggle" class="leaf" type="button" :aria-label="t(sidebarCollapsed ? 'header.expandNav' : 'header.collapseNav')" :title="t(sidebarCollapsed ? 'header.expandNav' : 'header.collapseNav')" :aria-expanded="!sidebarCollapsed" aria-controls="primary-navigation" @click="toggleSidebar">
          <i :class="compactViewport ? (mobileNavOpen ? 'i-mdi-close' : 'i-mdi-menu') : 'i-mdi-leaf'" aria-hidden="true" />
        </button>
        <RouterLink to="/index" class="brand-text" :title="t('header.home')" :aria-label="t('header.home')" :tabindex="sidebarCollapsed ? -1 : undefined">
          <strong>{{ t('brand') }}</strong>
          <small>{{ t('brandSub') }}</small>
        </RouterLink>
      </div>

      <nav id="primary-navigation" class="nav" :aria-label="t('header.navigation')">
        <template v-for="g in visibleGroups" :key="g.id">
          <div class="group-label">{{ t(g.labelKey) }}</div>
          <a
            v-for="it in g.children"
            :key="it.id"
            :href="router.resolve(it.href).href"
            :target="it.newTab ? '_blank' : undefined"
            :rel="it.newTab ? 'noopener' : undefined"
            class="nav-item"
            :class="{ active: isActive(it) }"
            :title="t(it.labelKey)"
            :aria-label="t(it.labelKey)"
            :aria-current="isActive(it) ? 'page' : undefined"
            @click="openItem(it, $event)"
          >
            <i :class="it.icon" />
            <span>{{ t(it.labelKey) }}</span>
          </a>
        </template>
        <div v-if="visibleGroups.length === 0" class="empty">{{ t('noMenu') }}</div>
      </nav>

      <div class="quote">
        <p>{{ t('quote') }}</p>
      </div>

      <div class="side-user">
        <img :src="avatarUrl" alt="" />
        <div class="side-user-meta">
          <b>{{ userLabel }}</b>
          <small>{{ shell.cloudName }}</small>
        </div>
      </div>
    </aside>

    <div class="main" :inert="compactViewport && mobileNavOpen || undefined">
      <header class="top">
        <HeaderSearch />
        <div class="top-right">
          <HeaderVersion ref="version" />
          <el-dropdown trigger="click" @command="changeTheme">
            <button class="icon-btn" type="button" :title="`${t('header.appearance')} · ${t(`header.${themeMode}`)}`" :aria-label="`${t('header.appearance')} · ${t(`header.${themeMode}`)}`">
              <i :class="themeIcon" aria-hidden="true" />
            </button>
            <template #dropdown>
              <el-dropdown-menu>
                <el-dropdown-item v-for="mode in ['light', 'dark', 'system']" :key="mode" :command="mode" :class="{ 'is-active': themeMode === mode }">
                  <span class="header-menu-label">{{ t(`header.${mode}`) }}</span><i v-if="themeMode === mode" class="i-mdi-check" aria-hidden="true" />
                </el-dropdown-item>
              </el-dropdown-menu>
            </template>
          </el-dropdown>
          <el-popover placement="bottom-end" :width="280" trigger="click">
            <template #reference>
              <button class="icon-btn" type="button" :title="t('chrome.title')" :aria-label="t('chrome.title')">
                <i class="i-mdi-palette-outline" />
              </button>
            </template>
            <div class="chrome-pop">
              <p class="chrome-label">{{ t('chrome.sidebar') }}</p>
              <div class="swatches">
                <button
                  v-for="c in SIDEBAR_SWATCHES"
                  :key="'s' + c"
                  type="button"
                  class="swatch"
                  :class="{ on: chrome.sidebar.toLowerCase() === c }"
                  :style="{ background: c }"
                  :aria-label="t('header.sidebarColor', { color: c })"
                  :title="t('header.sidebarColor', { color: c })"
                  :aria-pressed="chrome.sidebar.toLowerCase() === c"
                  @click="setSidebarColor(c)"
                />
                <label class="swatch picker">
                  <input type="color" :aria-label="t('header.customSidebar')" :title="t('header.customSidebar')" :value="chrome.sidebar || (theme === 'dark' ? '#000000' : '#1d1d1f')" @input="setSidebarColor(($event.target as HTMLInputElement).value)">
                </label>
              </div>
              <p class="chrome-label">{{ t('chrome.page') }}</p>
              <div class="swatches">
                <button
                  v-for="c in PAGE_SWATCHES"
                  :key="'p' + c"
                  type="button"
                  class="swatch"
                  :class="{ on: chrome.page.toLowerCase() === c }"
                  :style="{ background: c }"
                  :aria-label="t('header.pageColor', { color: c })"
                  :title="t('header.pageColor', { color: c })"
                  :aria-pressed="chrome.page.toLowerCase() === c"
                  @click="setPageColor(c)"
                />
                <label class="swatch picker">
                  <input type="color" :aria-label="t('header.customPage')" :title="t('header.customPage')" :value="chrome.page || (theme === 'dark' ? '#000000' : '#f5f5f7')" @input="setPageColor(($event.target as HTMLInputElement).value)">
                </label>
              </div>
              <button class="reset" type="button" @click="resetChrome">{{ t('chrome.reset') }}</button>
            </div>
          </el-popover>
          <el-dropdown trigger="click" :disabled="localeSyncing" @command="changeLocale">
            <button class="icon-btn" type="button" :disabled="localeSyncing" :aria-busy="localeSyncing" :title="languageLabel" :aria-label="languageLabel">
              <i class="i-mdi-translate" aria-hidden="true" />
            </button>
            <template #dropdown>
              <el-dropdown-menu>
                <el-dropdown-item command="zh" :class="{ 'is-active': locale === 'zh' }"><span class="header-menu-label" lang="zh-CN">简体中文</span><i v-if="locale === 'zh'" class="i-mdi-check" aria-hidden="true" /></el-dropdown-item>
                <el-dropdown-item command="en" :class="{ 'is-active': locale === 'en' }"><span class="header-menu-label" lang="en">English</span><i v-if="locale === 'en'" class="i-mdi-check" aria-hidden="true" /></el-dropdown-item>
              </el-dropdown-menu>
            </template>
          </el-dropdown>
          <HeaderMessages />
          <el-dropdown trigger="click" @command="userCommand">
            <button class="user-chip" type="button" :title="t(user.loadFailed ? 'header.userFailed' : 'header.userMenu')" :aria-label="`${userLabel} · ${t('header.userMenu')}`">
              <img :src="avatarUrl" alt="" />
              <span>
                <b>{{ userLabel }}</b>
                <small>{{ shell.cloudName }}</small>
              </span>
              <i class="i-mdi-chevron-down" />
            </button>
            <template #dropdown>
              <el-dropdown-menu>
                <el-dropdown-item disabled><span class="header-account-summary">{{ userLabel }}<small>{{ shell.cloudName }}</small></span></el-dropdown-item>
                <el-dropdown-item v-if="user.loadFailed" command="retry" :disabled="user.loading"><i class="i-mdi-refresh" aria-hidden="true" />{{ t('header.retryUser') }}</el-dropdown-item>
                <el-dropdown-item divided command="assets"><i class="i-mdi-chart-box-outline" aria-hidden="true" />{{ t('header.assets') }}</el-dropdown-item>
                <el-dropdown-item command="about"><i class="i-mdi-information-outline" aria-hidden="true" />
                  {{ t('about') }}
                </el-dropdown-item>
                <el-dropdown-item divided command="logout" :disabled="user.signingOut"><i class="i-mdi-logout" aria-hidden="true" />{{ t(user.signingOut ? 'header.signOutBusy' : 'logout') }}</el-dropdown-item>
              </el-dropdown-menu>
            </template>
          </el-dropdown>
        </div>
      </header>

      <section ref="content" class="content">
        <RouterView v-slot="{ Component, route: currentRoute }">
          <Transition name="page-view" mode="out-in"><component :is="Component" :key="currentRoute.path" /></Transition>
        </RouterView>
      </section>
    </div>
    <HeaderAssets ref="assets" />
  </div>
</template>

<style scoped>
.shell {
  display: flex;
  height: 100%;
  background: var(--bg-page);
  position: relative;
  isolation: isolate;
}
.side {
  width: var(--side-width);
  flex-shrink: 0;
  background: var(--bg-sidebar);
  color: var(--text-on-dark);
  display: flex;
  flex-direction: column;
  padding: 22px 14px 16px;
  position: relative;
  overflow: hidden;
  transition: width 0.32s cubic-bezier(0.22, 1, 0.36, 1),
              padding 0.32s cubic-bezier(0.22, 1, 0.36, 1);
}
.collapsed .side {
  width: var(--side-collapsed);
  padding-inline: 10px;
}
.brand {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 0 8px 18px;
  overflow: hidden;
  transition: padding 0.32s cubic-bezier(0.22, 1, 0.36, 1),
              gap 0.32s cubic-bezier(0.22, 1, 0.36, 1);
}
.collapsed .brand {
  justify-content: center;
  padding-inline: 0;
  gap: 0;
}
.leaf {
  width: 34px;
  height: 34px;
  flex-shrink: 0;
  border: 0;
  border-radius: 10px;
  background: var(--brand);
  color: var(--nav-active-fg);
  display: grid;
  place-items: center;
  font-size: 18px;
  cursor: pointer;
  transition: transform 180ms cubic-bezier(.22, 1, .36, 1), background-color 180ms ease;
}
.leaf:hover { background: var(--brand-hover); }
.leaf:active { transform: scale(.94); }
.leaf:focus-visible { outline: 2px solid var(--text-on-dark); outline-offset: 3px; }
.brand-text {
  color: inherit;
  text-decoration: none;
  min-width: 0;
  max-width: 160px;
  overflow: hidden;
  white-space: nowrap;
  opacity: 1;
  transition: opacity 0.2s ease 0.06s, max-width 0.32s cubic-bezier(0.22, 1, 0.36, 1);
}
.brand-text:focus-visible { outline: 2px solid var(--brand); outline-offset: 2px; }
.collapsed .brand-text {
  opacity: 0;
  max-width: 0;
  pointer-events: none;
  transition: opacity 0.12s ease, max-width 0.32s cubic-bezier(0.22, 1, 0.36, 1);
}
.brand-text strong {
  display: block;
  font-size: var(--font-size-section);
  letter-spacing: 0.02em;
}
.brand-text small {
  color: var(--text-on-dark-muted);
  font-size: var(--font-size-secondary);
}
.nav {
  flex: 1;
  overflow-x: hidden;
  overflow-y: auto;
  padding-right: 4px;
}
.collapsed .nav { padding-right: 0; }
.group-label {
  margin: 14px 10px 6px;
  font-size: var(--font-size-caption);
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: var(--text-on-dark-muted);
  max-height: 32px;
  overflow: hidden;
  white-space: nowrap;
  opacity: 1;
  transition: opacity 0.16s ease, max-height 0.28s ease, margin 0.28s ease;
}
.collapsed .group-label {
  opacity: 0;
  max-height: 0;
  margin-top: 0;
  margin-bottom: 0;
}
.nav-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 9px 12px;
  margin-bottom: 4px;
  border-radius: 12px;
  color: var(--text-on-dark-muted);
  text-decoration: none;
  font-size: var(--font-size-body);
  font-weight: 500;
  overflow: hidden;
  white-space: nowrap;
  transition: padding 0.28s cubic-bezier(0.22, 1, 0.36, 1),
              gap 0.28s cubic-bezier(0.22, 1, 0.36, 1);
}
.nav-item i { font-size: 18px; flex-shrink: 0; }
.nav-item span {
  overflow: hidden;
  max-width: 160px;
  opacity: 1;
  transition: opacity 0.18s ease 0.05s, max-width 0.28s cubic-bezier(0.22, 1, 0.36, 1);
}
.collapsed .nav-item {
  justify-content: center;
  padding-inline: 10px;
  gap: 0;
}
.collapsed .nav-item span {
  opacity: 0;
  max-width: 0;
  transition: opacity 0.1s ease, max-width 0.28s cubic-bezier(0.22, 1, 0.36, 1);
}
.nav-item:hover { background: color-mix(in srgb, var(--text-on-dark) 8%, transparent); color: var(--text-on-dark); }
.nav-item:focus-visible { outline: 2px solid var(--text-on-dark); outline-offset: -2px; }
.nav-item.active {
  background: linear-gradient(90deg, var(--brand) 0%, var(--brand-deep) 140%);
  color: var(--nav-active-fg);
  box-shadow: 0 8px 18px rgba(27, 138, 106, 0.28);
}
.empty { color: var(--text-on-dark-muted); font-size: var(--font-size-secondary); padding: 12px; }
.quote {
  margin: 12px 8px;
  padding: 16px 14px;
  border-radius: 16px;
  background: color-mix(in srgb, var(--brand) 22%, transparent);
  color: var(--text-on-dark);
  font-size: var(--font-size-body);
  line-height: 1.45;
  font-weight: 600;
  overflow: hidden;
  max-height: 140px;
  opacity: 1;
  transition: opacity 0.18s ease,
              max-height 0.32s cubic-bezier(0.22, 1, 0.36, 1),
              margin 0.32s cubic-bezier(0.22, 1, 0.36, 1),
              padding 0.32s cubic-bezier(0.22, 1, 0.36, 1);
}
.collapsed .quote {
  opacity: 0;
  max-height: 0;
  margin: 0;
  padding-top: 0;
  padding-bottom: 0;
  pointer-events: none;
}
.side-user {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 8px 4px;
  border-top: 1px solid rgba(255,255,255,0.06);
  overflow: hidden;
  transition: padding 0.28s cubic-bezier(0.22, 1, 0.36, 1),
              gap 0.28s cubic-bezier(0.22, 1, 0.36, 1);
}
.collapsed .side-user {
  justify-content: center;
  gap: 0;
  padding-inline: 0;
}
.side-user img, .user-chip img {
  width: 34px; height: 34px; border-radius: 50%; object-fit: cover; background: #234;
  flex-shrink: 0;
}
.side-user-meta {
  min-width: 0;
  max-width: 160px;
  overflow: hidden;
  white-space: nowrap;
  opacity: 1;
  transition: opacity 0.18s ease 0.05s, max-width 0.28s cubic-bezier(0.22, 1, 0.36, 1);
}
.collapsed .side-user-meta {
  opacity: 0;
  max-width: 0;
  pointer-events: none;
  transition: opacity 0.1s ease, max-width 0.28s cubic-bezier(0.22, 1, 0.36, 1);
}
.side-user b, .user-chip b { display: block; font-size: var(--font-size-body); }
.side-user small, .user-chip small { color: var(--text-on-dark-muted); font-size: var(--font-size-secondary); }

@media (prefers-reduced-motion: reduce) {
  .side,
  .brand,
  .brand-text,
  .group-label,
  .nav-item,
  .nav-item span,
  .quote,
  .side-user,
  .side-user-meta {
    transition: none;
  }
}

.main {
  flex: 1;
  min-width: 0;
  background: var(--bg-page);
  display: flex;
  flex-direction: column;
  overflow: hidden;
}
.top {
  height: var(--topbar-h);
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 24px;
  gap: 16px;
  flex-shrink: 0;
}
.top-right { display: flex; align-items: center; gap: 8px; flex-shrink: 0; }
.icon-btn {
  width: 38px; height: 38px; border: 0; border-radius: 50%;
  background: var(--bg-card); color: var(--text-secondary);
  display: grid; place-items: center; cursor: pointer;
  box-shadow: var(--shadow-card);
  flex-shrink: 0;
  transition: transform 160ms cubic-bezier(.22, 1, .36, 1), background-color 160ms ease;
}
.icon-btn:hover { background: var(--bg-hover); }
.icon-btn:active { transform: scale(.94); }
.icon-btn:focus-visible, .user-chip:focus-visible { outline: 2px solid var(--brand); outline-offset: 3px; }
.icon-btn:disabled { cursor: wait; opacity: .55; }
.icon-btn > i { font-size: 18px; }
.user-chip {
  display: flex; align-items: center; gap: 8px;
  border: 0; background: var(--bg-card); border-radius: var(--r-pill);
  padding: 4px 10px 4px 4px; cursor: pointer;
  box-shadow: var(--shadow-card); color: var(--text-primary);
}
.user-chip span { text-align: left; line-height: 1.15; max-width: 160px; overflow: hidden; }
.user-chip b { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.user-chip small { color: var(--text-secondary); }
.content {
  flex: 1;
  min-height: 0;
  padding: 8px 24px 24px;
  overflow: auto;
  overscroll-behavior: contain;
}
.content :deep(.el-table) {
  --el-table-header-bg-color: transparent;
  --el-table-tr-bg-color: var(--bg-card);
  --el-table-row-hover-bg-color: var(--bg-hover);
  --el-table-text-color: var(--text-primary);
  --el-table-header-text-color: var(--text-secondary);
  --el-table-border-color: var(--border);
}
.mobile-nav-backdrop {
  position: absolute;
  inset: 0;
  z-index: 10;
  border: 0;
  padding: 0;
  background: var(--el-mask-color);
}
.navigation-shade-enter-active, .navigation-shade-leave-active { transition: opacity 180ms ease; }
.navigation-shade-enter-from, .navigation-shade-leave-to { opacity: 0; }
@media (max-width: 760px) {
  .side { position: absolute; inset: 0 auto 0 0; z-index: 20; width: min(260px, calc(100vw - 48px)); }
  .collapsed .side { width: 64px; padding-inline: 8px; }
  .main { margin-left: 64px; }
  .top { padding-inline: 14px; gap: 8px; }
  .content { padding: 12px 14px 20px; }
  .user-chip { padding-right: 4px; }
  .user-chip > span, .user-chip > i { display: none; }
  .quote { display: none; }
}
@media (max-width: 560px) {
  .top { height: auto; padding-block: 10px; flex-wrap: wrap; gap: 10px; }
  .top-right { margin-left: auto; gap: 6px; flex-wrap: wrap; justify-content: flex-end; }
}
@media (prefers-reduced-motion: reduce) {
  .icon-btn, .leaf, .navigation-shade-enter-active, .navigation-shade-leave-active { transition: none; }
}
</style>

<style>
.header-menu-label { flex: 1; margin-right: 18px; }
.header-account-summary { color: var(--text-primary); font: var(--font-size-body)/1.5 var(--sans); max-width: 240px; overflow-wrap: anywhere; }
.header-account-summary small { display: block; color: var(--text-secondary); font-size: var(--font-size-secondary); }
.chrome-pop { padding: 4px 2px 2px; }
.chrome-label {
  margin: 0 0 8px;
  font-size: var(--font-size-body);
  font-weight: 600;
  color: var(--text-secondary);
}
.chrome-pop .chrome-label + .swatches + .chrome-label { margin-top: 14px; }
.swatches { display: flex; gap: 8px; flex-wrap: wrap; align-items: center; }
.swatch {
  width: 22px; height: 22px; border-radius: 50%;
  border: 1px solid var(--border);
  padding: 0; cursor: pointer; background: none;
}
.swatch.on { outline: 2px solid var(--brand); outline-offset: 2px; }
.swatch:focus-visible, .swatch.picker:focus-within, .chrome-pop .reset:focus-visible { outline: 2px solid var(--brand); outline-offset: 3px; }
.swatch.picker {
  display: grid; place-items: center; overflow: hidden;
  background: conic-gradient(from 90deg, #1d1d1f, #1b8a6a, #f5f5f7, #1d1d1f);
}
.swatch.picker input {
  opacity: 0; width: 22px; height: 22px; cursor: pointer; border: 0; padding: 0;
}
.chrome-pop .reset {
  margin-top: 14px; width: 100%; height: 32px;
  border: 1px solid var(--border); border-radius: 999px;
  background: var(--bg-card); color: var(--text-primary);
  font: inherit; font-size: var(--font-size-body); font-weight: 600; cursor: pointer;
}
.chrome-pop .reset:hover { background: var(--bg-hover); }
</style>
