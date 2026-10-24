<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { loadMemoImage, memoDisplayHtml, updateMemoImageLabels } from './memoContent'

const props = withDefaults(defineProps<{ html?: string | null; text?: string }>(), { html: '', text: '' })
const { t } = useI18n()
const root = ref<HTMLElement>()
const labels = computed(() => ({ load: t('memo.editor.loadImage'), blocked: t('memo.editor.imageBlocked'), failed: t('memo.editor.imageFailed') }))
const rendered = ref('')
watch(() => [props.html, props.text], () => { rendered.value = memoDisplayHtml(props.html, props.text, labels.value) }, { immediate: true })
watch(labels, value => { if (root.value) updateMemoImageLabels(root.value, value) }, { flush: 'post' })
function click(event: MouseEvent) { if (root.value) loadMemoImage(event, root.value, () => labels.value) }
</script>

<template><div ref="root" class="memo-content" @click="click" v-html="rendered" /></template>

<style scoped>
.memo-content { min-width: 0; color: var(--text-primary); font: 400 var(--font-size-body)/1.7 var(--sans); overflow-wrap: anywhere; white-space: pre-wrap; }
.memo-content :deep(p), .memo-content :deep(div) { margin: 0 0 12px; }
.memo-content :deep(h1), .memo-content :deep(h2) { font: 600 var(--font-size-dialog-title)/1.5 var(--sans); margin: 20px 0 10px; }
.memo-content :deep(h3) { font: 600 var(--font-size-section)/1.5 var(--sans); margin: 18px 0 8px; }
.memo-content :deep(blockquote) { margin: 12px 0; padding: 4px 14px; border-left: 3px solid var(--border-strong); color: var(--text-primary); }
.memo-content :deep(pre) { padding: 12px; background: var(--bg-search); white-space: pre-wrap; border-radius: 5px; }
.memo-content :deep(code), .memo-content :deep(pre) { font: 400 var(--font-size-body)/1.65 var(--mono); }
.memo-content :deep(ul), .memo-content :deep(ol) { padding-left: 24px; margin: 10px 0; }
.memo-content :deep(a) { color: var(--text-primary); text-decoration: underline; text-underline-offset: 3px; }
.memo-content :deep(a:focus-visible) { outline: 2px solid var(--brand); outline-offset: 2px; }
.memo-content :deep(.memo-image-placeholder) { display: inline-flex; flex-wrap: wrap; align-items: center; gap: 8px; max-width: 100%; padding: 8px 10px; margin: 8px 0; border: 1px dashed var(--border-strong); border-radius: 5px; color: var(--text-secondary); font: 400 var(--font-size-secondary)/1.6 var(--sans); }
.memo-content :deep(.memo-image-placeholder button) { padding: 4px 8px; border: 1px solid var(--border-strong); border-radius: 5px; background: var(--bg-card); color: var(--text-primary); font: inherit; cursor: pointer; }
.memo-content :deep(.memo-image-placeholder button:focus-visible) { outline: 2px solid var(--brand); outline-offset: 2px; }
.memo-content :deep(img) { display: block; max-width: 100%; max-height: 560px; object-fit: contain; }
</style>
