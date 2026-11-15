import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

test('App.vue configures global ElMessage placement to top-right with close button', async () => {
  const appSource = await readFile(new URL('../src/App.vue', import.meta.url), 'utf8')
  const mainSource = await readFile(new URL('../src/main.ts', import.meta.url), 'utf8')
  const toastCss = await readFile(new URL('../src/styles/toast.scss', import.meta.url), 'utf8')

  assert.match(appSource, /<ElConfigProvider[^>]*:message="elMessageConfig"/)
  assert.match(appSource, /placement:\s*'top-right'/)
  assert.match(appSource, /duration:\s*1800/)
  assert.match(appSource, /showClose:\s*true/)
  assert.match(mainSource, /import\s+'\.\/styles\/toast\.scss'/)

  assert.match(toastCss, /html:root\s+\.el-message\s*\{[\s\S]*width:\s*380px[\s\S]*height:\s*56px/)
  assert.match(toastCss, /-webkit-line-clamp:\s*2/)
  assert.match(toastCss, /\.el-message\.is-right[\s\S]*right:\s*18px/)
  assert.match(toastCss, /\.el-message-fade-enter-from\.is-right[\s\S]*translate3d\(calc\(100%\s*\+\s*28px\),\s*0,\s*0\)/)
  assert.match(toastCss, /@keyframes toast-slide-in-right/)
  assert.match(toastCss, /@keyframes toast-slide-out-right/)
  assert.match(toastCss, /\.el-message\.is-right\.el-message-fade-enter-active[\s\S]*animation:\s*toast-slide-in-right/)
  assert.match(toastCss, /\.el-message\.is-right\.el-message-fade-leave-active[\s\S]*animation:\s*toast-slide-out-right/)
  assert.match(toastCss, /\.el-message__icon[\s\S]*border-right:/)
  assert.match(toastCss, /\.el-message__content/)
})
