import { defineConfig, type ProxyOptions } from 'vite'
import vue from '@vitejs/plugin-vue'
import AutoImport from 'unplugin-auto-import/vite'
import Components from 'unplugin-vue-components/vite'
import { ElementPlusResolver } from 'unplugin-vue-components/resolvers'
import UnoCSS from 'unocss/vite'
import { fileURLToPath, URL } from 'node:url'

const backend = 'http://127.0.0.1:9856'

const proxyPaths = [
  '/api', '/tenants', '/oci', '/boot', '/system', '/ws', '/ssl', '/dns',
  '/email', '/monitor', '/cost', '/vpnProxy', '/m', '/perform_login',
  '/perform_logout', '/resource', '/other', '/vps', '/ssh', '/migration',
  '/mfa', '/ai', '/social', '/sysMessage', '/delayTest', '/instanceDetail', '/images', '/css', '/js',
  '/webfonts', '/script', '/login', '/about',
]

const htmlPageToBackend = new Set(['/login', '/perform_login'])

const proxy: Record<string, ProxyOptions> = {}
for (const path of proxyPaths) {
  proxy[path] = {
    target: backend,
    changeOrigin: true,
    ws: path === '/ws',
    bypass(req) {
      if (htmlPageToBackend.has(path)) return
      const accept = req.headers.accept
      if (typeof accept === 'string' && accept.includes('text/html')) {
        return '/index.html'
      }
    },
  }
}

export default defineConfig({
  plugins: [
    vue(),
    UnoCSS(),
    AutoImport({
      imports: ['vue', 'vue-router', 'pinia'],
      resolvers: [ElementPlusResolver()],
      dts: 'src/types/auto-imports.d.ts',
    }),
    Components({
      resolvers: [ElementPlusResolver()],
      dts: 'src/types/components.d.ts',
    }),
  ],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  server: {
    host: '0.0.0.0',
    port: 5173,
    proxy,
  },
  build: {
    outDir: '../oci-server/src/main/resources/static',
    emptyOutDir: false,
    chunkSizeWarningLimit: 1500,
    rollupOptions: {
      output: {
        entryFileNames: 'assets/[name]-[hash].js',
        chunkFileNames: 'assets/[name]-[hash].js',
        assetFileNames: 'assets/[name]-[hash][extname]',
        manualChunks(id) {
          if (!id.includes('node_modules')) return
          if (id.includes('echarts') || id.includes('zrender')) return 'echarts'
          if (
            id.includes('/vue/') ||
            id.includes('/vue-router/') ||
            id.includes('/vue-i18n/') ||
            id.includes('/pinia/') ||
            id.includes('/@vue/')
          ) {
            return 'vue-vendor'
          }
        },
      },
    },
  },
})
