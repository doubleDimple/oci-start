import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import ts from 'typescript'

const source = await readFile(new URL('../src/composables/useChrome.ts', import.meta.url), 'utf8')
let transpiledSource = source
  .replace(/import\s*\{[^}]*\}\s*from\s*['"]vue['"]/g, `
    const reactive = v => v;
    const ref = v => ({ value: v });
    const computed = fn => ({ get value() { return fn() } });
  `)
  .replace(/import\s*type\s*\{[^}]*\}\s*from\s*['"][^'"]*['"]/g, '')

const { outputText } = ts.transpileModule(transpiledSource, {
  compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
})
const helperModuleUrl = `data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`
const helpers = await import(helperModuleUrl)
const {
  deriveCustomPalette,
  CONTENT_PRESETS,
  SIDEBAR_PRESETS,
  isLightColor,
  hexToRgb,
  rgbToHsl,
  hslToHex,
} = helpers

test('all CONTENT_PRESETS have distinct card and page colors so container divs never disappear', () => {
  assert.ok(CONTENT_PRESETS.length >= 6)
  for (const preset of CONTENT_PRESETS) {
    assert.ok(preset.id, 'Preset must have an id')
    assert.ok(preset.page.startsWith('#'), `Preset ${preset.id} page must be valid hex`)
    assert.ok(preset.card.startsWith('#'), `Preset ${preset.id} card must be valid hex`)
    assert.ok(preset.border.startsWith('#'), `Preset ${preset.id} border must be valid hex`)
    assert.notEqual(
      preset.page.toLowerCase(),
      preset.card.toLowerCase(),
      `Preset ${preset.id} must have card background distinct from page canvas`,
    )
  }
})

test('pure white page (#ffffff) derives a distinct card surface to prevent cards from vanishing', () => {
  const palette = deriveCustomPalette('#ffffff')
  assert.equal(palette.mode, 'light')
  assert.equal(palette.page, '#ffffff')
  assert.notEqual(
    palette.card.toLowerCase(),
    '#ffffff',
    'When page is pure white, cards must derive a subtle contrast surface (e.g. #f8fafc) rather than merging into white',
  )
  assert.ok(palette.border.startsWith('#'))
  assert.ok(palette.search.startsWith('#'))
})

test('standard light canvas derives crisp floating white card and harmonized borders', () => {
  const palette = deriveCustomPalette('#f1f5f9')
  assert.equal(palette.mode, 'light')
  assert.equal(palette.page, '#f1f5f9')
  assert.equal(palette.card.toLowerCase(), '#ffffff')
  assert.notEqual(palette.search.toLowerCase(), palette.card.toLowerCase())
  assert.ok(palette.border.startsWith('#'))
})

test('dark canvas derives elevated cards that are lighter than page for real visual hierarchy', () => {
  const darkNavy = '#0b0f19'
  const palette = deriveCustomPalette(darkNavy)
  assert.equal(palette.mode, 'dark')
  assert.equal(palette.page, darkNavy)
  const rgbPage = hexToRgb(palette.page)
  const rgbCard = hexToRgb(palette.card)
  const hslPage = rgbToHsl(rgbPage.r, rgbPage.g, rgbPage.b)
  const hslCard = rgbToHsl(rgbCard.r, rgbCard.g, rgbCard.b)
  assert.ok(
    hslCard.l > hslPage.l,
    `Card lightness (${hslCard.l}%) must be higher than page canvas (${hslPage.l}%) for dark mode elevation`,
  )
  assert.equal(palette.textPrimary, '#f8fafc')
})

test('all SIDEBAR_PRESETS specify correct contrast flags', () => {
  for (const sidebar of SIDEBAR_PRESETS) {
    assert.ok(sidebar.color.startsWith('#'))
    assert.equal(sidebar.isLight, isLightColor(sidebar.color))
  }
})
