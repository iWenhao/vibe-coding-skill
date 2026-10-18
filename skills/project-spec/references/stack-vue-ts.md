# 技术栈落地：Vue 3 + TypeScript + Vite

scaffold 用 `--stack vue-ts` 时生成的配置，每一项的**理由**写在这里。换栈时（React / Svelte / 纯 Node）本文件不适用，但约定内核照用。

## 选型与职责

| 依赖 | 作用 | 为什么是它 |
| --- | --- | --- |
| `vue` + `typescript` + `vite` | 主体 | 类型检查交给 `vue-tsc`，构建交给 vite，两者分离 |
| `pinia` | 跨组件状态 | 只放跨组件状态；单组件内的逻辑放 composable |
| `vue-router` | 路由 | 多页面分层（列表 → 详情 → 编辑）是常见形态 |
| `element-plus` + `@element-plus/icons-vue` | 组件库与图标 | 图标在 `main.ts` 全局注册，SFC 里**不需要 import**（unplugin 也已配 resolver） |
| `@vueuse/core` | 组合式工具 | 先查这里有没有现成的，再自己写 |
| `echarts` | 图表 | 可选 |
| `sass` | 样式 | vite 配 `api: 'modern-compiler'`，避免旧 legacy API 告警 |

图表、渲染引擎这类重依赖用 `manualChunks` 单独分包（见 `vite.config.ts` 模板），否则首屏 chunk 会把它们和 vue 打在一起。

## pnpm 与构建脚本白名单

`pnpm-workspace.yaml` 的 `allowBuilds`（`esbuild` / `@parcel/watcher` / `vue-demi`）**不要删**：pnpm 10/11 会拦截依赖的构建脚本，删了表现为装完跑不起来。

## tsconfig 三份，各管一片

- `tsconfig.json`——只 include `src/**`，开 strict 四件套（见约定内核第 6 节），`moduleResolution: bundler`、`noEmit`、`isolatedModules`、`paths: {"@/*": ["./src/*"]}`。
- `tsconfig.node.json`——给 `vite.config.ts` / `vitest.config.ts` 这类跑在 Node 的配置文件用，作为 project reference 挂在主配置上。
- `tsconfig.server.json`（`--backend` 时生成）——服务端是 ESM `.mjs`，`allowJs` + `checkJs`，include 只覆盖 `server/**` 与 `shared/**`。
  - **这条配置的独立价值**：`vue-tsc` 的 include 不含服务端目录，所以服务端唯一的类型检查入口是 `tsc -p tsconfig.server.json`（脚本名 `typecheck:server`）。不跑等于后端改动零把关。
  - 这里**刻意不开 strict**：后端是渐进补上的检查，一上来开 strict 会报出上百条既有问题、把真正的错误淹掉。strict 留作单独一轮。这是「先让检查存在，再提高强度」的通用策略。

## ESLint flat config（v9+）

`.ts/.mjs` 与 `.vue` **必须拆成两个块**：前者的 `languageOptions.parser` 是 TS parser，会覆盖 `flat/recommended` 为 `.vue` 注入的 `vue-eslint-parser`，导致模板解析失败。

三条关掉的规则及理由（照抄前先确认适用）：

- `@typescript-eslint/no-explicit-any: off`——大体积第三方库返回的事件与渲染对象逐个声明类型收益不大。
- `no-undef: off`——TS 已由 `vue-tsc` 检查未定义标识符；ESLint 版不认识类型（如 `RequestInit`）会误报。
- `vue/multi-word-component-names` / 格式类规则 off——格式交给编辑器与构建，别让 lint 报缩进。

`@typescript-eslint/no-unused-vars` 设 `warn` 并加 `argsIgnorePattern: '^_'`，与 strict 的 `noUnusedParameters` 呼应（`_e` 约定）。

**全量 lint 会被既有 `.vue` 报警淹没**，所以日常只跑改动文件；这条也写进了验证节奏表。

## unplugin 自动生成文件

`auto-imports.d.ts` / `components.d.ts` 由 unplugin 生成，**跟随相关改动一起提交**（不提交会导致别人拉下来类型缺失）。它们不是手写文件，别去改内容。

## vitest

`environment: 'jsdom'`、`globals: true`，`include` 要**显式列出所有被测目录**——默认只扫 src，工具脚本与共用纯逻辑目录（`shared/`、`scripts/`）会被静默漏掉。测试统一放被测文件同目录。

### 按范围挑着跑的三条命令

写进 `AGENTS.md`「验证节奏」表的就是这三条（全量只在提交前跑）：

| 想验证的范围 | 命令 |
| --- | --- |
| 单个文件 / 模块 | `npx vitest run src/utils` |
| 一批改动（未提交的也算） | `npx vitest run --changed` |
| 几条特定用例 | `npx vitest run -t "关键词"` |

三条都接受路径子串做模糊匹配，多个参数是「或」关系。

### 每个测试文件自己选环境

配置里的 `environment: 'jsdom'` 是**默认值，不是每个文件的需求**——jsdom 环境的启动开销远大于纯逻辑用例本体。

- 纯逻辑测试（工具函数、纯数学/几何、协议解析、Pinia store 的纯状态流转、数据结构）：文件**第一行**写 `// @vitest-environment node`。
- 真用了 `mount` / `document` / `window` / `localStorage` / canvas / `ResizeObserver` 的：保持默认 jsdom。
- 判据看**用例自身**，被测源码可能间接摸浏览器 API；改完必须真跑一遍确认，炸了就退回默认。

## 前端 + 可选零依赖后端（`--backend`）

这套形态值得复制：**前端是纯前端项目（构建产物可直接托管），后端是可选的存储服务，不在线时回落 localStorage**。

- `server/*.mjs` 零依赖（只用 `node:` 内置模块），单文件起 HTTP 服务，数据落 `DATA_DIR` 下的 `*.json`。
- 前端 `RemoteStorageAdapter` 通过 `/api/storage/*` 访问；启动时探测后端在线与否，不在线回落本地存储。**这个探测让「纯前端托管」和「带存储部署」两种形态共用一份代码**。
- Vite 代理 `/api` → 后端端口；改代理或后端路由后**需重启 dev server**。
- 环境变量以 `.env.example` 为**单一清单**，只列 `server/index.mjs` 真读的那几个：`PORT` / `HOST` / `DATA_DIR` / `MAX_BODY_BYTES` / `CORS_ORIGIN` / `AUTH_TOKEN`，加前端 `VITE_*`（构建期注入，改了要重新构建）。**加开关必须代码与清单一起改**——文档里写了代码没读的变量，用户设了没反应，就是一份假接口（这次清理掉五条这种条目：`NOTIFY_ALLOW_PRIVATE`、`NOTIFY_TIMEOUT_MS`、`SMTP_REJECT_UNAUTHORIZED`、`SEED_PASSWORD`、以及并不存在的 `_users.json` 账号体系）。
- 默认值保守（只监听 `127.0.0.1`、`CORS_ORIGIN=*`、请求体有上限），放开是显式选择。`AGENTS.md`、`docs/DEPLOY.md` 与 `server/index.mjs` 头注释都**不再重列这份清单**，各留一句指针——四处各写一遍，改一处就漏三处。
- 运行时数据目录（`server/data/`）**必须进 `.gitignore`**——里面是应用写入的真实数据，最容易在 `git add -A` 时误入提交。
- 前后端共用的纯逻辑（如启动横幅布局）放 `shared/`，两侧引同一份，避免各写一遍后显示不一致。

## 目录结构基线

```
src/
  views/       页面（路由级）
  components/  可复用组件（布局类再分 layout/）
  composables/ 组合式逻辑
  stores/      Pinia
  core/        与 UI 无关的核心算法（按域分子目录，纯函数单独成文件并配测试）
  utils/       通用工具（ID 生成等公共入口放这里）
  status/      状态 → 文案/样式/类型 的展示映射
  types/       类型定义
  styles/      全局与主题样式
```

两条容易漏的：

- **样式主题分层**：第三方组件库的暗色变量层（官方 `dark/css-vars.css` + `html.dark`，负责兜底）与项目品牌调色层（`dark-theme.scss`，限定在 `html.dark` 作用域）是**两层不同职责，不要合并**。清理样式时最容易把「看起来重复」的那层删掉。
- **同一份内容有多种渲染形态时必须同步**（如列表页与详情页、编辑器与只读预览）。改其中一种渲染必须检查另一种，否则用户在不同入口看到的结果不一致。
