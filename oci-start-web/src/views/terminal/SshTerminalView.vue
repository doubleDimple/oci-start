<script setup lang="ts">
import { onUnmounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import PageHero from '@/components/PageHero.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import request from '@/api/request'

const route = useRoute()
const log = ref('')
let ws: WebSocket | null = null

async function connect() {
  const id = route.query.instanceId
  if (id) {
    await request.get(`/oci/ssh/config/${id}`).catch(() => undefined)
  }
  ws?.close()
  const proto = location.protocol === 'https:' ? 'wss' : 'ws'
  ws = new WebSocket(`${proto}://${location.host}/ws/ssh`)
  ws.onopen = () => { log.value += '\nconnected\n' }
  ws.onmessage = (e) => { log.value += typeof e.data === 'string' ? e.data : '' }
  ws.onclose = () => { log.value += '\nclosed\n' }
}

function send(ev: KeyboardEvent) {
  if (ev.key === 'Enter' && ws && ws.readyState === WebSocket.OPEN) {
    const line = (ev.target as HTMLInputElement).value + '\n'
    ws.send(line)
    ;(ev.target as HTMLInputElement).value = ''
  }
}

onUnmounted(() => ws?.close())
</script>
<template>
  <div>
    <PageHero title="SSH 终端" desc="WebSocket /ws/ssh，配置 GET /oci/ssh/config/{id}">
      <GhostBtn @click="ws?.close()">断开</GhostBtn>
      <PrimaryBtn @click="connect">连接</PrimaryBtn>
    </PageHero>
    <section class="term">
      <pre>{{ log }}</pre>
      <input placeholder="输入命令后回车" @keydown="send" />
    </section>
  </div>
</template>
<style scoped>
.term {
  background: #071016;
  color: #d7efe6;
  border-radius: 18px;
  min-height: 520px;
  padding: 16px;
  display: flex;
  flex-direction: column;
}
pre { flex: 1; overflow: auto; margin: 0 0 12px; }
input {
  border: 0; background: #102028; color: #fff; border-radius: 10px; padding: 10px 12px;
}
</style>
