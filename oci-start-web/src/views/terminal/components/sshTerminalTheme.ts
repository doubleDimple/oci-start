import { readChartTheme } from '@/utils/chartTheme'
import type { SshTerminalTheme, TerminalPalette } from './sshTerminalTypes'

// The seven terminal palettes already offered by ssh_terminal.ftl. These are
// explicit terminal preferences; surrounding controls still follow page tokens.
const presets: Record<Exclude<SshTerminalTheme, 'system'>, TerminalPalette> = {
  tokyonight: {
    background: '#1a1b26', foreground: '#a9b1d6', cursor: '#c0caf5',
    black: '#15161e', red: '#f7768e', green: '#9ece6a', yellow: '#e0af68', blue: '#7aa2f7', magenta: '#bb9af7', cyan: '#7dcfff', white: '#a9b1d6',
    brightBlack: '#414868', brightRed: '#f7768e', brightGreen: '#9ece6a', brightYellow: '#e0af68', brightBlue: '#7aa2f7', brightMagenta: '#bb9af7', brightCyan: '#7dcfff', brightWhite: '#c0caf5',
  },
  dracula: {
    background: '#282a36', foreground: '#f8f8f2', cursor: '#f8f8f2',
    black: '#000000', red: '#ff5555', green: '#50fa7b', yellow: '#f1fa8c', blue: '#bd93f9', magenta: '#ff79c6', cyan: '#8be9fd', white: '#bbbbbb',
    brightBlack: '#555555', brightRed: '#ff5555', brightGreen: '#50fa7b', brightYellow: '#f1fa8c', brightBlue: '#bd93f9', brightMagenta: '#ff79c6', brightCyan: '#8be9fd', brightWhite: '#ffffff',
  },
  nord: {
    background: '#2e3440', foreground: '#d8dee9', cursor: '#d8dee9',
    black: '#3b4252', red: '#bf616a', green: '#a3be8c', yellow: '#ebcb8b', blue: '#81a1c1', magenta: '#b48ead', cyan: '#88c0d0', white: '#e5e9f0',
    brightBlack: '#4c566a', brightRed: '#bf616a', brightGreen: '#a3be8c', brightYellow: '#ebcb8b', brightBlue: '#81a1c1', brightMagenta: '#b48ead', brightCyan: '#8fbcbb', brightWhite: '#eceff4',
  },
  monokai: {
    background: '#272822', foreground: '#f8f8f2', cursor: '#f8f8f0',
    black: '#272822', red: '#f92672', green: '#a6e22e', yellow: '#f4bf75', blue: '#66d9ef', magenta: '#ae81ff', cyan: '#a1efe4', white: '#f8f8f2',
    brightBlack: '#75715e', brightRed: '#f92672', brightGreen: '#a6e22e', brightYellow: '#f4bf75', brightBlue: '#66d9ef', brightMagenta: '#ae81ff', brightCyan: '#a1efe4', brightWhite: '#f9f8f5',
  },
  solarizedLight: {
    background: '#fdf6e3', foreground: '#657b83', cursor: '#657b83',
    black: '#073642', red: '#dc322f', green: '#859900', yellow: '#b58900', blue: '#268bd2', magenta: '#d33682', cyan: '#2aa198', white: '#eee8d5',
    brightBlack: '#002b36', brightRed: '#cb4b16', brightGreen: '#586e75', brightYellow: '#657b83', brightBlue: '#839496', brightMagenta: '#6c71c4', brightCyan: '#93a1a1', brightWhite: '#fdf6e3',
  },
  highContrast: {
    background: '#000000', foreground: '#ffffff', cursor: '#ffffff',
    black: '#000000', red: '#ff0000', green: '#00ff00', yellow: '#ffff00', blue: '#0088ff', magenta: '#ff00ff', cyan: '#00ffff', white: '#ffffff',
    brightBlack: '#7f7f7f', brightRed: '#ff4c4c', brightGreen: '#4cff4c', brightYellow: '#ffff4c', brightBlue: '#4c9dff', brightMagenta: '#ff4cff', brightCyan: '#4cffff', brightWhite: '#ffffff',
  },
  matrix: {
    background: '#000000', foreground: '#00ff00', cursor: '#00ff00',
    black: '#000000', red: '#ff0000', green: '#00ff00', yellow: '#ffff00', blue: '#00ffff', magenta: '#ff00ff', cyan: '#00ffff', white: '#ffffff',
    brightBlack: '#333333', brightRed: '#ff5555', brightGreen: '#00ff00', brightYellow: '#ffff55', brightBlue: '#55ffff', brightMagenta: '#ff55ff', brightCyan: '#55ffff', brightWhite: '#ffffff',
  },
}

/** Resolve dynamic CSS colors to native sRGB before giving them to xterm 4.x. */
export function terminalPalette(name: SshTerminalTheme): TerminalPalette {
  if (name !== 'system' && Object.prototype.hasOwnProperty.call(presets, name)) return { ...presets[name] }
  const theme = readChartTheme()
  const dark = (document.documentElement.getAttribute('data-content-theme')
    || document.documentElement.getAttribute('data-theme')) === 'dark'
  // ANSI colors retain their protocol meaning. Default text, cursor, selection
  // and the terminal surface follow the same resolved page palette as charts.
  const palette = dark ? presets.tokyonight : presets.solarizedLight
  return {
    ...palette, background: theme.surface, foreground: theme.text, cursor: theme.text,
    cursorAccent: theme.surface, selection: theme.border,
  }
}
