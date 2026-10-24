import { defineConfig, type ProxyOptions } from 'vite'
import vue from '@vitejs/plugin-vue'
import AutoImport from 'unplugin-auto-import/vite'
import Components from 'unplugin-vue-components/vite'
import { ElementPlusResolver } from 'unplugin-vue-components/resolvers'
import UnoCSS from 'unocss/vite'
import { fileURLToPath, URL } from 'node:url'
import { rmSync } from 'node:fs'

const backend = 'http://127.0.0.1:9856'

const proxyPaths = [
  '/api', '/tenants', '/oci', '/boot', '/system', '/ws', '/ssl', '/dns',
  '/email', '/monitor', '/cost', '/vpnProxy', '/m', '/perform_login',
  '/perform_logout', '/resource', '/other', '/vps', '/ssh', '/migration',
  '/mfa', '/ai', '/social', '/sysMessage', '/delayTest', '/instanceDetail', '/images', '/css', '/js',
  '/webfonts', '/script', '/login', '/about',
]

const proxy: Record<string, ProxyOptions> = {}
// Documentation is served by Spring, including browser navigation and its assets.
for (const path of ['/swagger-ui', '/v3/api-docs']) {
  proxy[path] = { target: backend, changeOrigin: true }
}
for (const path of proxyPaths) {
  proxy[path] = {
    target: backend,
    changeOrigin: true,
    ws: path === '/ws',
    bypass(req) {
      const pathname = req.url?.split('?')[0] || path
      // OAuth callbacks are browser navigations too; they must finish on Spring.
      if (!['GET', 'HEAD'].includes(req.method || 'GET')
          || pathname.startsWith('/api/') || pathname.startsWith('/perform_')
          || pathname.startsWith('/social/')) return
      const accept = req.headers.accept
      if (typeof accept === 'string' && accept.includes('text/html')) {
        return '/index.html'
      }
    },
  }
}

export default defineConfig({
  plugins: [
    {
      name: 'clean-vue-assets',
      apply: 'build',
      buildStart() {
        // Only Vite's generated chunks: shared images and terminal runtimes stay intact.
        rmSync(fileURLToPath(new URL('../oci-server/src/main/resources/static/assets', import.meta.url)), { recursive: true, force: true })
      },
    },
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
    warmup: {
      clientFiles: [
        './src/main.ts', './src/App.vue', './src/layouts/DefaultLayout.vue',
        './src/views/dashboard/DashboardView.vue', './src/views/tenants/TenantsView.vue',
        './src/views/instances/InstancesView.vue', './src/views/vps/VpsListView.vue',
      ],
    },
  },
  // Template auto-imports appear after the initial dependency scan.
  optimizeDeps: { include: ['element-plus/es'] },
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
