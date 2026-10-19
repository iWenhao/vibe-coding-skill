# 部署

## 前置

{{#VUE_TS}}- Node ≥ 18，pnpm
- 构建产物是纯静态文件（`dist/`），可托管到任意静态站点或 Nginx{{#BACKEND}}；后端是零依赖 Node 服务（只用 `node:` 内置模块），可独立部署{{/BACKEND}}
{{/VUE_TS}}
{{^VUE_TS}}- 【待填】运行环境与版本要求
{{/VUE_TS}}

## 构建

```bash
pnpm install
pnpm build
```

产物在 `dist/`，静态托管即可。前端 API 根路径由构建期变量 `VITE_API_BASE` 决定：
同源反代用默认 `/api`；前后端分开部署且不同域时填完整地址（改这个变量必须重新构建，它是构建期注入的）。

{{#BACKEND}}
## 后端服务

```bash
PORT={{API_PORT}} HOST=127.0.0.1 DATA_DIR=/var/lib/{{NAME}}/data node server/index.mjs
```

全部可调项只列在 `.env.example`，本文件不重复那份清单。默认值保守：只监听 `127.0.0.1`、`CORS_ORIGIN` 为 `*`、请求体有上限。
**放开任何一条都必须是显式选择**——跨域上线前把 `CORS_ORIGIN` 改成具体前端站点来源。

`DATA_DIR` 下是 `*.json` 运行时数据，**是应用写入的真实内容，不要提交进仓库、不要放进公开备份**；
容器部署时挂持久卷。
{{/BACKEND}}

## 反向代理要点

- 前端站点把 `/api` 转发到后端端口；
- 改代理目标或后端路由后需重启服务；
- 站点与后端不同域时，除 `VITE_API_BASE` 外还要确认 `CORS_ORIGIN` 已包含前端站点来源。

## 接口错误码

{{#BACKEND}}
存储后端的全部码与归属端点（常量在 `server/lib/apiError.mjs`，**新增码先加常量、再补这张表**）：

| 码 | 状态 | 含义 | 端点 |
| --- | --- | --- | --- |
| `ROUTE_NOT_FOUND` | 404 | 路径不属于本服务——base 配错或代理指到别处 | 任意 `/api/*` |
| `KEY_NOT_FOUND` | 404 | 路径正确、这个键确实没写过 | `GET /api/storage/:key` |
| `UNAUTHORIZED` | 401 | 设了 `AUTH_TOKEN` 而 Bearer 缺失或不匹配 | 除 `/health` 外全部 |
| `METHOD_NOT_ALLOWED` | 405 | 路径认得、方法不支持；`error.meta.allowed` 给允许的方法 | `/api/storage/:key` |
| `MALFORMED_JSON` | 400 | 请求体不是合法 JSON | `PUT` |
| `INVALID_VALUE` | 400 | `value` 不是字符串 | `PUT` |
| `BODY_TOO_LARGE` | 413 | 请求体超过 `MAX_BODY_BYTES` | `PUT` |
| `INTERNAL` | 500 | 未预期异常；原始文案只进服务端日志，不回显 | 全部 |

两个 404 分成不同码是刻意的：只看状态码的调用方会把「配错了」读成「数据本来没有」，症状是无报错的空结果。
`/health` 与 `/api/health` 都回 `200`、不鉴权，前端在线探测**只看状态码、不拆信封**（约定里点名的例外之一）。

**这张表不登记 message**——文案可随时改动，写进表就等于邀请调用方去断言它。
{{/BACKEND}}
{{^BACKEND}}
【待填】本项目若对外暴露端点，在这里登记错误码：一行一码（码 / HTTP 状态 / 含义 / 哪个端点会返回），
**不写给人读的文案**（约定见 AGENTS.md「代码风格」，调用方只比码）。当前形态没有对外端点，本节可整段删掉。
{{/BACKEND}}

## 验证部署成功

【待填】一条能证明「前后端连通」的最小检查（如登录接口 200、存储读写一次往返），
以及看哪个日志/横幅判断后端真的起来了。
