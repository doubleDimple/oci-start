import { createApp } from 'vue'
import { createPinia } from 'pinia'
import 'element-plus/es/components/message/style/css'
import 'element-plus/es/components/message-box/style/css'
import 'element-plus/es/components/loading/style/css'
import 'virtual:uno.css'

import App from './App.vue'
import router from './router'
import { i18n } from './i18n'
import { applyStoredTheme } from './composables/useTheme'
import './styles/tokens.css'
import './styles/index.scss'
import './styles/motion.scss'
import './styles/mobile-ios.scss'

applyStoredTheme()

const app = createApp(App)
app.use(createPinia())
app.use(router)
app.use(i18n)
app.mount('#app')
