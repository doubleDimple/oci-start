export type SshTerminalTheme = 'system' | 'tokyonight' | 'dracula' | 'nord' | 'monokai'
  | 'solarizedLight' | 'highContrast' | 'matrix'
export type SshTerminalError = 'loadFailed' | 'renderFailed' | 'outputOverflow'
export type SshTerminalShortcut = 'search' | 'fullscreen' | 'increaseFont' | 'decreaseFont' | 'copy' | 'paste'
export interface SshTerminalDimensions { cols: number; rows: number }
export interface SshTerminalSearch { index: number; total: number }
export interface SshTerminalCanvasHandle {
  write(data: string | Uint8Array): boolean
  focus(): void
  fit(): void
  clear(): void
  reset(): void
  paste(text: string): void
  getSelection(): string
  selectAll(): void
  clearSelection(): void
  getBufferText(): string
  search(query: string, direction?: 1 | -1): SshTerminalSearch
  getDimensions(): SshTerminalDimensions | null
  scrollToBottom(): void
}

// Narrow public API of the existing local UMD runtime. No private xterm fields
// are accessed here; its matching bundled FitAddon owns renderer measurement.
export interface TerminalDisposable { dispose(): void }
export interface TerminalBufferLine {
  readonly isWrapped: boolean
  translateToString(trimRight?: boolean): string
}
export interface TerminalBuffer {
  readonly length: number
  getLine(index: number): TerminalBufferLine | undefined
}
export type TerminalPalette = Record<string, string>
export interface TerminalOptions {
  cols?: number; rows?: number; fontFamily?: string; fontSize?: number
  cursorBlink?: boolean; scrollback?: number; allowProposedApi?: boolean
  rendererType?: 'canvas' | 'dom'; disableStdin?: boolean
  convertEol?: boolean; theme?: TerminalPalette; screenReaderMode?: boolean
  allowTransparency?: boolean; logLevel?: 'off'; windowsMode?: boolean
}
export interface LocalTerminal {
  readonly cols: number
  readonly rows: number
  readonly element?: HTMLElement
  readonly textarea?: HTMLTextAreaElement
  readonly buffer: { active: TerminalBuffer }
  options: TerminalOptions
  open(element: HTMLElement): void
  loadAddon(addon: TerminalDisposable): void
  onData(listener: (data: string) => void): TerminalDisposable
  onResize(listener: (dimensions: SshTerminalDimensions) => void): TerminalDisposable
  attachCustomKeyEventHandler(listener: (event: KeyboardEvent) => boolean): void
  write(data: string | Uint8Array, callback?: () => void): void
  focus(): void
  blur(): void
  clear(): void
  reset(): void
  paste(text: string): void
  getSelection(): string
  selectAll(): void
  clearSelection(): void
  scrollToLine(line: number): void
  scrollToBottom(): void
  dispose(): void
}
export interface LocalFitAddon extends TerminalDisposable {
  fit(): void
  proposeDimensions(): SshTerminalDimensions | undefined
}
export type TerminalWebLinksConstructor = new (handler: (event: MouseEvent, uri: string) => void) => TerminalDisposable
export interface TerminalRuntime {
  Terminal: new (options?: TerminalOptions) => LocalTerminal
  FitAddon: new () => LocalFitAddon
}
