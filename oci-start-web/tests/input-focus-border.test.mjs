import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

const read = rel => readFile(new URL(`../src/${rel}`, import.meta.url), 'utf8')

test('global and shared input focus styles do not paint brand-colored borders or rings', async () => {
  const indexScss = await read('styles/index.scss')
  assert.doesNotMatch(indexScss, /\.el-input__wrapper\.is-focus[^{]*\{[^}]*var\(--brand\)/)
  assert.match(indexScss, /\.el-input__wrapper\.is-focus[\s\S]*?box-shadow:\s*0 0 0 1px var\(--border-strong\) inset/)

  const tokensCss = await read('styles/tokens.css')
  assert.match(tokensCss, /--el-input-focus-border-color:\s*var\(--border-strong\)/)

  const motionScss = await read('styles/motion.scss')
  assert.match(motionScss, /:where\(input:not\(\[type='checkbox'\]\):not\(\[type='radio'\]\),\s*select,\s*textarea\):focus[\s\S]*?outline:\s*none/)

  const consoleScss = await read('styles/console.scss')
  assert.match(consoleScss, /&:focus-within\s*\{\s*border-color:\s*var\(--border-strong\);\s*box-shadow:\s*none;\s*outline:\s*none;\s*\}/)

  const tenantsScss = await read('views/tenants/tenants.scss')
  assert.match(tenantsScss, /\.tenant-search:focus-within\s*\{\s*border-color:\s*var\(--border-strong\);\s*box-shadow:\s*none;\s*outline:\s*none;\s*\}/)

  const headerSearch = await read('components/header/HeaderSearch.vue')
  assert.match(headerSearch, /\.search-field:focus-within\s*\{\s*border-color:\s*var\(--border-strong\);\s*box-shadow:\s*none;\s*outline:\s*none;\s*\}/)

  const bootScss = await read('views/boot/oci-boot.scss')
  assert.match(bootScss, /&:focus\s*\{\s*border-color:\s*var\(--border\);\s*box-shadow:\s*none;\s*outline:\s*none;\s*\}/)
  assert.match(bootScss, /:deep\(\.el-select__wrapper\.is-focused\)\s*\{\s*border-color:\s*var\(--border\);\s*box-shadow:\s*none;\s*outline:\s*none;\s*\}/)
})
