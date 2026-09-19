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
import { useRoutePreload } from '@/composables/useRoutePreload'
import { refreshHeaderVersionOnEntry, headerVersionSnapshot } from '@/api/headerVersion'
import { navigateWithFeedback, navigationErrorDetail, navigationLoading, navigationLoadingVisible, navigationPending, navigationProblem, navigationTargetPath, dismissNavigationProblem } from '@/utils/navigation'
import PageLoading from '@/components/PageLoading.vue'
import PageErrorNotice from '@/components/PageErrorNotice.vue'
import UserAvatar from '@/components/UserAvatar.vue'
import { loadSiteBrand, siteLogoName } from '@/composables/useSiteBrand'
import HeaderSearch from '@/components/header/HeaderSearch.vue'
import HeaderMessages from '@/components/header/HeaderMessages.vue'
import HeaderAssets from '@/components/header/HeaderAssets.vue'
import HeaderVersion from '@/components/header/HeaderVersion.vue'
import ThemeDrawer from '@/components/ThemeDrawer.vue'

const { t } = useI18n()
const route = useRoute()
const router = useRouter()
const shell = useShellStore()
const user = useUserStore()
const { locale, setLocale, syncing: localeSyncing } = useLocale()
const { prepare: preparePage, cancelIntent: cancelPagePreparation } = useRoutePreload(['/tenants/list', '/oci/list', '/vps/instances/list'])
const assets = ref<InstanceType<typeof HeaderAssets>>()
const version = ref<InstanceType<typeof HeaderVersion>>()
const messages = ref<InstanceType<typeof HeaderMessages>>()
const userRequest = new AbortController()
const siteBrandRequest = new AbortController()
let disposed = false
// Reset any hidden provider retained by an already mounted development session.
if (shell.cloudType !== 1) shell.setCloud(1)
const userLabel = computed(() => user.username || t(user.loading ? 'header.loading' : 'header.user'))
const languageLabel = computed(() => `${t('header.language')} · ${locale.value === 'zh' ? '简体中文' : 'English'}`)
const themeIcon = computed(() => themeMode.value === 'system' ? 'i-mdi-monitor' : theme.value === 'dark' ? 'i-mdi-weather-night' : 'i-mdi-white-balance-sunny')
const compactMedia = window.matchMedia('(max-width: 760px)')
const compactViewport = ref(compactMedia.matches)
const mobileNavOpen = ref(false)
const sidebarToggle = ref<HTMLButtonElement | null>(null)
const mobileSidebarToggle = ref<HTMLButtonElement | null>(null)
const sidebar = ref<HTMLElement | null>(null)
const mobilePreferencesOpen = ref(false)
const themeDrawerOpen = ref(false)
const content = ref<HTMLElement | null>(null)
const sidebarCollapsed = computed(() => !compactViewport.value && shell.collapsed)
const mobileLinks: Record<string, string> = {
  '/tenants/list': '/m/tenants', '/boot/fullBootList': '/m/boot', '/vps/instances/list': '/m/instances',
  '/oci/list': '/m/oci-instances', '/delayTest': '/m/speedtest', '/boot/dashboard': '/m/monitor',
  '/resource/list': '/m/arm-regions', '/system/settings': '/m/settings', '/dns/cloudflare': '/m/cloudflare',
  '/system/notifySettings': '/m/notify-settings', '/system/memPage': '/m/memo', '/mfa/page': '/m/mfa',
}
const mobileTabs: NavItem[] = [
  { id: 'tenants', href: '/m/tenants', labelKey: 'mobileShell.tabs.tenants', icon: 'i-mdi-account-group-outline' },
  { id: 'boot', href: '/m/boot', labelKey: 'mobileShell.tabs.boot', icon: 'i-mdi-play-circle-outline' },
  { id: 'instances', href: '/m/instances', labelKey: 'mobileShell.tabs.instances', icon: 'i-mdi-server-outline' },
  { id: 'speed', href: '/m/speedtest', labelKey: 'mobileShell.tabs.speed', icon: 'i-mdi-speedometer' },
  { id: 'monitor', href: '/m/monitor', labelKey: 'mobileShell.tabs.monitor', icon: 'i-mdi-chart-line' },
]
const pageTitleKeys: Record<string, string> = {
  '/tenants/list': 'tenants', '/boot/fullBootList': 'boot', '/vps/instances/list': 'instances',
  '/oci/list': 'ociInstances', '/delayTest': 'speed', '/boot/dashboard': 'monitor',
  '/tenants/regionList': 'regions', '/tenants/auditPage': 'audit', '/tenants/regionSubList': 'subscriptions',
  '/tenants/addSpeed': 'import', '/tenants/bootPage': 'launch', '/tenants/gcpBootPage': 'gcpLaunch',
  '/instanceDetail/bootList': 'tenantInstances', '/monitor/homePage': 'traffic', '/cost/costPage': 'cost',
  '/oci/vnic/manage': 'network', '/oci/metricsPage': 'metrics', '/oci/terminal': 'terminal', '/ssh/terminal': 'terminal',
  '/ai/chat': 'chat', '/m/ai': 'telegram', '/m/user-mgr': 'users', '/m/disk-info': 'volumes',
  '/m/security-rules': 'security', '/m/storage-instances': 'mysql',
}
function canonicalPath(path: string) {
  const resolved = router.resolve(path)
  return typeof resolved.meta.canonicalPath === 'string' ? resolved.meta.canonicalPath : resolved.path
}
const currentPath = computed(() => canonicalPath(route.path))
const mobilePageTitle = computed(() => {
  const detail = pageTitleKeys[currentPath.value] || pageTitleKeys[route.path]
  if (detail) return t(`mobileShell.titles.${detail}`)
  if (currentPath.value.startsWith('/oci/console/terminal')) return t('mobileShell.titles.console')
  const items = MENU.flatMap(group => group.children)
  const item = items.find(item => item.href === currentPath.value) || items.find(item => item.id === route.meta.id)
  return item ? t(item.labelKey) : t('mobileShell.console')
})
const activeMobileTab = computed(() => {
  const path = canonicalPath(navigationTargetPath.value || route.path)
  if (path === '/delayTest') return 'speed'
  if (path === '/boot/dashboard' || path === '/oci/metricsPage') return 'monitor'
  if (['/boot/fullBootList', '/tenants/bootList', '/tenants/bootPage', '/tenants/gcpBootPage'].includes(path)) return 'boot'
  if (path.startsWith('/vps/') || path.startsWith('/oci/')) return 'instances'
  if (path.startsWith('/tenants/') || path.startsWith('/instanceDetail/') || ['/cost/costPage', '/monitor/homePage', '/m/user-mgr', '/m/disk-info', '/m/security-rules', '/m/storage-instances'].includes(path)) return 'tenants'
  return ''
})

function itemHref(item: NavItem) { return compactViewport.value ? mobileLinks[item.href] || item.href : item.href }

function updateViewport(event: MediaQueryListEvent) {
  const activeElement = document.activeElement
  const focusInSidebar = sidebar.value?.contains(document.activeElement)
  const focusInDesktopTools = activeElement instanceof HTMLElement && activeElement.closest('.desktop-search, .desktop-tools')
  const focusInMobileTools = activeElement instanceof HTMLElement && activeElement.closest('.mobile-heading, .mobile-tabs')
  compactViewport.value = event.matches
  mobileNavOpen.value = false
  if (event.matches && route.matched.some(record => record.path === '/oci/sysHelp')) void router.replace('/m/instances')
  if (event.matches && (focusInSidebar || focusInDesktopTools)) void nextTick(() => mobileSidebarToggle.value?.focus())
  else if (!event.matches && focusInMobileTools) void nextTick(() => sidebarToggle.value?.focus())
}

function toggleSidebar() {
  if (compactViewport.value) {
    if (mobileNavOpen.value) closeMobileNav()
    else mobileNavOpen.value = true
  }
  else shell.toggleCollapsed()
}

function closeMobileNav(restoreFocus = true) {
  if (!mobileNavOpen.value) return
  mobileNavOpen.value = false
  if (restoreFocus) void nextTick(() => mobileSidebarToggle.value?.focus())
}

function trapMobileFocus(event: KeyboardEvent) {
  if (!compactViewport.value || !mobileNavOpen.value || event.key !== 'Tab') return
  const controls = Array.from(sidebar.value?.querySelectorAll<HTMLElement>('a[href], button:not(:disabled), input:not(:disabled), [tabindex="0"]') || [])
    .filter(element => element.getClientRects().length > 0)
  const first = controls[0]
  const last = controls[controls.length - 1]
  if (!first || !last) { event.preventDefault(); return }
  if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus() }
  else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus() }
}

function keepMobileFocus(event: FocusEvent) {
  if (compactViewport.value && mobileNavOpen.value && !sidebar.value?.contains(event.target as Node)) sidebarToggle.value?.focus()
}

function closeMobileNavWithEscape(event: KeyboardEvent) {
  if (event.key === 'Escape' && compactViewport.value && mobileNavOpen.value) closeMobileNav()
}

onMounted(() => {
  void refreshHeaderVersionOnEntry()
  void user.load(userRequest.signal)
  void loadSiteBrand(siteBrandRequest.signal)
  compactMedia.addEventListener('change', updateViewport)
  document.addEventListener('focusin', keepMobileFocus)
  document.addEventListener('keydown', closeMobileNavWithEscape)
})
onBeforeUnmount(() => {
  disposed = true
  userRequest.abort()
  siteBrandRequest.abort()
  compactMedia.removeEventListener('change', updateViewport)
  document.removeEventListener('focusin', keepMobileFocus)
  document.removeEventListener('keydown', closeMobileNavWithEscape)
})

watch(mobileNavOpen, async open => {
  if (!open) return
  messages.value?.close()
  await nextTick()
  if (mobileNavOpen.value) sidebarToggle.value?.focus()
})

watch(() => route.path, async () => {
  closeMobileNav()
  await nextTick()
  content.value?.scrollTo({ top: 0, left: 0 })
})

const visibleGroups = computed(() => {
  const q = shell.menuQuery.trim().toLowerCase()
  return MENU.map((g) => ({
    ...g,
    children: [...g.children, ...(compactViewport.value && g.id === 'tools' ? [{ id: 'mobile-telegram', href: '/m/ai', labelKey: 'mobileShell.titles.telegram', icon: 'i-mdi-robot-outline' } as NavItem] : [])].filter((it) => {
      if (compactViewport.value && /sysHelp|rescue/i.test(`${it.id} ${it.href}`)) return false
      if (it.cloudTypes && !it.cloudTypes.includes(shell.cloudType)) return false
      if (!q) return true
      return `${t(it.labelKey)} ${t(g.labelKey)} ${it.href}`.toLowerCase().includes(q)
    }),
  })).filter((g) => g.children.length > 0)
})

function openItem(it: NavItem, event: MouseEvent) {
  if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button !== 0) return
  event.preventDefault()
  closeMobileNav()
  shell.menuQuery = ''
  const href = itemHref(it)
  if (it.newTab) window.open(router.resolve(href).href, '_blank', 'noopener')
  else void navigateWithFeedback(router, href)
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
  else if (value === 'auditLogs') void router.push('/system/auditLogs')
  else if (value === 'about') version.value?.open()
  else if (value === 'logout') void signOut()
  else if (value === 'retry') void user.load(userRequest.signal)
  else if (value === 'preferences') mobilePreferencesOpen.value = true
}

function isActive(it: NavItem) {
  return canonicalPath(navigationTargetPath.value || route.path) === canonicalPath(it.href)
}

function retryNavigation() {
  const href = navigationProblem.value?.href
  if (href) void navigateWithFeedback(router, href)
}

</script>

<template>
  <div class="shell" :class="{ collapsed: sidebarCollapsed, 'mobile-nav-open': mobileNavOpen }" @keydown.esc="closeMobileNav()">
    <Transition name="navigation-shade"><button v-if="compactViewport && mobileNavOpen" class="mobile-nav-backdrop" type="button" tabindex="-1" :aria-label="t('header.collapseNav')" @click="closeMobileNav()" /></Transition>
    <aside ref="sidebar" class="side" :role="compactViewport ? 'dialog' : undefined" :aria-modal="compactViewport && mobileNavOpen || undefined" :aria-label="compactViewport ? t('header.navigation') : undefined" :aria-hidden="compactViewport && !mobileNavOpen || undefined" :inert="compactViewport && !mobileNavOpen || undefined" @keydown="trapMobileFocus">
      <div class="brand">
        <button ref="sidebarToggle" class="leaf" type="button" :aria-label="t(sidebarCollapsed ? 'header.expandNav' : 'header.collapseNav')" :title="t(sidebarCollapsed ? 'header.expandNav' : 'header.collapseNav')" :aria-expanded="compactViewport ? mobileNavOpen : !sidebarCollapsed" aria-controls="primary-navigation" @click="toggleSidebar">
          <i :class="compactViewport ? (mobileNavOpen ? 'i-mdi-close' : 'i-mdi-menu') : 'i-mdi-leaf'" aria-hidden="true" />
        </button>
        <RouterLink :to="compactViewport ? '/m/monitor' : '/boot/dashboard'" class="brand-text" :title="t('header.home')" :aria-label="t('header.home')" :tabindex="sidebarCollapsed ? -1 : undefined">
          <strong>{{ siteLogoName || t('brand') }}</strong>
          <small>{{ t('brandSub') }}</small>
        </RouterLink>
      </div>

      <label v-if="compactViewport" class="mobile-menu-search"><i class="i-mdi-magnify" aria-hidden="true" /><input v-model="shell.menuQuery" type="search" :placeholder="t('mobileShell.search')" :aria-label="t('mobileShell.search')" /></label>

      <nav id="primary-navigation" class="nav" :aria-label="t('header.navigation')">
        <template v-for="g in visibleGroups" :key="g.id">
          <div class="group-label">{{ t(g.labelKey) }}</div>
          <a
            v-for="it in g.children"
            :key="it.id"
            :href="router.resolve(itemHref(it)).href"
            :target="it.newTab ? '_blank' : undefined"
            :rel="it.newTab ? 'noopener' : undefined"
            class="nav-item"
            :class="{ active: isActive(it) }"
            :title="t(it.labelKey)"
            :aria-label="t(it.labelKey)"
            :aria-current="currentPath === canonicalPath(it.href) ? 'page' : undefined"
            :aria-busy="isActive(it) && navigationPending || undefined"
            @pointerenter="preparePage(itemHref(it))"
            @pointerleave="cancelPagePreparation"
            @focus="preparePage(itemHref(it))"
            @blur="cancelPagePreparation"
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
        <UserAvatar :name="user.username" context="sidebar" />
        <div class="side-user-meta">
          <b>{{ userLabel }}</b>
          <small>{{ shell.cloudName }}</small>
        </div>
      </div>
    </aside>

    <div class="main" :inert="compactViewport && mobileNavOpen || undefined">
      <header class="top">
        <div class="mobile-heading">
          <button ref="mobileSidebarToggle" class="icon-btn mobile-menu-toggle" type="button" :aria-label="t('header.expandNav')" :aria-expanded="mobileNavOpen" aria-controls="primary-navigation" @click="toggleSidebar"><i class="i-mdi-menu" aria-hidden="true" /></button>
          <span class="mobile-page-title" :title="mobilePageTitle">{{ mobilePageTitle }}</span>
        </div>
        <div class="desktop-search"><HeaderSearch /></div>
        <div class="top-right">
          <div class="desktop-tools">
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
          <button
            class="icon-btn"
            type="button"
            :title="t('chrome.title')"
            :aria-label="t('chrome.title')"
            @click="themeDrawerOpen = true"
          >
            <i class="i-mdi-palette-outline" />
          </button>
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
          </div>
          <HeaderMessages ref="messages" />
          <el-dropdown trigger="click" placement="bottom-end" :popper-class="compactViewport ? 'mobile-account-menu' : undefined" @command="userCommand">
            <button class="user-chip" type="button" :title="t(user.loadFailed ? 'header.userFailed' : 'header.userMenu')" :aria-label="`${userLabel} · ${t('header.userMenu')}`">
              <UserAvatar :name="user.username" />
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
                <el-dropdown-item v-if="compactViewport" divided command="preferences"><i :class="themeIcon" aria-hidden="true" />{{ t('mobileShell.preferences') }}</el-dropdown-item>
                <el-dropdown-item divided command="assets"><i class="i-mdi-chart-box-outline" aria-hidden="true" />{{ t('header.assets') }}</el-dropdown-item>
                <el-dropdown-item command="auditLogs"><i class="i-mdi-shield-check-outline" aria-hidden="true" />{{ t('header.auditLogs') }}</el-dropdown-item>
                <el-dropdown-item command="about"><i class="i-mdi-information-outline" aria-hidden="true" />
                  {{ t(compactViewport && headerVersionSnapshot?.needUpdate ? 'headerVersion.updateAvailable' : 'about') }}
                </el-dropdown-item>
                <el-dropdown-item divided command="logout" class="account-logout" :disabled="user.signingOut"><i class="i-mdi-logout" aria-hidden="true" />{{ t(user.signingOut ? 'header.signOutBusy' : 'logout') }}</el-dropdown-item>
              </el-dropdown-menu>
            </template>
          </el-dropdown>
        </div>
      </header>

      <div class="content-stage" :aria-busy="navigationPending || undefined">
        <section ref="content" class="content" :inert="navigationLoading && route.path !== navigationTargetPath || undefined">
          <RouterView v-slot="{ Component, route: currentRoute }">
            <component :is="Component" :key="currentRoute.path" />
          </RouterView>
        </section>
        <PageLoading :visible="navigationLoadingVisible" />
        <PageErrorNotice v-if="navigationProblem" :title="t('pageLoading.failed')"><p>{{ navigationErrorDetail || t('pageLoading.failed') }}</p><button type="button" @click="retryNavigation">{{ t('pageLoading.retry') }}</button><button type="button" @click="dismissNavigationProblem">{{ t('pageError.close') }}</button></PageErrorNotice>
      </div>
      <nav class="mobile-tabs" :aria-label="t('mobileShell.navigation')">
        <a v-for="tab in mobileTabs" :key="tab.id" :href="router.resolve(tab.href).href" :class="{ active: activeMobileTab === tab.id }" :aria-current="activeMobileTab === tab.id ? 'page' : undefined" :aria-label="t(tab.labelKey)" @pointerenter="preparePage(tab.href)" @pointerleave="cancelPagePreparation" @focus="preparePage(tab.href)" @blur="cancelPagePreparation" @click="openItem(tab, $event)"><i :class="tab.icon" aria-hidden="true" /><span>{{ t(tab.labelKey) }}</span></a>
      </nav>
    </div>
    <HeaderAssets ref="assets" />
    <ThemeDrawer v-model="themeDrawerOpen" />
    <el-dialog v-model="mobilePreferencesOpen" class="mobile-preferences-dialog" :title="t('mobileShell.preferences')" width="min(460px, calc(100vw - 24px))" align-center append-to-body>
      <div class="mobile-preferences">
        <fieldset><legend>{{ t('header.appearance') }}</legend><div class="mobile-preference-options"><button v-for="mode in ['light', 'dark', 'system']" :key="mode" type="button" :aria-pressed="themeMode === mode" @click="changeTheme(mode)">{{ t(`header.${mode}`) }}<i v-if="themeMode === mode" class="i-mdi-check" aria-hidden="true" /></button></div></fieldset>
        <fieldset><legend>{{ t('header.language') }}</legend><div class="mobile-preference-options"><button type="button" lang="zh-CN" :aria-pressed="locale === 'zh'" :disabled="localeSyncing" @click="changeLocale('zh')">简体中文<i v-if="locale === 'zh'" class="i-mdi-check" aria-hidden="true" /></button><button type="button" lang="en" :aria-pressed="locale === 'en'" :disabled="localeSyncing" @click="changeLocale('en')">English<i v-if="locale === 'en'" class="i-mdi-check" aria-hidden="true" /></button></div></fieldset>
        <fieldset><legend>{{ t('chrome.title') }}</legend><div class="mobile-preference-options"><button type="button" @click="mobilePreferencesOpen = false; themeDrawerOpen = true"><i class="i-mdi-palette-outline" aria-hidden="true" />{{ t('chrome.subtitle') }}</button></div></fieldset>
      </div>
    </el-dialog>
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
  border-right: 1px solid color-mix(in srgb, var(--border) 40%, transparent);
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
.desktop-search { display: contents; }
.desktop-tools { display: flex; align-items: center; gap: 8px; }
.mobile-heading, .mobile-tabs { display: none; }
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
.content-stage { position: relative; display: flex; flex: 1; min-width: 0; min-height: 0; }
.content {
  flex: 1;
  min-width: 0;
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
  .shell { width: 100%; height: 100dvh; max-height: 100dvh; overflow: hidden; }
  .side { position: fixed; inset: 0 auto 0 0; z-index: 20; width: min(360px, calc(100vw - 28px)); max-width: 100%; height: 100dvh; padding: calc(14px + env(safe-area-inset-top)) 14px calc(14px + env(safe-area-inset-bottom)); transform: translateX(-100%); visibility: hidden; transition: transform 220ms ease, visibility 220ms; }
  .mobile-nav-open .side { transform: translateX(0); visibility: visible; }
  .brand { flex: none; padding: 0 0 14px; }
  .brand-text { max-width: none; }
  .leaf { width: 44px; height: 44px; }
  .nav { min-height: 0; overscroll-behavior: contain; }
  .nav-item { min-height: 44px; white-space: normal; }
  .nav-item span { max-width: none; }
  .mobile-menu-search { display: flex; flex: none; align-items: center; gap: 8px; min-height: 44px; margin-bottom: 8px; padding: 8px 12px; border: 1px solid color-mix(in srgb, var(--text-on-dark) 25%, transparent); border-radius: var(--r-pill); }
  .mobile-menu-search > i { flex: none; width: 18px; height: 18px; }
  .mobile-menu-search input { min-width: 0; width: 100%; border: 0; outline: 0; background: transparent; color: var(--text-on-dark); font: var(--font-size-body)/1.5 var(--sans); }
  .mobile-menu-search input::placeholder { color: var(--text-on-dark-muted); opacity: 1; }
  .mobile-menu-search:focus-within { outline: 2px solid var(--brand); outline-offset: 2px; }
  .main { margin-left: 0; width: 100%; min-height: 0; }
  .top { height: calc(60px + env(safe-area-inset-top)); padding: env(safe-area-inset-top) max(12px, env(safe-area-inset-right)) 0 max(12px, env(safe-area-inset-left)); gap: 8px; box-sizing: border-box; flex-wrap: nowrap; }
  .mobile-heading { display: flex; flex: 1; align-items: center; gap: 10px; min-width: 0; }
  .mobile-page-title { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: var(--text-primary); font-size: var(--font-size-body); font-weight: 600; }
  .desktop-search, .desktop-tools { display: none; }
  .top-right { gap: 8px; flex-wrap: nowrap; }
  .top .icon-btn, .top :deep(.message-trigger) { width: 44px; height: 44px; }
  .content { padding: 4px max(12px, env(safe-area-inset-right)) 12px max(12px, env(safe-area-inset-left)); }
  .user-chip { justify-content: center; width: 44px; height: 44px; padding: 4px; }
  .user-chip > span, .user-chip > i { display: none; }
  .side-user { flex: none; }
  .quote { display: none; }
  .mobile-tabs { display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); flex: none; width: 100%; min-height: 60px; padding: 4px env(safe-area-inset-right) calc(4px + env(safe-area-inset-bottom)) env(safe-area-inset-left); border-top: 1px solid var(--border); background: var(--bg-card); }
  .mobile-tabs a { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 3px; min-width: 0; min-height: 52px; margin-inline: 2px; padding: 4px 0; border-radius: 12px; color: var(--text-primary); text-decoration: none; font: var(--font-size-body)/1.35 var(--sans); }
  .mobile-tabs a > i { flex: none; width: 22px; height: 22px; font-size: 22px; }
  .mobile-tabs a > span { max-width: 100%; white-space: nowrap; text-align: center; }
  .mobile-tabs a.active { color: var(--brand); background: var(--status-ok-bg); font-weight: 600; }
  .mobile-tabs a:focus-visible { outline: 2px solid var(--brand); outline-offset: -2px; }
  .mobile-nav-backdrop { position: fixed; }
}
@media (prefers-reduced-motion: reduce) {
  .icon-btn, .leaf, .navigation-shade-enter-active, .navigation-shade-leave-active { transition: none; }
}
</style>

<style>
.header-menu-label { flex: 1; margin-right: 18px; }
.header-account-summary { color: var(--text-primary); font: var(--font-size-body)/1.5 var(--sans); max-width: 240px; overflow-wrap: anywhere; }
.header-account-summary small { display: block; color: var(--text-secondary); font-size: var(--font-size-secondary); }

.mobile-account-menu { max-width: calc(100vw - 24px); }
.mobile-account-menu .el-dropdown-menu__item { min-height: 44px; white-space: normal; font-size: var(--font-size-body); }
.mobile-preferences-dialog { max-width: calc(100vw - 24px); }
.mobile-preferences-dialog .el-dialog__body { max-height: calc(100dvh - 160px); overflow-y: auto; overscroll-behavior: contain; }
.mobile-preferences { display: flex; flex-direction: column; gap: 20px; color: var(--text-primary); font: var(--font-size-body)/1.5 var(--sans); }
.mobile-preferences fieldset { min-width: 0; margin: 0; padding: 0; border: 0; }
.mobile-preferences legend { padding: 0; margin-bottom: 10px; color: var(--text-primary); font-weight: 600; }
.mobile-preference-options { display: flex; flex-wrap: wrap; gap: 8px; }
.mobile-preference-options button { display: flex; flex: 1; align-items: center; justify-content: center; gap: 5px; min-height: 44px; padding: 8px 10px; border: 1px solid var(--border); border-radius: 12px; background: var(--bg-card); color: var(--text-primary); font: var(--font-size-body)/1.4 var(--sans); cursor: pointer; }
.mobile-preference-options button[aria-pressed='true'] { border-color: var(--brand); background: var(--status-ok-bg); }
.mobile-preference-options button:disabled { opacity: .6; cursor: wait; }
.mobile-preference-options button:focus-visible { outline: 2px solid var(--brand); outline-offset: 2px; }
</style>
