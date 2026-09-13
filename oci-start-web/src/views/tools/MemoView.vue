<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { ElMessage } from 'element-plus'
import PageHero from '@/components/PageHero.vue'
import ListCard from '@/components/ListCard.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import request from '@/api/request'
const rows = ref<any[]>([])
const title = ref('')
const content = ref('')
async function load() {
  const res: any = await request.get('/api/memos')
  rows.value = res?.data || res || []
}
onMounted(load)
async function save() {
  await request.post('/api/memos', { title: title.value, content: content.value })
  ElMessage.success('已保存')
  title.value = ''
  content.value = ''
  load()
}
</script>
<template>
  <div>
    <PageHero title="笔记" desc="CRUD /api/memos">
      <PrimaryBtn @click="save">保存</PrimaryBtn>
    </PageHero>
    <ListCard>
      <el-input v-model="title" placeholder="标题" style="margin-bottom:8px" />
      <el-input v-model="content" type="textarea" :rows="4" placeholder="内容" />
      <el-table :data="Array.isArray(rows) ? rows : []" style="margin-top:16px">
        <el-table-column prop="title" label="标题" />
        <el-table-column prop="content" label="内容" />
      </el-table>
    </ListCard>
  </div>
</template>
