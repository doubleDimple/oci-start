<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { ElMessage } from 'element-plus'
import { theme, themeMode, setTheme, type ThemePreference } from '@/composables/useTheme'
import {
  chrome,
  CONTENT_PRESETS,
  SIDEBAR_PRESETS,
  activeContentPreset,
  activeSidebarPreset,
  setContentPreset,
  setCustomPageColor,
  setSidebarPreset,
  setSidebarColor,
  resetChrome,
  type ContentPalette,
  type SidebarTheme,
} from '@/composables/useChrome'

const props = defineProps<{
  modelValue: boolean
}>()

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void
}>()

const { t } = useI18n()

const visible = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val),
})

const modeOptions: { key: ThemePreference; labelKey: string; icon: string }[] = [
  { key: 'light', labelKey: 'header.light', icon: 'i-mdi-white-balance-sunny' },
  { key: 'dark', labelKey: 'header.dark', icon: 'i-mdi-weather-night' },
  { key: 'system', labelKey: 'header.system', icon: 'i-mdi-monitor' },
]

function onSelectMode(mode: ThemePreference) {
  setTheme(mode)
}

function onSelectSidebar(item: SidebarTheme) {
  setSidebarPreset(item.id)
}

function onCustomSidebarInput(e: Event) {
  const target = e.target as HTMLInputElement
  if (target?.value) {
    setSidebarColor(target.value)
  }
}

function onSelectContentPreset(preset: ContentPalette) {
  setContentPreset(preset.id)
}

function onCustomPageInput(e: Event) {
  const target = e.target as HTMLInputElement
  if (target?.value) {
    setCustomPageColor(target.value)
  }
}

function onReset() {
  resetChrome()
  ElMessage.success(t('chrome.resetTip'))
}
</script>

<template>
  <el-drawer
    v-model="visible"
    :title="t('chrome.title')"
    size="390px"
    class="theme-customizer-drawer"
    direction="rtl"
    append-to-body
    :destroy-on-close="false"
  >
    <template #header>
      <div class="drawer-header">
        <div class="header-icon">
          <i class="i-mdi-palette-swatch-outline" aria-hidden="true" />
        </div>
        <div>
          <h3 class="header-title">{{ t('chrome.title') }}</h3>
          <p class="header-sub">{{ t('chrome.subtitle') }}</p>
        </div>
      </div>
    </template>

    <div class="drawer-body">
      <!-- Section 1: Appearance Mode -->
      <section class="config-section">
        <div class="section-title-wrap">
          <i class="i-mdi-theme-light-dark section-icon" />
          <h4 class="section-title">{{ t('chrome.modeTitle') }}</h4>
        </div>
        <div class="mode-grid">
          <button
            v-for="opt in modeOptions"
            :key="opt.key"
            type="button"
            class="mode-card"
            :class="{ active: themeMode === opt.key }"
            :aria-pressed="themeMode === opt.key"
            @click="onSelectMode(opt.key)"
          >
            <i :class="opt.icon" class="mode-icon" />
            <span class="mode-label">{{ t(opt.labelKey) }}</span>
            <i v-if="themeMode === opt.key" class="i-mdi-check check-badge" />
          </button>
        </div>
      </section>

      <!-- Section 2: Sidebar Theme -->
      <section class="config-section">
        <div class="section-title-wrap">
          <i class="i-mdi-dock-left section-icon" />
          <h4 class="section-title">{{ t('chrome.sidebarTitle') }}</h4>
        </div>
        <div class="sidebar-swatches">
          <button
            v-for="sb in SIDEBAR_PRESETS"
            :key="sb.id"
            type="button"
            class="sidebar-pill"
            :class="{ active: activeSidebarPreset === sb.id || chrome.sidebar.toLowerCase() === sb.color.toLowerCase() }"
            @click="onSelectSidebar(sb)"
          >
            <span class="color-dot" :style="{ background: sb.color }" />
            <span class="pill-name">{{ t(sb.nameKey) }}</span>
            <i v-if="activeSidebarPreset === sb.id || chrome.sidebar.toLowerCase() === sb.color.toLowerCase()" class="i-mdi-check dot-check" />
          </button>
          <label class="sidebar-picker-pill" :title="t('chrome.customPicker')">
            <span class="picker-preview" :style="{ background: chrome.sidebar || '#18181b' }" />
            <span class="picker-label">{{ t('chrome.customPicker') }}</span>
            <input
              type="color"
              class="hidden-color-input"
              :value="chrome.sidebar || '#18181b'"
              @input="onCustomSidebarInput"
            />
          </label>
        </div>
      </section>

      <!-- Section 3: Content Area & Card Surfaces (Core) -->
      <section class="config-section">
        <div class="section-title-wrap">
          <i class="i-mdi-view-dashboard-variant-outline section-icon" />
          <div>
            <h4 class="section-title">{{ t('chrome.contentTitle') }}</h4>
            <p class="section-sub">{{ t('chrome.contentDesc') }}</p>
          </div>
        </div>

        <!-- Curated Presets with visual layer preview -->
        <div class="content-presets-grid">
          <div
            v-for="preset in CONTENT_PRESETS"
            :key="preset.id"
            class="preset-card"
            :class="{ active: activeContentPreset === preset.id }"
            @click="onSelectContentPreset(preset)"
          >
            <!-- Visual layer simulation -->
            <div class="preset-preview-canvas" :style="{ background: preset.page }">
              <div class="mini-sidebar" :style="{ background: chrome.sidebar || '#18181b' }" />
              <div class="mini-content">
                <div class="mini-topbar" :style="{ borderBottomColor: preset.border }" />
                <div
                  class="mini-card"
                  :style="{
                    background: preset.card,
                    borderColor: preset.border,
                    boxShadow: preset.shadowCard,
                  }"
                >
                  <span class="mini-line w-60" :style="{ background: preset.textPrimary }" />
                  <span class="mini-line w-40" :style="{ background: preset.textSecondary }" />
                </div>
                <div
                  class="mini-card mini-subcard"
                  :style="{
                    background: preset.card,
                    borderColor: preset.border,
                  }"
                >
                  <span class="mini-dot" :style="{ background: 'var(--brand)' }" />
                  <span class="mini-line w-50" :style="{ background: preset.textMuted }" />
                </div>
              </div>
            </div>

            <!-- Footer description -->
            <div class="preset-footer">
              <span class="preset-name">{{ t(preset.nameKey) }}</span>
              <span class="preset-mode-tag" :class="preset.mode">
                {{ preset.mode === 'dark' ? t('header.dark') : t('header.light') }}
              </span>
              <i v-if="activeContentPreset === preset.id" class="i-mdi-check-circle preset-check" />
            </div>
          </div>
        </div>

        <!-- Custom Content Color Picker with derivation engine notice -->
        <div class="custom-content-box">
          <div class="custom-content-row">
            <label class="custom-color-trigger">
              <span class="color-badge" :style="{ background: chrome.page }" />
              <span class="custom-text">
                <b>{{ t('chrome.customPicker') }}</b>
                <small>{{ chrome.page }}</small>
              </span>
              <input
                type="color"
                class="hidden-color-input"
                :value="chrome.page || (theme === 'dark' ? '#0b0f19' : '#f1f5f9')"
                @input="onCustomPageInput"
              />
            </label>
          </div>
          <p class="custom-hint">{{ t('chrome.customHint') }}</p>
        </div>
      </section>
    </div>

    <template #footer>
      <div class="drawer-footer">
        <button type="button" class="btn-reset" @click="onReset">
          <i class="i-mdi-restore" />
          <span>{{ t('chrome.reset') }}</span>
        </button>
        <button type="button" class="btn-done" @click="visible = false">
          {{ t('common.done', '完成') }}
        </button>
      </div>
    </template>
  </el-drawer>
</template>

<style scoped>
.theme-customizer-drawer :deep(.el-drawer__header) {
  margin-bottom: 0;
  padding: 18px 22px 14px;
  border-bottom: 1px solid var(--border);
}
.theme-customizer-drawer :deep(.el-drawer__body) {
  padding: 0;
  background: var(--bg-card);
  color: var(--text-primary);
  overflow-y: auto;
}
.theme-customizer-drawer :deep(.el-drawer__footer) {
  padding: 14px 22px;
  border-top: 1px solid var(--border);
  background: var(--bg-card);
}

.drawer-header {
  display: flex;
  align-items: center;
  gap: 12px;
}
.header-icon {
  width: 38px;
  height: 38px;
  border-radius: 10px;
  background: var(--status-ok-bg);
  color: var(--brand);
  display: grid;
  place-items: center;
  font-size: 20px;
}
.header-title {
  margin: 0;
  font-size: var(--font-size-section);
  font-weight: 600;
  color: var(--text-primary);
}
.header-sub {
  margin: 3px 0 0;
  font-size: var(--font-size-secondary);
  color: var(--text-secondary);
}

.drawer-body {
  padding: 20px 22px 28px;
  display: flex;
  flex-direction: column;
  gap: 26px;
}

.config-section {
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.section-title-wrap {
  display: flex;
  align-items: flex-start;
  gap: 8px;
}
.section-icon {
  font-size: 18px;
  color: var(--brand);
  margin-top: 1px;
}
.section-title {
  margin: 0;
  font-size: var(--font-size-body);
  font-weight: 600;
  color: var(--text-primary);
}
.section-sub {
  margin: 2px 0 0;
  font-size: var(--font-size-secondary);
  color: var(--text-secondary);
}

/* Mode grid */
.mode-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 8px;
}
.mode-card {
  position: relative;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  padding: 12px 6px;
  border: 1px solid var(--border);
  border-radius: 12px;
  background: var(--bg-card);
  color: var(--text-primary);
  cursor: pointer;
  transition: all 160ms ease;
}
.mode-card:hover {
  border-color: var(--border-strong);
  background: var(--bg-hover);
}
.mode-card.active {
  border-color: var(--brand);
  background: var(--status-ok-bg);
  color: var(--brand);
}
.mode-icon {
  font-size: 20px;
}
.mode-label {
  font-size: var(--font-size-secondary);
  font-weight: 500;
}
.check-badge {
  position: absolute;
  top: 6px;
  right: 6px;
  font-size: 13px;
  color: var(--brand);
}

/* Sidebar swatches */
.sidebar-swatches {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 8px;
}
.sidebar-pill, .sidebar-picker-pill {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 10px;
  border: 1px solid var(--border);
  border-radius: 10px;
  background: var(--bg-card);
  color: var(--text-primary);
  cursor: pointer;
  position: relative;
  transition: all 160ms ease;
  font: inherit;
}
.sidebar-pill:hover, .sidebar-picker-pill:hover {
  border-color: var(--border-strong);
  background: var(--bg-hover);
}
.sidebar-pill.active {
  border-color: var(--brand);
  background: var(--status-ok-bg);
}
.color-dot {
  width: 18px;
  height: 18px;
  border-radius: 50%;
  border: 1px solid rgba(0, 0, 0, 0.12);
  flex-shrink: 0;
}
.pill-name, .picker-label {
  font-size: var(--font-size-secondary);
  font-weight: 500;
  flex: 1;
  text-align: left;
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
}
.dot-check {
  font-size: 15px;
  color: var(--brand);
}
.picker-preview {
  width: 18px;
  height: 18px;
  border-radius: 50%;
  border: 1px solid var(--border);
  flex-shrink: 0;
  background: conic-gradient(from 90deg, #1d1d1f, #1b8a6a, #f1f5f9, #1d1d1f);
}

/* Hidden color input */
.hidden-color-input {
  position: absolute;
  inset: 0;
  opacity: 0;
  width: 100%;
  height: 100%;
  cursor: pointer;
}

/* Content Presets Grid */
.content-presets-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 10px;
}
.preset-card {
  position: relative;
  display: flex;
  flex-direction: column;
  border: 1.5px solid var(--border);
  border-radius: 14px;
  overflow: hidden;
  cursor: pointer;
  background: var(--bg-card);
  transition: all 180ms ease;
}
.preset-card:hover {
  border-color: var(--border-strong);
  transform: translateY(-2px);
  box-shadow: var(--shadow-card);
}
.preset-card.active {
  border-color: var(--brand);
  box-shadow: 0 0 0 2px color-mix(in srgb, var(--brand) 25%, transparent);
}
.preset-preview-canvas {
  height: 76px;
  display: flex;
  padding: 7px;
  gap: 6px;
  position: relative;
  overflow: hidden;
}
.mini-sidebar {
  width: 18px;
  height: 100%;
  border-radius: 4px;
  flex-shrink: 0;
}
.mini-content {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 5px;
  min-width: 0;
}
.mini-topbar {
  height: 6px;
  border-bottom: 1px solid;
  opacity: 0.4;
}
.mini-card {
  flex: 1;
  border-radius: 6px;
  border: 1px solid;
  padding: 5px 6px;
  display: flex;
  flex-direction: column;
  gap: 3px;
  justify-content: center;
}
.mini-subcard {
  flex: 0 0 12px;
  flex-direction: row;
  align-items: center;
  padding: 2px 5px;
  gap: 4px;
}
.mini-line {
  height: 3px;
  border-radius: 2px;
  opacity: 0.8;
}
.mini-line.w-60 { width: 60%; }
.mini-line.w-50 { width: 50%; }
.mini-line.w-40 { width: 40%; }
.mini-dot {
  width: 4px;
  height: 4px;
  border-radius: 50%;
}
.preset-footer {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 8px 10px;
  border-top: 1px solid var(--border);
  background: var(--bg-card);
}
.preset-name {
  font-size: var(--font-size-secondary);
  font-weight: 600;
  color: var(--text-primary);
  flex: 1;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.preset-mode-tag {
  font-size: 11px;
  padding: 1px 5px;
  border-radius: 4px;
  font-weight: 500;
}
.preset-mode-tag.light {
  background: #f1f5f9;
  color: #475569;
}
.preset-mode-tag.dark {
  background: #1e293b;
  color: #cbd5e1;
}
.preset-check {
  font-size: 16px;
  color: var(--brand);
}

/* Custom Content Box */
.custom-content-box {
  margin-top: 4px;
  padding: 12px 14px;
  border: 1px dashed var(--border-strong);
  border-radius: 12px;
  background: var(--bg-hover);
}
.custom-content-row {
  display: flex;
  align-items: center;
}
.custom-color-trigger {
  position: relative;
  display: flex;
  align-items: center;
  gap: 10px;
  cursor: pointer;
  flex: 1;
}
.color-badge {
  width: 28px;
  height: 28px;
  border-radius: 8px;
  border: 1px solid var(--border-strong);
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.1);
  flex-shrink: 0;
}
.custom-text b {
  display: block;
  font-size: var(--font-size-body);
  color: var(--text-primary);
}
.custom-text small {
  display: block;
  font-size: var(--font-size-secondary);
  color: var(--text-secondary);
  font-family: var(--mono);
}
.custom-hint {
  margin: 8px 0 0;
  font-size: var(--font-size-caption);
  color: var(--text-muted);
  line-height: 1.4;
}

/* Footer buttons */
.drawer-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}
.btn-reset {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 8px 14px;
  border: 1px solid var(--border);
  border-radius: 10px;
  background: var(--bg-hover);
  color: var(--text-primary);
  font-size: var(--font-size-body);
  font-weight: 500;
  cursor: pointer;
  transition: all 160ms ease;
}
.btn-reset:hover {
  background: var(--bg-search);
  border-color: var(--border-strong);
}
.btn-done {
  padding: 8px 20px;
  border: 0;
  border-radius: 10px;
  background: var(--brand);
  color: #ffffff;
  font-size: var(--font-size-body);
  font-weight: 600;
  cursor: pointer;
  transition: background-color 160ms ease;
}
.btn-done:hover {
  background: var(--brand-hover);
}
</style>
