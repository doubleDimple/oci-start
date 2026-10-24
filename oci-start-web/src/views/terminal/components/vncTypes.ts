export type VncCanvasError = 'loadFailed' | 'invalidUrl' | 'connectFailed' | 'textTooLarge' | 'inputFailed'
export interface VncDisconnect { clean: boolean; reason: string }
export interface VncCredentials { username?: string; password?: string; target?: string }
export interface VncCredentialsRequired { types: string[] }
export interface VncSecurityFailure { status: number | null; reason: string }
export interface VncClipboard { text: string }
export interface VncDesktopName { name: string }
export interface VncCanvasHandle {
  /** Load the renderer only; never opens a WebSocket or creates cloud resources. */
  prepare(): Promise<boolean>
  retry(): Promise<boolean>
  disconnect(): void
  focus(): void
  blur(): void
  fit(): void
  getConnected(): boolean
  sendCredentials(credentials: VncCredentials): boolean
  sendCtrlAltDel(): boolean
  sendKey(keysym: number, code?: string, down?: boolean): boolean
  /** Sends keystrokes, not a remote clipboard update; false can include a sent prefix. */
  sendText(text: string): Promise<boolean>
  cancelText(): void
  clipboardPaste(text: string): boolean
}

/** Public noVNC 1.4 API used by the original console_terminal.ftl. */
export interface RfbClient extends EventTarget {
  scaleViewport: boolean
  resizeSession: boolean
  viewOnly: boolean
  focusOnClick: boolean
  background: string
  disconnect(): void
  focus(): void
  blur(): void
  sendCredentials(credentials: VncCredentials): void
  sendCtrlAltDel(): void
  sendKey(keysym: number, code?: string, down?: boolean): void
  clipboardPasteFrom(text: string): void
}
export type RfbConstructor = new (
  target: HTMLElement,
  url: string,
  options?: { shared?: boolean; wsProtocols?: string[]; credentials?: VncCredentials },
) => RfbClient
