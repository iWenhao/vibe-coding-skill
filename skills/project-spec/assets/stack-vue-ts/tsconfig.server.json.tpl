{
  // 服务端（ESM .mjs）类型检查配置。
  //
  // 为什么单独一份：tsconfig.json 的 include 只覆盖 src/，服务端长期既不 lint 也不类型检查，
  // 里面全是 `node:fs` / `node:http` 这类 Node API 与 JSDoc 类型，跟前端那套 DOM + strict 配置混不到一起。
  //
  // 用法：pnpm typecheck:server（= npx tsc -p tsconfig.server.json）
  // 注意：这里刻意不开 strict —— 服务端是渐进补上的检查，一上来开 strict 会报出上百条既有问题、
  // 把真正的错误淹掉。现阶段先让「类型确实被检查起来」，strict 留作后续单独一轮。
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "types": ["node"],
    "allowJs": true,
    "checkJs": true,
    "noEmit": true,
    "skipLibCheck": true,
    "resolveJsonModule": true,
    "allowSyntheticDefaultImports": true,
    "esModuleInterop": true,
    "strict": false,
    "noUnusedLocals": false,
    "noUnusedParameters": false
  },
  "include": ["server/**/*.mjs", "server/**/*.d.mts", "shared/**/*.mjs", "shared/**/*.d.mts"],
  "exclude": ["server/data/**"]
}
