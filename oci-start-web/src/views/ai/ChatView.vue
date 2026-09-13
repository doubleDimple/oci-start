<script setup lang="ts">
import { ref } from 'vue'
import { useRoute } from 'vue-router'
import PageHero from '@/components/PageHero.vue'
import ListCard from '@/components/ListCard.vue'
const route = useRoute()
const text = ref('')
</script>
<template>
  <div>
    <PageHero title="AI 对话" :desc="`/ws/aiChat · tenantId=${route.query.tenantId || ''}`" />
    <ListCard>
      <el-input v-model="text" type="textarea" :rows="6" placeholder="消息走原 WebSocket /ws/aiChat" />
    </ListCard>
  </div>
</template>
