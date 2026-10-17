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

全部可调项见 `.env.example`。安全默认值（**放开必须是显式选择**）：

- 只监听 `127.0.0.1`；
- `CORS_ORIGIN` 默认 `*` 仅建议内网使用，生产填前端站点；
- 通知类 HTTP 出口默认拦截内网/回环地址（防 SSRF），`NOTIFY_ALLOW_PRIVATE=1` 才放开；
- 请求体上限 `MAX_BODY_BYTES`，防止上传打满内存；
- 可选服务主密钥 `AUTH_TOKEN`（Bearer），与前端 `VITE_API_TOKEN` 一致。

`DATA_DIR` 下是 `*.json` 运行时数据，**含用户与凭据信息，不要提交进仓库、不要放进公开备份**；
容器部署时挂持久卷。
{{/BACKEND}}

## 反向代理要点

- 前端站点把 `/api` 转发到后端端口；
- 改代理目标或后端路由后需重启服务；
- 站点与后端不同域时，除 `VITE_API_BASE` 外还要确认 `CORS_ORIGIN` 已包含前端站点来源。

## 验证部署成功

【待填】一条能证明「前后端连通」的最小检查（如登录接口 200、存储读写一次往返），
以及看哪个日志/横幅判断后端真的起来了。
