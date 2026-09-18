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
import { headerEn } from './header'
import { headerMessagesEn } from './headerMessages'
import { headerAssetsEn } from './headerAssets'
import { headerVersionEn } from './headerVersion'
import { mobileTenantToolsMessages } from './mobileTenantTools'
import { mobileShellMessages } from './mobileShell'
import { mobileRecordsMessages } from './mobileRecords'

export default {
  mobileRecords: mobileRecordsMessages.en,
  mobileTenantTools: mobileTenantToolsMessages.en,
  mobileShell: mobileShellMessages.en,
  pageLoading: { loading: 'Loading…', failed: 'Unable to load page', retry: 'Reload' },
  pageError: { title: 'Error details', open: 'An error occurred. Open details', close: 'Close error details' },
  pagePagination: { label: 'Pagination', previous: 'Previous page', next: 'Next page', pageSize: 'Items per page', perPage: '{count}/page' },
  emailManagement: emailManagement.en,
  emailCompose: emailCompose.en,
  storageManagement: storageManagement.en,
  storageUpload: storageUpload.en,
  storagePreview: storagePreview.en,
  pageBack: 'Back',
  tenantSecurity: tenantSecurity.en,
  tenantRegions: tenantRegions.en,
  tenantAudit: tenantAudit.en,
  ociCost: ociCost.en,
  tenantTraffic: tenantTraffic.en,
  metrics: metrics.en,
  domainProviders: domainProviders.en,
  cloudflareDns: cloudflareDns.en,
  edgeoneDns: edgeoneDns.en,
  vps: vps.en,
  vpsDetails: vpsDetails.en,
  networkQuality: networkQuality.en,
  systemLogs: systemLogs.en,
  securitySettings: securitySettings.en,
  vpnProxy: vpnProxy.en,
  notificationSettings: notificationSettings.en,
  memo: memos.en,
  migration: migration.en,
  mfaBackup: mfaBackup.en,
  apiTokens: apiTokens.en,
  aiChat: aiChat.en,
  aiModels: aiModels.en,
  delayTest: delayTest.en,
  openLogs: openLogs.en,
  instances: instances.en,
  tenantInstances: tenantInstances.en,
  sshTerminal: sshTerminal.en,
  sftp: sftp.en,
  vnc: vnc.en,
  vnic: vnic.en,
  vnicActions: vnicActions.en,
  instanceOperations: instanceOperations.en,
  instanceNetwork: instanceNetwork.en,
  gcpInstances: gcpInstances.en,
  header: headerEn,
  headerMessages: headerMessagesEn,
  headerAssets: headerAssetsEn,
  headerVersion: headerVersionEn,
  ociBoot: ociBoot.en,
  bootTasks: bootTasks.en,
  regionGlobe: regionGlobe.en,
  regionPage: regionPage.en,
  tenant: tenant.en,
  tenantIdentity: tenantIdentity.en,
  tenantImport: tenantImport.en,
  tenantOperations: tenantOperations.en,
  tenantResources: tenantResources.en,
  tenantSubscription: tenantSubscription.en,
  brand: 'OCI-START',
  brandSub: 'Build. Track. Grow.',
  searchMenu: 'Search menus or pages…',
  welcomeBack: 'WELCOME BACK',
  goodToSee: 'Good to see you, {name}',
  happening: 'Here is what is happening on this host today.',
  currentFocus: 'CURRENT HOST',
  viewMonitor: 'View monitor',
  quote: 'Small steps create big results.',
  keepGoing: 'KEEP GOING',
  keepGoingBody: 'The work you do today builds the instance you need tomorrow.',
  newTenant: 'New tenant',
  quickActions: 'Quick Actions',
  recentActivity: 'System status',
  viewAll: 'View all',
  logout: 'Sign out',
  about: 'About',
  themeDark: 'Dark',
  themeLight: 'Light',
  chrome: {
    title: 'Appearance',
    sidebar: 'Sidebar',
    page: 'Content palette',
    reset: 'Reset',
  },
  cloudSwitch: 'Cloud provider',
  noMenu: 'No matching menu',
  comingSoon: 'Coming soon',
  dashboard: {
    yearUnit: 'y', dayUnit: 'd', hourUnit: 'h', minuteUnit: 'm',
    pageTitle: 'System monitor',
    loading: 'Loading...',
    apiTotal: 'API calls',
    bootInstances: 'Boot instances',
    attemptTotal: 'Boot attempts',
    attemptSuccess: 'Successful attempts',
    attemptFail: 'Failed attempts',
    cpuTitle: 'CPU',
    cpuPhysical: 'Physical cores',
    cpuLogical: 'Logical cores',
    cpuTemp: 'Temperature',
    cpuFreq: 'Frequency',
    memTitle: 'Memory',
    memTotal: 'Total',
    memUsed: 'Used',
    memAvailable: 'Available',
    memSwap: 'Swap',
    sysTitle: 'System',
    sysOs: 'OS',
    sysArch: 'Arch',
    sysUptime: 'Uptime',
    sysProcesses: 'Processes',
    sysThreads: 'Threads',
    netTitle: 'Network',
    netSubtitle: 'Live throughput',
    netUp: 'Upload',
    netDown: 'Download',
    netTotalUp: 'Total sent',
    netTotalDown: 'Total received',
    diskTitle: 'Disk',
    diskSubtitle: 'Storage',
    diskTotal: 'Total',
    diskUsed: 'Used',
    diskFree: 'Free',
    diskIo: 'IO',
  },
  arm: {
    pageTitle: 'ARM Architecture Supply Monitor',
    loading: 'Loading...',
    statsTotal: 'Total Regions',
    statsOpen: 'ARM Enabled Regions',
    statsToday: 'New Success Today',
    mapCount: 'Count',
    mapAll: 'All ARM Regions',
    mapMine: 'My Regions',
    mapShow: 'Show Map',
    mapHide: 'Hide Map',
    searchPlaceholder: 'Search regions...',
    filterContinentAll: 'All Continents',
    filterContinentAsia: 'Asia Pacific',
    filterContinentEurope: 'Europe',
    filterContinentNa: 'North America',
    filterContinentSa: 'South America',
    filterContinentMe: 'ME & Africa',
    filterStatusAll: 'All Status',
    filterStatusOpen: 'Available',
    filterStatusClosed: 'Unavailable',
    colStatus: 'Status',
    colCode: 'Region Code',
    colName: 'Region Name',
    colArch: 'Architecture',
    colOpenTime: 'Launch time',
    colTotal: 'Total launches',
    colMonth: 'Monthly launches',
    colLast: 'Last Released',
    badgeOpen: 'Available',
    badgeClosed: 'Unavailable',
    empty: 'No matching regions',
    popupCode: 'Region code:',
    popupStatus: 'Status:',
    popupArch: 'Architecture:',
    popupTotal: 'Total boots:',
    popupMonth: 'Monthly boots:',
    popupOpenTime: 'Release time:',
    popupLast: 'Last released:',
  },
  nav: {
    service: 'Service',
    monitor: 'System monitor',
    regions: 'OCI Regions',
    tenants: 'OCI Tenants',
    instances: 'OCI Instances',
    email: 'OCI Email',
    storage: 'OCI Object Storage',
    boot: 'OCI Boot',
    ai: 'OCI AI',
    speed: 'OCI Latency Test',
    openLog: 'OCI boot logs',
    gcpAccounts: 'GCP Accounts',
    gcpInstances: 'GCP Instances',
    azureVms: 'Azure VMs',
    azureResources: 'Azure Resource groups',
    azureStorage: 'Azure Storage',
    azureNetworks: 'Azure Networks',
    awsEc2: 'EC2',
    awsS3: 'S3',
    awsLambda: 'Lambda',
    awsRds: 'RDS',
    proxy: 'Proxy',
    keyConfig: 'Key config',
    cf: 'Cloudflare',
    eo: 'EdgeOne',
    nginx: 'Nginx',
    vps: 'VPS',
    vpsList: 'Instances',
    system: 'System',
    quality: 'IP quality',
    logs: 'System logs',
    security: 'Security',
    proxyConfig: 'Proxy config',
    tools: 'Tools',
    notify: 'Notifications',
    notes: 'Memos',
    migration: 'Migration',
    mfa: 'MFA backup',
    dev: 'Developer',
    token: 'API tokens',
  },
}
