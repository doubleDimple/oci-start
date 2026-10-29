import { tokens } from '@cloudscape-design/design-tokens/index-visual-refresh.json'

// Cloudscape's JSON format supports non-React stacks. Keep the existing Vue
// components and map semantic roles, rather than importing React component CSS.
// https://cloudscape.design/foundation/visual-foundation/design-tokens/
type Mode = 'light' | 'dark'
type ColorToken = { $value: Record<Mode, string> }
const color = (token: ColorToken, mode: Mode) => token.$value[mode]

export function cloudscapeContent(mode: Mode) {
  return {
    mode,
    // A quiet canvas separates resource containers from the surrounding shell.
    page: mode === 'light' ? '#f4f5f7' : '#0f141a',
    card: color(tokens['color-background-container-content'], mode),
    cardSubtle: mode === 'light' ? '#f9f9fa' : '#1b232d',
    search: color(tokens['color-background-input-default'], mode),
    hover: mode === 'light' ? '#f5f2ef' : '#292522',
    border: color(tokens['color-border-divider-default'], mode),
    borderStrong: color(tokens['color-border-input-default'], mode),
    textPrimary: color(tokens['color-text-body-default'], mode),
    textSecondary: color(tokens['color-text-body-secondary'], mode),
    textMuted: color(tokens['color-text-input-placeholder'], mode),
    shadowCard: mode === 'light' ? '0 1px 2px rgba(15, 20, 26, 0.05)' : '0 1px 2px rgba(0, 0, 0, 0.2)',
  }
}

export function cloudscapeVariables(mode: Mode): Record<string, string> {
  return {
    // Orange text needs a deeper shade than filled controls on light surfaces.
    '--brand': mode === 'light' ? '#b34814' : '#ffb47a',
    '--brand-hover': mode === 'light' ? '#963c11' : '#ffcca5',
    '--brand-deep': mode === 'light' ? '#963c11' : '#ffcca5',
    '--brand-subtle': mode === 'light' ? '#fff0e6' : '#3b2b20',
    '--brand-solid': '#f5a15d',
    '--brand-solid-hover': '#ee9148',
    '--text-on-solid': '#3b220f',
    '--text-on-brand': color(tokens['color-text-button-primary-default'], mode),
    '--text-heading': color(tokens['color-text-heading-default'], mode),
    '--status-ok': color(tokens['color-text-status-success'], mode),
    '--status-ok-bg': color(tokens['color-background-status-success'], mode),
    '--status-info': color(tokens['color-text-status-info'], mode),
    '--status-info-bg': color(tokens['color-background-status-info'], mode),
    '--status-warn': color(tokens['color-text-status-warning'], mode),
    '--status-warn-bg': color(tokens['color-background-status-warning'], mode),
    '--status-danger': color(tokens['color-text-status-error'], mode),
    '--status-danger-bg': color(tokens['color-background-status-error'], mode),
    '--chart-primary': mode === 'light' ? '#d77b33' : '#ffb47a',
    '--chart-tertiary': mode === 'light' ? '#8867b1' : '#c1a3ed',
    '--chart-secondary': mode === 'light' ? '#087e8b' : '#63d5d2',
    '--r-btn': tokens['border-radius-button'].$value,
    '--r-card': tokens['border-radius-container'].$value,
    '--r-sm': tokens['border-radius-input'].$value,
    '--font-size-body': tokens['font-size-body-m'].$value,
    '--font-size-page-title': tokens['font-size-heading-xl'].$value,
    '--space-s': tokens['space-scaled-s'].$value.comfortable,
    '--space-m': tokens['space-scaled-m'].$value.comfortable,
    '--space-l': tokens['space-scaled-l'].$value.comfortable,
  }
}
