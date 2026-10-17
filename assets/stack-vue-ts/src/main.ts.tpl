import { createApp } from 'vue'
import { createPinia } from 'pinia'
// 只注册模板里实际用到的图标：全量注册（app.use(ElementPlusIconsVue)）会把几百个图标
// 打进 bundle。新增图标时在这里补一项，而不是改成全量注册。
import { Plus, Search, Setting } from '@element-plus/icons-vue'
// Element Plus 组件本体与样式由 unplugin 的 ElementPlusResolver 按需注入，
// 不再全量 app.use + 全量 CSS（两份并存时按需配置会失效）。
// 但官方暗色变量必须保留：html.dark 时所有组件（含 teleport 弹层、表格行）整体转暗
import 'element-plus/theme-chalk/dark/css-vars.css'
// 编程式组件（ElMessage / ElMessageBox 这类函数调用，不是 <el-xxx> 标签）resolver 认不出来，
// 样式必须手动补——否则弹出的是没有样式的裸 DOM。新增编程式组件时照此补充。
import 'element-plus/es/components/message/style/css'
import 'element-plus/es/components/message-box/style/css'
import './styles/index.scss'
import App from './App.vue'
import { getStorage, initStorage } from './storage'

// 挂载前先应用主题，避免首帧闪一下错误的配色（light/dark 由 html.dark 类驱动）
const applyTheme = (theme: 'light' | 'dark') => {
  document.documentElement.dataset.theme = theme
  document.documentElement.classList.toggle('dark', theme === 'dark')
}
applyTheme('dark')

const app = createApp(App)
for (const [name, component] of Object.entries({ Plus, Search, Setting })) {
  app.component(name, component)
}
app.use(createPinia())

// 持久化统一走 storage 抽象层，业务代码不要直接碰 localStorage（约定见 AGENTS.md）
initStorage()
  .then(async () => {
    const saved = await getStorage().get('theme')
    if (saved === 'light' || saved === 'dark') applyTheme(saved)
  })
  .catch(() => {
    /* 存储不可用时保持默认主题，不阻塞挂载 */
  })

app.mount('#app')
