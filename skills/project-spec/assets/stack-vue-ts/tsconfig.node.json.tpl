{
  // 给跑在 Node 里的配置文件用（vite/vitest 配置），与 src 的 DOM + strict 配置分开。
  // 作为 tsconfig.json 的 project reference 挂载。
  "compilerOptions": {
    "composite": true,
    "skipLibCheck": true,
    "module": "ESNext",
    "moduleResolution": "bundler",
    "allowSyntheticDefaultImports": true
  },
  "include": ["vite.config.ts", "vitest.config.ts"]
}
