<script setup lang="ts">
import { useI18n } from 'vue-i18n'

const props = defineProps<{
  disabled: boolean
  canOperate: boolean
  showInstall: boolean
  rowName: string
}>()
const emit = defineEmits<{
  ssh: []
  details: []
  quality: []
  install: []
  uninstall: []
}>()
const { t } = useI18n()

function ssh(): void {
  if (!props.disabled) emit('ssh')
}
function command(value: unknown): void {
  if (props.disabled) return
  if (value === 'details') emit('details')
  else if (value === 'quality') emit('quality')
  else if (props.canOperate && value === 'install' && props.showInstall) emit('install')
  else if (props.canOperate && value === 'uninstall') emit('uninstall')
}
</script>

<template>
  <div class="vps-compact-actions">
    <button
      type="button"
      class="vps-action-btn"
      :disabled="disabled"
      :aria-label="`${t('vps.ssh')} · ${rowName}`"
      :title="t('vps.ssh')"
      @click="ssh"
    >
      <i class="i-mdi-console" aria-hidden="true" />
    </button>
    <button
      type="button"
      class="vps-action-btn"
      :disabled="disabled"
      :aria-label="`${t('vpsDetails.title')} · ${rowName}`"
      :title="t('vpsDetails.title')"
      @click="emit('details')"
    >
      <i class="i-mdi-information-outline" aria-hidden="true" />
    </button>
    <el-dropdown
      trigger="click"
      placement="bottom-end"
      :teleported="true"
      :hide-on-click="true"
      :disabled="disabled"
      popper-class="vps-menu vps-row-actions-menu"
      @command="command"
    >
      <button
        type="button"
        class="vps-action-btn"
        :disabled="disabled"
        :aria-label="`${t('vps.more')} · ${rowName}`"
        :title="t('vps.more')"
      >
        <i class="i-mdi-dots-horizontal" aria-hidden="true" />
      </button>
      <template #dropdown>
        <el-dropdown-menu>
          <el-dropdown-item command="quality" :disabled="disabled">
            <i class="i-mdi-chart-line" aria-hidden="true" /><span>{{ t('networkQuality.details') }}</span>
          </el-dropdown-item>
          <el-dropdown-item v-if="showInstall" command="install" :disabled="disabled || !canOperate">
            <i class="i-mdi-download-outline" aria-hidden="true" /><span>{{ t('vps.install') }}</span>
          </el-dropdown-item>
          <el-dropdown-item command="uninstall" divided class="vps-row-action-danger" :disabled="disabled || !canOperate">
            <i class="i-mdi-trash-can-outline" aria-hidden="true" /><span>{{ t('vps.uninstall') }}</span>
          </el-dropdown-item>
        </el-dropdown-menu>
      </template>
    </el-dropdown>
  </div>
</template>

<style scoped>
.vps-compact-actions {
  display: inline-flex;
  align-items: center;
  justify-content: flex-start;
  gap: 6px;
  white-space: nowrap;
}

.vps-action-btn {
  display: inline-flex;
  justify-content: center;
  align-items: center;
  width: 32px;
  height: 32px;
  padding: 0;
  box-sizing: border-box;
  border: 1px solid color-mix(in srgb, var(--border) 70%, transparent);
  border-radius: 9px;
  background: var(--bg-card);
  color: var(--text-primary);
  font: inherit;
  font-size: 15px;
  cursor: pointer;
  transition: all 0.16s ease;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.04);
  flex-shrink: 0;
}

.vps-action-btn > i {
  flex: none;
  width: 16px;
  height: 16px;
  font-size: 16px;
}

.vps-action-btn:hover:not(:disabled) {
  color: var(--brand);
  background: var(--status-ok-bg);
  border-color: color-mix(in srgb, var(--brand) 30%, transparent);
  box-shadow: 0 2px 8px color-mix(in srgb, var(--brand) 12%, transparent);
  transform: translateY(-1px);
}

.vps-action-btn:active:not(:disabled) {
  transform: scale(0.94);
}

.vps-action-btn:focus-visible {
  outline: 2px solid var(--brand);
  outline-offset: 2px;
}

.vps-action-btn:disabled {
  opacity: 0.45;
  cursor: not-allowed;
  box-shadow: none;
}
</style>

<style>
/* The menu is teleported outside the table; every rule stays local to this popper. */
.vps-menu.vps-row-actions-menu { max-width: min(280px, calc(100vw - 24px)); color: var(--text-primary); font: 400 var(--font-size-body)/20px var(--sans); }
.vps-menu.vps-row-actions-menu .el-dropdown-menu { min-width: 180px; max-height: min(360px, calc(100dvh - 32px)); overflow-y: auto; overscroll-behavior: contain; background: var(--bg-card); }
.vps-menu.vps-row-actions-menu .el-dropdown-menu__item { gap: 8px; min-height: 36px; padding: 7px 10px; border-radius: var(--r-sm); color: var(--text-primary); font: inherit; white-space: normal; }
.vps-menu.vps-row-actions-menu .el-dropdown-menu__item > i { flex: none; width: 17px; height: 17px; }
.vps-menu.vps-row-actions-menu .el-dropdown-menu__item > span { min-width: 0; overflow-wrap: anywhere; }
.vps-menu.vps-row-actions-menu .el-dropdown-menu__item:not(.is-disabled):is(:hover, :focus, .is-hovering) { background: var(--bg-hover); color: var(--text-primary); }
.vps-menu.vps-row-actions-menu .el-dropdown-menu__item:focus-visible { outline: 2px solid var(--brand); outline-offset: -2px; }
.vps-menu.vps-row-actions-menu .el-dropdown-menu__item--divided { border-top-color: var(--border); }
.vps-menu.vps-row-actions-menu .el-dropdown-menu__item.vps-row-action-danger:not(.is-disabled) { color: var(--status-danger); }
.vps-menu.vps-row-actions-menu .el-dropdown-menu__item.vps-row-action-danger:not(.is-disabled):is(:hover, :focus, .is-hovering) { background: var(--status-danger-bg); }
.vps-menu.vps-row-actions-menu .el-dropdown-menu__item.is-disabled { color: var(--text-muted); cursor: not-allowed; }
</style>
