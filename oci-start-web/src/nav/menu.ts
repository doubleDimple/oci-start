export interface NavItem {
  id: string
  href: string
  labelKey: string
  icon: string
  cloudTypes?: number[]
  newTab?: boolean
}

export interface NavGroup {
  id: string
  labelKey: string
  children: NavItem[]
}

export const MENU: NavGroup[] = [
  {
    id: 'service',
    labelKey: 'nav.service',
    children: [
      { id: 'api-dashboard', href: '/boot/dashboard', labelKey: 'nav.monitor', icon: 'i-mdi-view-dashboard-outline' },
      { id: 'api-records', href: '/resource/list', labelKey: 'nav.regions', icon: 'i-mdi-earth', cloudTypes: [1] },
      { id: 'api-management', href: '/tenants/list', labelKey: 'nav.tenants', icon: 'i-mdi-account-group-outline', cloudTypes: [1] },
      { id: 'api-ociMachineList', href: '/oci/list', labelKey: 'nav.instances', icon: 'i-mdi-server', cloudTypes: [1] },
      { id: 'oci-email-management', href: '/email/management', labelKey: 'nav.email', icon: 'i-mdi-email-outline', cloudTypes: [1] },
      { id: 'oci-object-storage', href: '/oci/storage/page', labelKey: 'nav.storage', icon: 'i-mdi-database-outline', cloudTypes: [1] },
      { id: 'api-fullBootList', href: '/boot/fullBootList', labelKey: 'nav.boot', icon: 'i-mdi-play-circle-outline', cloudTypes: [1] },
      { id: 'ai-models', href: '/system/ai/models', labelKey: 'nav.ai', icon: 'i-mdi-brain', cloudTypes: [1] },
      { id: 'api-delayTest', href: '/delayTest', labelKey: 'nav.speed', icon: 'i-mdi-speedometer', cloudTypes: [1] },
      { id: 'api-openLog', href: '/system/openLogs', labelKey: 'nav.openLog', icon: 'i-mdi-text-box-search-outline', cloudTypes: [1], newTab: true },
      { id: 'gcp-accounts', href: '/tenants/list', labelKey: 'nav.gcpAccounts', icon: 'i-mdi-google', cloudTypes: [2] },
      { id: 'api-ociBootList', href: '/other/instances/list', labelKey: 'nav.gcpInstances', icon: 'i-mdi-server', cloudTypes: [2] },
      { id: 'azure-vms', href: '/azure/vms', labelKey: 'nav.azureVms', icon: 'i-mdi-microsoft', cloudTypes: [3] },
      { id: 'azure-resources', href: '/azure/resources', labelKey: 'nav.azureResources', icon: 'i-mdi-folder-outline', cloudTypes: [3] },
      { id: 'azure-storage', href: '/azure/storage', labelKey: 'nav.azureStorage', icon: 'i-mdi-harddisk', cloudTypes: [3] },
      { id: 'azure-networks', href: '/azure/networks', labelKey: 'nav.azureNetworks', icon: 'i-mdi-lan', cloudTypes: [3] },
      { id: 'aws-ec2', href: '/aws/ec2', labelKey: 'nav.awsEc2', icon: 'i-mdi-aws', cloudTypes: [4] },
      { id: 'aws-s3', href: '/aws/s3', labelKey: 'nav.awsS3', icon: 'i-mdi-cloud-outline', cloudTypes: [4] },
      { id: 'aws-lambda', href: '/aws/lambda', labelKey: 'nav.awsLambda', icon: 'i-mdi-lambda', cloudTypes: [4] },
      { id: 'aws-rds', href: '/aws/rds', labelKey: 'nav.awsRds', icon: 'i-mdi-database-outline', cloudTypes: [4] },
    ],
  },
  {
    id: 'proxy',
    labelKey: 'nav.proxy',
    children: [
      { id: 'domain-settings', href: '/system/domainSettings', labelKey: 'nav.keyConfig', icon: 'i-mdi-key-outline' },
      { id: 'cloudflare-servers', href: '/dns/cloudflare', labelKey: 'nav.cf', icon: 'i-mdi-earth' },
      { id: 'edgeOne-servers', href: '/dns/edgeone', labelKey: 'nav.eo', icon: 'i-mdi-earth' },
    ],
  },
  {
    id: 'vps',
    labelKey: 'nav.vps',
    children: [
      { id: 'vps-instances', href: '/vps/instances/list', labelKey: 'nav.vpsList', icon: 'i-mdi-format-list-bulleted' },
    ],
  },
  {
    id: 'system',
    labelKey: 'nav.system',
    children: [
      { id: 'ip-settings', href: '/system/ipSettings', labelKey: 'nav.quality', icon: 'i-mdi-shield-check-outline', cloudTypes: [1] },
      { id: 'api-logs', href: '/system/logs', labelKey: 'nav.logs', icon: 'i-mdi-file-document-outline', newTab: true },
      { id: 'api-settings', href: '/system/settings', labelKey: 'nav.security', icon: 'i-mdi-tune' },
      { id: 'vpnProxy-management', href: '/vpnProxy/page', labelKey: 'nav.proxyConfig', icon: 'i-mdi-swap-horizontal' },
    ],
  },
  {
    id: 'tools',
    labelKey: 'nav.tools',
    children: [
      { id: 'api-notifySettings', href: '/system/notifySettings', labelKey: 'nav.notify', icon: 'i-mdi-bell-outline' },
      { id: 'api-memPage', href: '/system/memPage', labelKey: 'nav.notes', icon: 'i-mdi-notebook-outline' },
      { id: 'api-migPage', href: '/migration/migPage', labelKey: 'nav.migration', icon: 'i-mdi-database-sync-outline' },
      { id: 'api-mfa', href: '/mfa/page', labelKey: 'nav.mfa', icon: 'i-mdi-cellphone-key' },
    ],
  },
  {
    id: 'dev',
    labelKey: 'nav.dev',
    children: [
      { id: 'api-tokens', href: '/system/apiTokens', labelKey: 'nav.token', icon: 'i-mdi-key-outline' },
    ],
  },
]

export const PROVIDERS = [
  { type: 1, name: 'Oracle Cloud' },
  { type: 2, name: 'Google Cloud' },
  { type: 3, name: 'Azure Cloud' },
  { type: 4, name: 'Amazon Cloud' },
] as const
