import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import AutoImport from 'unplugin-auto-import/vite'
import Components from 'unplugin-vue-components/vite'
import { ElementPlusResolver } from 'unplugin-vue-components/resolvers'
import { readFileSync } from 'node:fs'
import path from 'path'

// 读取 package.json 的版本注入给前端（控制台横幅/关于页要用），
// 用 readFileSync 而非 JSON import，避免为 resolveJsonModule 单独调 tsconfig.node.json。
const pkg = JSON.parse(
  readFileSync(new URL('./package.json', import.meta.url), 'utf-8'),
) as { name: string; version: string; description: string }

export default defineConfig({
  define: {
    __APP_VERSION__: JSON.stringify(pkg.version),
  },
  plugins: [
    vue(),
    // 自动导入 vue/vue-router/pinia 的 API 与 Element Plus 组件，
    // 生成的 d.ts 是自动产物，跟随相关改动一起提交、不要手写
    AutoImport({
      resolvers: [ElementPlusResolver()],
      imports: ['vue', 'vue-router', 'pinia'],
      dts: 'auto-imports.d.ts',
    }),
    Components({
      resolvers: [ElementPlusResolver()],
      dts: 'components.d.ts',
    }),
  ],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'src'),
    },
  },
  css: {
    preprocessorOptions: {
      scss: { api: 'modern-compiler' },
    },
  },
  build: {
    rollupOptions: {
      output: {
        // 重依赖单独分包，别和 vue 挤在同一个首屏 chunk 里；
        // 新增大体积库（画布/图表/编辑器）时在此补一条
        manualChunks(id) {
          if (id.includes('node_modules/element-plus')) return 'vendor-element'
          if (id.includes('node_modules/vue')) return 'vendor-vue'
          return undefined
        },
      },
    },
  },
  server: {
    // 显式绑定 IPv4 回环地址，不用默认的 localhost。
    // 背景：某些本机代理/TUN 工具会拦截 IPv6 回环 ::1 的 TCP 连接，而 Node 17+ 解析
    // localhost 优先返回 ::1，于是 dev server 只监听 [::1]——浏览器走 IPv6 被拦、
    // 走 IPv4 又无人监听，表现为「服务已启动但页面打不开」，很容易被误判成依赖装坏了。
    // 代价：绑 127.0.0.1 后局域网设备访问不到，需要手机联调时临时用 `pnpm dev --host`。
    host: '127.0.0.1',
    port: {{DEV_PORT}},
    strictPort: true{{#BACKEND}},
    proxy: {
      // 目标写 127.0.0.1 而非 localhost：同样是为了避开 ::1 被拦截。
      // 改这里或后端路由后需要重启 dev server。
      '/api': 'http://127.0.0.1:{{API_PORT}}',
    }{{/BACKEND}},
  },
})
