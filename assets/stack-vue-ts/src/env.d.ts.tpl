/// <reference types="vite/client" />

/** vite.config.ts define 注入：package.json 的项目版本 */
declare const __APP_VERSION__: string

declare module '*?raw' {
  const content: string
  export default content
}

interface ImportMetaEnv {
{{#BACKEND}}
  /** 存储 API 根路径，默认 '/api' */
  readonly VITE_API_BASE?: string
  /** 访问存储后端的 Bearer Token（可选，与后端 AUTH_TOKEN 对应） */
  readonly VITE_API_TOKEN?: string
{{/BACKEND}}
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}

declare module '*.vue' {
  import type { DefineComponent } from 'vue'
  const component: DefineComponent<Record<string, unknown>, Record<string, unknown>, unknown>
  export default component
}
