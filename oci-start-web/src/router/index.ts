import { createRouter, createWebHistory, type RouteRecordRaw } from 'vue-router'
import { finishProgress, startProgress } from '@/utils/progress'

const layout = () => import('@/layouts/DefaultLayout.vue')

const children: RouteRecordRaw[] = [
  { path: 'boot/dashboard', meta: { title: '系统资源监控', id: 'api-dashboard' }, component: () => import('@/views/dashboard/DashboardView.vue') },
  { path: 'resource/list', meta: { title: 'OCI 区域管理', id: 'api-records' }, component: () => import('@/views/regions/ArmRegionsView.vue') },
  { path: 'tenants/list', meta: { title: 'OCI 租户管理', id: 'api-management' }, component: () => import('@/views/tenants/TenantsView.vue') },
  { path: 'tenants/regionList', meta: { title: '区域列表', id: 'api-management' }, component: () => import('@/views/tenants/TenantRegionsView.vue') },
  { path: 'tenants/regionSubList', meta: { title: '区域订阅', id: 'api-management' }, component: () => import('@/views/tenants/RegionSubView.vue') },
  { path: 'tenants/addSpeed', meta: { title: 'API 导入', id: 'api-management' }, component: () => import('@/views/tenants/TenantImportView.vue') },
  { path: 'tenants/bootPage', meta: { title: '添加开机', id: 'api-fullBootList' }, component: () => import('@/views/boot/AddBootView.vue') },
  { path: 'tenants/gcpBootPage', meta: { title: 'GCP 开机', id: 'api-ociBootList' }, component: () => import('@/views/boot/GcpAddBootView.vue') },
  { path: 'tenants/bootList', meta: { title: '开机任务', id: 'api-fullBootList' }, component: () => import('@/views/boot/BootListView.vue') },
  { path: 'oci/list', meta: { title: 'OCI 实例列表', id: 'api-ociMachineList' }, component: () => import('@/views/instances/InstancesView.vue') },
  { path: 'email/management', meta: { title: 'OCI 邮箱服务', id: 'oci-email-management' }, component: () => import('@/views/email/EmailView.vue') },
  { path: 'oci/storage/page', meta: { title: '对象存储', id: 'oci-object-storage' }, component: () => import('@/views/storage/StorageView.vue') },
  { path: 'boot/fullBootList', meta: { title: 'OCI 开机管理', id: 'api-fullBootList' }, component: () => import('@/views/boot/BootListView.vue') },
  { path: 'system/ai/models', meta: { title: 'OCI AI 管理', id: 'ai-models' }, component: () => import('@/views/ai/AiModelsView.vue') },
  { path: 'delayTest', meta: { title: '延迟测试', id: 'api-delayTest' }, component: () => import('@/views/tools/SpeedTestView.vue') },
  { path: 'system/openLogs', meta: { title: '开机日志', id: 'api-openLog' }, component: () => import('@/views/logs/OpenLogsView.vue') },
  { path: 'other/instances/list', meta: { title: 'GCP 实例', id: 'api-ociBootList' }, component: () => import('@/views/gcp/GcpInstancesView.vue') },
  { path: 'azure/vms', meta: { title: 'Azure 虚拟机' }, component: () => import('@/views/common/ComingSoonView.vue') },
  { path: 'azure/resources', meta: { title: 'Azure 资源组' }, component: () => import('@/views/common/ComingSoonView.vue') },
  { path: 'azure/storage', meta: { title: 'Azure 存储' }, component: () => import('@/views/common/ComingSoonView.vue') },
  { path: 'azure/networks', meta: { title: 'Azure 网络' }, component: () => import('@/views/common/ComingSoonView.vue') },
  { path: 'aws/ec2', meta: { title: 'EC2' }, component: () => import('@/views/common/ComingSoonView.vue') },
  { path: 'aws/s3', meta: { title: 'S3' }, component: () => import('@/views/common/ComingSoonView.vue') },
  { path: 'aws/lambda', meta: { title: 'Lambda' }, component: () => import('@/views/common/ComingSoonView.vue') },
  { path: 'aws/rds', meta: { title: 'RDS' }, component: () => import('@/views/common/ComingSoonView.vue') },
  { path: 'system/domainSettings', meta: { title: '密钥配置', id: 'domain-settings' }, component: () => import('@/views/settings/DomainSettingsView.vue') },
  { path: 'dns/cloudflare', meta: { title: 'CF 管理', id: 'cloudflare-servers' }, component: () => import('@/views/dns/CloudflareView.vue') },
  { path: 'dns/edgeone', meta: { title: 'EO 管理', id: 'edgeOne-servers' }, component: () => import('@/views/dns/EdgeOneView.vue') },
  { path: 'ssl/nginx/management', meta: { title: 'Nginx 管理', id: 'nginx-management' }, component: () => import('@/views/nginx/NginxView.vue') },
  { path: 'vps/instances/list', meta: { title: '资源列表', id: 'vps-instances' }, component: () => import('@/views/vps/VpsListView.vue') },
  { path: 'system/ipSettings', meta: { title: '质量管理', id: 'ip-settings' }, component: () => import('@/views/settings/IpSettingsView.vue') },
  { path: 'system/logs', meta: { title: '系统日志', id: 'api-logs' }, component: () => import('@/views/logs/SysLogView.vue') },
  { path: 'system/settings', meta: { title: '安全管理', id: 'api-settings' }, component: () => import('@/views/settings/SecuritySettingsView.vue') },
  { path: 'vpnProxy/page', meta: { title: '代理配置', id: 'vpnProxy-management' }, component: () => import('@/views/vpn/VpnProxyView.vue') },
  { path: 'system/notifySettings', meta: { title: '通知管理', id: 'api-notifySettings' }, component: () => import('@/views/settings/NotifySettingsView.vue') },
  { path: 'system/memPage', meta: { title: '笔记管理', id: 'api-memPage' }, component: () => import('@/views/tools/MemoView.vue') },
  { path: 'migration/migPage', meta: { title: '数据迁移', id: 'api-migPage' }, component: () => import('@/views/tools/MigrationView.vue') },
  { path: 'mfa/page', meta: { title: 'MFA 备份', id: 'api-mfa' }, component: () => import('@/views/tools/MfaView.vue') },
  { path: 'system/apiTokens', meta: { title: 'Token 配置', id: 'api-tokens' }, component: () => import('@/views/settings/ApiTokensView.vue') },
  { path: 'oci/terminal', meta: { title: 'SSH 终端', id: 'api-ociMachineList' }, component: () => import('@/views/terminal/SshTerminalView.vue') },
  { path: 'ssh/terminal', meta: { title: 'SSH 终端' }, component: () => import('@/views/terminal/SshTerminalView.vue') },
  { path: 'oci/sysHelp', meta: { title: '系统救援' }, component: () => import('@/views/terminal/RescueView.vue') },
  { path: 'oci/metricsPage', meta: { title: '监控' }, component: () => import('@/views/monitor/MetricsView.vue') },
  { path: 'instanceDetail/bootList', meta: { title: '租户实例' }, component: () => import('@/views/instances/InstancesView.vue') },
  { path: 'cost/costPage', meta: { title: '费用' }, component: () => import('@/views/cost/CostView.vue') },
  { path: 'monitor/homePage', meta: { title: '流量监控' }, component: () => import('@/views/monitor/TrafficView.vue') },
  { path: 'oci/vnic/manage', meta: { title: '网络管理' }, component: () => import('@/views/network/VnicView.vue') },
  { path: 'oci/console/terminal/:instanceId?', meta: { title: '控制台' }, component: () => import('@/views/terminal/ConsoleView.vue') },
  { path: 'ai/chat', meta: { title: 'AI 对话' }, component: () => import('@/views/ai/ChatView.vue') },
]

const router = createRouter({
  history: createWebHistory('/'),
  routes: [
    { path: '/index', component: () => import('@/views/welcome/WelcomeView.vue') },
    {
      path: '/',
      component: layout,
      redirect: '/boot/dashboard',
      children,
    },
    { path: '/main', redirect: (to) => ({ path: String(to.query.path || '/boot/dashboard'), query: {} }) },
    { path: '/index.html', redirect: '/boot/dashboard' },
  ],
})

router.beforeEach(() => {
  startProgress()
  return true
})
router.afterEach(() => finishProgress())
router.onError(() => finishProgress())

export default router
