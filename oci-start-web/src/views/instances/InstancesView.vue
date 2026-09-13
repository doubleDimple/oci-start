<script setup lang="ts">
import { onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage, ElMessageBox } from 'element-plus'
import PageHero from '@/components/PageHero.vue'
import ListCard from '@/components/ListCard.vue'
import GhostBtn from '@/components/GhostBtn.vue'
import { usePagedQuery } from '@/composables/usePagedQuery'
import request from '@/api/request'

const route = useRoute()
const router = useRouter()
const q = usePagedQuery('/oci/list/json')

function extra() {
  return { tenantId: route.query.tenantId || undefined }
}

onMounted(() => q.load(extra()))

async function act(url: string, row: any, label: string) {
  await ElMessageBox.confirm(`${label} ${row.displayName || row.instanceId}？`, '确认')
  await request.post(url, { instanceId: row.instanceId, tenantId: row.tenantId })
  ElMessage.success('已提交')
  q.load(extra())
}
</script>
<template>
  <div>
    <PageHero title="实例列表" desc="GET /oci/list/json，电源操作走原 POST。">
      <GhostBtn @click="q.load(extra())">刷新</GhostBtn>
    </PageHero>
    <ListCard>
      <el-table :data="q.rows" v-loading="q.loading" height="560">
        <el-table-column prop="displayName" label="名称" min-width="140" />
        <el-table-column prop="state" label="状态" width="110" />
        <el-table-column prop="shape" label="Shape" min-width="140" />
        <el-table-column label="规格" width="120">
          <template #default="{ row }">{{ row.ocpus }}C / {{ row.memoryInGBs }}G</template>
        </el-table-column>
        <el-table-column prop="publicIps" label="公网 IP" min-width="140" />
        <el-table-column prop="privateIps" label="私网 IP" min-width="140" />
        <el-table-column prop="tenancyName" label="租户" min-width="120" />
        <el-table-column label="操作" width="280" fixed="right">
          <template #default="{ row }">
            <el-button link type="primary" @click="act('/oci/startInstance', row, '启动')">启动</el-button>
            <el-button link @click="act('/oci/stopInstance', row, '停止')">停止</el-button>
            <el-button link @click="router.push({ path: '/oci/terminal', query: { instanceId: row.id } })">SSH</el-button>
            <el-button link @click="router.push('/oci/console/terminal/' + row.id)">控制台</el-button>
            <el-button link type="danger" @click="act('/oci/terminateInstance', row, '终止')">终止</el-button>
          </template>
        </el-table-column>
      </el-table>
      <template #footer>
        <el-pagination background layout="total, prev, pager, next, sizes" :total="q.total"
          v-model:current-page="q.page" v-model:page-size="q.size" :page-sizes="[10,20,50]"
          @current-change="q.load(extra())" @size-change="q.load(extra())" />
      </template>
    </ListCard>
  </div>
</template>
