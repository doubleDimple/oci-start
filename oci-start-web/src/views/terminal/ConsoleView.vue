<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import PageHero from '@/components/PageHero.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import request from '@/api/request'

const route = useRoute()
const info = ref<any>({})
onMounted(async () => {
  const id = route.params.instanceId
  if (id) {
    info.value = await request.post('/oci/console/create', { instanceId: id }).catch(() => ({}))
  }
})
</script>
<template>
  <div>
    <PageHero title="实例控制台" desc="POST /oci/console/create，VNC URL 规则与旧 console_terminal 一致。">
      <PrimaryBtn @click="info = {}">重连</PrimaryBtn>
    </PageHero>
    <section class="canvas">
      <p>instanceId: {{ route.params.instanceId }}</p>
      <pre>{{ JSON.stringify(info, null, 2) }}</pre>
    </section>
  </div>
</template>
<style scoped>
.canvas {
  background: #05080b;
  color: #9ad7c4;
  min-height: 520px;
  border-radius: 18px;
  padding: 20px;
}
</style>
