import regionGlobe from './regions/globe'
import emailManagement from './email/management'
import emailCompose from './email/compose'
import storageManagement from './storage/management'
import storageUpload from './storage/upload'
import storagePreview from './storage/preview'
import tenantSecurity from './tenants/security'
import tenantRegions from './tenants/regions'
import tenantAudit from './tenants/audit'
import ociCost from './cost/oci'
import tenantTraffic from './monitor/traffic'
import metrics from './monitor/metrics'
import domainProviders from './settings/domainProviders'
import cloudflareDns from './dns/cloudflare'
import edgeoneDns from './dns/edgeone'
import vps from './vps/list'
import vpsDetails from './vps/resourceDetails'
import networkQuality from './settings/networkQuality'
import systemLogs from './settings/systemLogs'
import securitySettings from './settings/securitySettings'
import vpnProxy from './settings/vpnProxy'
import notificationSettings from './settings/notificationSettings'
import memos from './settings/memos'
import migration from './settings/migration'
import mfaBackup from './settings/mfaBackup'
import apiTokens from './settings/apiTokens'
import aiChat from './ai/chat'
import aiModels from './ai/models'
import delayTest from './tools/delayTest'
import openLogs from './boot/logs'
import instances from './instances/list'
import tenantInstances from './instances/tenantInstances'
import sshTerminal from './terminal/ssh'
import sftp from './terminal/sftp'
import vnc from './terminal/vnc'
import vnic from './network/vnic'
import vnicActions from './network/vnicActions'
import instanceOperations from './instances/operations'
import instanceNetwork from './instances/network'
import gcpInstances from './instances/gcp'
import ociBoot from './boot/oci'
import bootTasks from './boot/tasks'
import regionPage from './regions/page'
import tenant from './tenants/list'
import tenantIdentity from './tenants/identity'
import tenantImport from './tenants/import'
import tenantOperations from './tenants/operations'
import tenantResources from './tenants/resources'
import tenantSubscription from './tenants/subscriptions'
import { headerZh } from './header'
import { headerMessagesZh } from './headerMessages'
import { headerAssetsZh } from './headerAssets'
import { headerVersionZh } from './headerVersion'
import { auditLogsZh } from './auditLogs'
import { mobileTenantToolsMessages } from './mobileTenantTools'
import { mobileShellMessages } from './mobileShell'
import { mobileRecordsMessages } from './mobileRecords'

export default {
  auditLogs: auditLogsZh,
  mobileRecords: mobileRecordsMessages.zh,
  mobileTenantTools: mobileTenantToolsMessages.zh,
  mobileShell: mobileShellMessages.zh,
  pageLoading: { loading: '加载中…', failed: '页面加载失败', retry: '重新加载' },
  pageError: { title: '错误详情', open: '出现错误，点击查看详情', close: '关闭错误详情' },
  pagePagination: { label: '分页', previous: '上一页', next: '下一页', pageSize: '每页条数', perPage: '{count}条/页' },
  emailManagement: emailManagement.zh,
  emailCompose: emailCompose.zh,
  storageManagement: storageManagement.zh,
  storageUpload: storageUpload.zh,
  storagePreview: storagePreview.zh,
  pageBack: '返回',
  tenantSecurity: tenantSecurity.zh,
  tenantRegions: tenantRegions.zh,
  tenantAudit: tenantAudit.zh,
  ociCost: ociCost.zh,
  tenantTraffic: tenantTraffic.zh,
  metrics: metrics.zh,
  domainProviders: domainProviders.zh,
  cloudflareDns: cloudflareDns.zh,
  edgeoneDns: edgeoneDns.zh,
  vps: vps.zh,
  vpsDetails: vpsDetails.zh,
  networkQuality: networkQuality.zh,
  systemLogs: systemLogs.zh,
  securitySettings: securitySettings.zh,
  vpnProxy: vpnProxy.zh,
  notificationSettings: notificationSettings.zh,
  memo: memos.zh,
  migration: migration.zh,
  mfaBackup: mfaBackup.zh,
  apiTokens: apiTokens.zh,
  aiChat: aiChat.zh,
  aiModels: aiModels.zh,
  delayTest: delayTest.zh,
  openLogs: openLogs.zh,
  instances: instances.zh,
  tenantInstances: tenantInstances.zh,
  sshTerminal: sshTerminal.zh,
  sftp: sftp.zh,
  vnc: vnc.zh,
  vnic: vnic.zh,
  vnicActions: vnicActions.zh,
  instanceOperations: instanceOperations.zh,
  instanceNetwork: instanceNetwork.zh,
  gcpInstances: gcpInstances.zh,
  header: headerZh,
  headerMessages: headerMessagesZh,
  headerAssets: headerAssetsZh,
  headerVersion: headerVersionZh,
  ociBoot: ociBoot.zh,
  bootTasks: bootTasks.zh,
  regionGlobe: regionGlobe.zh,
  regionPage: regionPage.zh,
  tenant: tenant.zh,
  tenantIdentity: tenantIdentity.zh,
  tenantImport: tenantImport.zh,
  tenantOperations: tenantOperations.zh,
  tenantResources: tenantResources.zh,
  tenantSubscription: tenantSubscription.zh,
  brand: 'OCI-START',
  brandSub: 'Build. Track. Grow.',
  searchMenu: '搜索菜单、页面…',
  welcomeBack: '欢迎回来',
  goodToSee: '很高兴见到你，{name}',
  happening: '这是当前账号和本机资源的实时概况。',
  currentFocus: '当前主机',
  viewMonitor: '查看监控',
  quote: '小步推进，才能堆出大结果。',
  keepGoing: 'KEEP GOING',
  keepGoingBody: '今天的每一次操作，都在为下一台实例铺路。',
  newTenant: '新建租户',
  quickActions: '快捷操作',
  recentActivity: '系统状态',
  viewAll: '查看全部',
  logout: '退出登录',
  about: '关于项目',
  themeDark: '暗色',
  themeLight: '浅色',
  chrome: {
    title: '外观与换肤',
    subtitle: '定制企业级侧边栏、内容区域及容器层级配色',
    modeTitle: '主题模式',
    sidebarTitle: '侧边栏风格',
    contentTitle: '内容区域与卡片皮肤',
    contentDesc: '切换底色与容器层级，整站卡片、表格与输入框自动适配',
    sidebar: '侧栏背景',
    page: '内容区配色',
    reset: '恢复默认主题',
    resetTip: '已恢复默认外观设置',
    customPicker: '自定义取色',
    customHint: '智能色彩引擎将自动为卡片、容器、输入框与边框计算协调层级，告别卡片融为一体或灰暗无对比的问题',
    sidebarObsidian: '经典暗黑',
    sidebarBlack: '曜石纯黑',
    sidebarForest: 'OCI 墨绿',
    sidebarNavy: '科技深蓝',
    sidebarEspresso: '沉稳深咖',
    sidebarLight: '极简素白',
    presetSlate: '经典冷灰',
    presetPure: '极简纯雪',
    presetAzure: '科技蓝灰',
    presetIvory: '温润暖米',
    presetMidnight: '暗夜极客',
    presetOnyx: '曜石极黑',
    presetAurora: '极光墨夜',
    presetCustom: '自定义皮肤',
  },
  cloudSwitch: '切换云厂商',
  noMenu: '无匹配菜单',
  comingSoon: '即将推出',
  dashboard: {
    yearUnit: '年', dayUnit: '天', hourUnit: '时', minuteUnit: '分',
    pageTitle: '系统监控',
    loading: '加载中...',
    apiTotal: '总API数',
    bootInstances: '总Boot实例数',
    attemptTotal: '总抢机次数',
    attemptSuccess: '抢机成功次数',
    attemptFail: '抢机失败次数',
    cpuTitle: 'CPU信息',
    cpuPhysical: '物理核心',
    cpuLogical: '逻辑核心',
    cpuTemp: 'CPU温度',
    cpuFreq: '主频',
    memTitle: '内存使用',
    memTotal: '总内存',
    memUsed: '已用内存',
    memAvailable: '可用内存',
    memSwap: '交换空间',
    sysTitle: '系统信息',
    sysOs: '操作系统',
    sysArch: '系统架构',
    sysUptime: '运行时间',
    sysProcesses: '进程数',
    sysThreads: '线程数',
    netTitle: '网络流量',
    netSubtitle: '实时流量监控',
    netUp: '上传速度',
    netDown: '下载速度',
    netTotalUp: '总发送',
    netTotalDown: '总接收',
    diskTitle: '磁盘使用',
    diskSubtitle: '存储状态监控',
    diskTotal: '总容量',
    diskUsed: '已用空间',
    diskFree: '可用空间',
    diskIo: '读写速度',
  },
  arm: {
    pageTitle: '开机区域监控',
    loading: '加载中...',
    statsTotal: '总区域数',
    statsOpen: '已开ARM架构区域数',
    statsToday: '今日新开机区域数',
    mapCount: '数量',
    mapAll: 'ARM放货区域',
    mapMine: '我的区域',
    mapShow: '显示地图',
    mapHide: '隐藏地图',
    searchPlaceholder: '搜索区域...',
    filterContinentAll: '全部大洲',
    filterContinentAsia: '亚太地区',
    filterContinentEurope: '欧洲',
    filterContinentNa: '北美',
    filterContinentSa: '南美',
    filterContinentMe: '中东/非洲',
    filterStatusAll: '全部状态',
    filterStatusOpen: '已开机',
    filterStatusClosed: '未放货',
    colStatus: '状态',
    colCode: '区域代码',
    colName: '区域名称',
    colArch: '架构类型',
    colOpenTime: '开机时间',
    colTotal: '总开机数量',
    colMonth: '当月开机数量',
    colLast: '最后开机时间',
    badgeOpen: '已放货',
    badgeClosed: '未放货',
    empty: '没有找到匹配的区域',
    popupCode: '区域代码:',
    popupStatus: '状态:',
    popupArch: '架构类型:',
    popupTotal: '总开机数量:',
    popupMonth: '当月开机数量:',
    popupOpenTime: '开机时间:',
    popupLast: '最后开机时间:',
  },
  nav: {
    service: '服务管理',
    monitor: '系统资源监控',
    regions: 'OCI 区域管理',
    tenants: 'OCI 租户管理',
    instances: 'OCI 实例列表',
    email: 'OCI 邮箱服务',
    storage: 'OCI 对象存储',
    boot: 'OCI 开机管理',
    ai: 'OCI AI 管理',
    speed: 'OCI延迟测试',
    openLog: 'OCI 开机日志',
    gcpAccounts: 'GCP 账号管理',
    gcpInstances: 'GCP 实例管理',
    azureVms: 'Azure 虚拟机',
    azureResources: 'Azure 资源组',
    azureStorage: 'Azure 存储',
    azureNetworks: 'Azure 网络',
    awsEc2: 'EC2 实例',
    awsS3: 'S3 存储',
    awsLambda: 'Lambda 函数',
    awsRds: 'RDS 数据库',
    proxy: '代理管理',
    keyConfig: '密钥配置',
    cf: 'CF 管理',
    eo: 'EO 管理',
    nginx: 'Nginx 管理',
    vps: '资源管理',
    vpsList: '资源列表',
    system: '系统管理',
    quality: '网络质量',
    logs: '系统日志',
    security: '安全管理',
    proxyConfig: '代理配置',
    tools: '我的工具',
    notify: '通知管理',
    notes: '笔记管理',
    migration: '数据迁移',
    mfa: 'MFA 备份',
    dev: '开发配置',
    token: 'Token 配置',
  },
}
