import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

const read = rel => readFile(new URL(`../src/${rel}`, import.meta.url), 'utf8')

test('mobile styles reset sibling el-button margins inside flex/grid containers and drawer footers', async () => {
  const indexScss = await read('styles/index.scss')
  assert.match(indexScss, /\.el-drawer__footer \.el-button/)
  assert.match(indexScss, /> \.el-button \+ \.el-button\s*\{\s*margin-left:\s*0;/)

  for (const drawerFile of [
    'views/instances/components/InstanceOperationDialog.vue',
    'views/instances/components/InstanceNetworkDialog.vue',
    'views/instances/components/InstanceReinstallDialog.vue',
    'views/tenants/components/TenantOperationDialogs.vue',
    'views/tenants/components/TenantRegionSecurityDialog.vue',
    'views/tenants/components/TenantRegionMysqlDialog.vue',
    'views/tenants/components/TenantRegionVolumesDialog.vue',
  ]) {
    const content = await read(drawerFile)
    assert.match(content, /margin-left:\s*0/, `${drawerFile} should reset Element Plus sibling margin-left`)
  }
})

test('mobile toolbars align button heights and wrapped rows cleanly across key pages', async () => {
  const tenantsScss = await read('views/tenants/tenants.scss')
  assert.doesNotMatch(tenantsScss, /\.tenant-import\s*\{[^}]*height:\s*32px\s*!important/)
  assert.match(tenantsScss, /\.toolbar-actions button\.btn\.tenant-import\s*\{\s*height:\s*40px;\s*min-height:\s*40px;/)

  const instancesScss = await read('views/instances/instances.scss')
  assert.match(instancesScss, /\.list-toolbar button\.btn\.filter-submit,\s*\.list-toolbar button\.btn\.tenant-details-entry\s*\{\s*height:\s*40px;\s*min-height:\s*40px;/)

  const bootList = await read('views/boot/BootListView.vue')
  assert.match(bootList, /\.toolbar-actions\s*\{\s*flex:\s*1 1 100%;\s*width:\s*100%;\s*justify-content:\s*flex-end;/)

  const ociBoot = await read('views/boot/oci-boot.scss')
  assert.match(ociBoot, /\.boot-toolbar-actions :deep\(button\.btn:not\(\.page-back-button\)\)\s*\{\s*min-height:\s*40px;\s*height:\s*40px;/)

  const vnicScss = await read('views/network/vnic.scss')
  assert.match(vnicScss, /\.vnic-toolbar \.el-button\s*\{\s*min-height:\s*40px;\s*height:\s*40px;\s*\}/)
  assert.match(vnicScss, /\.vnic-toolbar \.vnic-icon-button\s*\{\s*width:\s*40px;\s*height:\s*40px;\s*\}/)
})
