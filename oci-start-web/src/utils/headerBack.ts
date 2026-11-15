import type { ComputedRef, InjectionKey } from 'vue'

export const LAYOUT_HEADER_BACK_KEY: InjectionKey<ComputedRef<HTMLElement | null>> = Symbol('layoutHeaderBack')
