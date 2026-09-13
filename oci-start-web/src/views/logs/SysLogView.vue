<script setup lang="ts">
import { onMounted, onUnmounted, ref } from 'vue'
import PageHero from '@/components/PageHero.vue'
import ListCard from '@/components/ListCard.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import request from '@/api/request'

const props = defineProps<{ boot?: boolean }>()
const lines = ref<string[]>([])
let es: EventSource | null = null

async function load() {
  const url = props.boot ? '/system/openLogs/json' : '/system/logs/json'
  const res: any = await request.get(url, { params: { lines: 300 } })
  const body = res?.data || res
  lines.value = body.content || body.lines || body.logLines || []
}

function connectSse() {
  es?.close()
  es = new EventSource(`/system/streamLogs?isBootLog=${props.boot ? 'true' : 'false'}`)
  es.onmessage = (e) => {
    if (e.data) lines.value = [...lines.value, e.data].slice(-800)
  }
}

onMounted(() => { load(); connectSse() })
onUnmounted(() => es?.close())
</script>
<template>
  <div>
    <PageHero :title="boot ? '开机日志' : '系统日志'" desc="JSON 历史 + SSE /system/streamLogs">
      <GhostBtn @click="load">刷新历史</GhostBtn>
    </PageHero>
    <ListCard>
      <pre class="log">{{ lines.join('\n') }}</pre>
    </ListCard>
  </div>
</template>
<style scoped>
.log {
  margin: 0;
  min-height: 480px;
  max-height: 62vh;
  overflow: auto;
  background: #0e161c;
  color: #d7efe6;
  border-radius: 14px;
  padding: 16px;
  font-size: 12px;
  line-height: 1.55;
}
</style>
