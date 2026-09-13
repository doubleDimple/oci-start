<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import PageHero from '@/components/PageHero.vue'
import ListCard from '@/components/ListCard.vue'
import PrimaryBtn from '@/components/PrimaryBtn.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import request from '@/api/request'

const rows = ref<any[]>([])
const total = ref(0)
const page = ref(1)
const form = ref({ name: '', host: '', port: '', username: '', password: '' })

async function load() {
  const res: any = await request.post('/vpnProxy/pageList', { pageNum: page.value, pageSize: 10 })
  const data = res?.data || res
  rows.value = data.content || data.records || data.list || []
  total.value = Number(data.totalElements || data.total || rows.value.length)
}
onMounted(load)

async function save() {
  await request.post('/vpnProxy/saveOrUpdate', form.value)
  ElMessage.success('已保存')
  load()
}
async function remove(row: any) {
  await ElMessageBox.confirm('删除该代理？', '确认', { type: 'warning' })
  await request.post('/vpnProxy/delete', { id: row.id })
  load()
}
</script>
<template>
  <div>
    <PageHero title="代理配置" desc="POST /vpnProxy/pageList，保存禁止改查询逻辑。">
      <GhostBtn @click="load">刷新</GhostBtn>
    </PageHero>
    <ListCard>
      <template #toolbar>
        <el-input v-model="form.name" placeholder="名称" style="width:140px" />
        <el-input v-model="form.host" placeholder="Host" style="width:160px" />
        <el-input v-model="form.port" placeholder="Port" style="width:90px" />
        <PrimaryBtn @click="save">保存</PrimaryBtn>
      </template>
      <el-table :data="rows" height="480">
        <el-table-column prop="name" label="名称" />
        <el-table-column prop="host" label="Host" />
        <el-table-column prop="port" label="Port" width="90" />
        <el-table-column prop="availableStatus" label="状态" width="100" />
        <el-table-column label="操作" width="120">
          <template #default="{ row }">
            <el-button link type="danger" @click="remove(row)">删除</el-button>
          </template>
        </el-table-column>
      </el-table>
    </ListCard>
  </div>
</template>
