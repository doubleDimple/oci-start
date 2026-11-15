import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

test('headerMessages batch delete and clear-all contracts match backend endpoints and component UI', async () => {
  const apiSource = await readFile(new URL('../src/api/headerMessages.ts', import.meta.url), 'utf8')
  const i18nSource = await readFile(new URL('../src/i18n/headerMessages.ts', import.meta.url), 'utf8')
  const vueSource = await readFile(new URL('../src/components/header/HeaderMessages.vue', import.meta.url), 'utf8')
  const controllerSource = await readFile(
    new URL('../../oci-server/src/main/java/com/doubledimple/ociserver/controller/SystemMessageController.java', import.meta.url),
    'utf8',
  )
  const serviceImplSource = await readFile(
    new URL('../../oci-server/src/main/java/com/doubledimple/ociserver/service/impl/system/SystemMessageServiceImpl.java', import.meta.url),
    'utf8',
  )
  const repositorySource = await readFile(
    new URL('../../oci-dao/src/main/java/com/doubledimple/dao/repository/MessageRepository.java', import.meta.url),
    'utf8',
  )

  // Frontend API client exports
  assert.match(apiSource, /export async function deleteHeaderMessages\([\s\S]*post\('delBatch',\s*\{\s*businessIds:\s*uniqueIds\s*\}/)
  assert.match(apiSource, /export async function clearAllHeaderMessages\([\s\S]*post\('clear',\s*\{\}/)

  // i18n keys for both locales
  assert.match(i18nSource, /selectAll:\s*'全选本页'/)
  assert.match(i18nSource, /batchDelete:\s*'批量删除'/)
  assert.match(i18nSource, /clearAll:\s*'清空全部'/)
  assert.match(i18nSource, /selectAll:\s*'Select page'/)
  assert.match(i18nSource, /batchDelete:\s*'Delete selected'/)
  assert.match(i18nSource, /clearAll:\s*'Clear all'/)

  // Component controls, checkboxes, inline clear confirmation, and ElMessage feedback
  assert.match(vueSource, /type Action = 'all' \| 'delete' \| 'batchDelete' \| 'clearAll'/)
  assert.match(vueSource, /class="message-batch-bar"/)
  assert.match(vueSource, /@change="toggleSelectAllPage"/)
  assert.match(vueSource, /@change="toggleSelect\(message\.businessId\)"/)
  assert.match(vueSource, /@click="runAction\('batchDelete'\)"/)
  assert.match(vueSource, /@click="clearConfirmOpen = true"/)
  assert.match(vueSource, /@click="runAction\('clearAll'\)"/)
  assert.match(vueSource, /ElMessage\.success\(notice\.value\)/)

  // Backend endpoints, transactional batch JPQL deletes
  assert.match(controllerSource, /@PostMapping\("\/delBatch"\)[\s\S]*systemMessageService\.deleteMessages\(messageRequest\)/)
  assert.match(controllerSource, /@PostMapping\("\/clear"\)[\s\S]*systemMessageService\.clearAllMessages\(\)/)
  assert.match(serviceImplSource, /public ApiResponse deleteMessages[\s\S]*deleteByBusinessIds/)
  assert.match(serviceImplSource, /public ApiResponse clearAllMessages[\s\S]*deleteAllMessages\(\)/)
  assert.match(repositorySource, /delete from Message m where m\.businessId in :businessIds/)
  assert.match(repositorySource, /delete from Message m"/)
})
