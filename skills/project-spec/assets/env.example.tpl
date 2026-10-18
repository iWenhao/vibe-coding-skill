# 前端构建时注入（vite build / dev 会读取；改这些值必须重新构建，它们是构建期替换的）
# 存储后端 API 根路径。同源反代用默认 /api；前后端分开部署且不同域时填完整地址
VITE_API_BASE=/api

# 可选「服务主密钥」，与后端 AUTH_TOKEN 一致。日常请留空，用登录会话
# （仅探针/CI 等无浏览器场景使用）
VITE_API_TOKEN=

{{#BACKEND}}
# —— 后端 node server/index.mjs ——
# 本段是后端**全部**可调项：只列 server/index.mjs 真正读取的变量，
# 加一项就同步加一行注释，别在这里写代码没实现的开关。
PORT={{API_PORT}}
# 监听地址，默认 127.0.0.1（只本机可访问）。容器/局域网部署才改 0.0.0.0
# HOST=0.0.0.0
# 数据目录（容器部署时挂持久卷）。默认 server/data
# DATA_DIR=/var/lib/{{NAME}}/data
# 请求体上限（字节），默认 20971520 (20MB)
MAX_BODY_BYTES=20971520
# 允许的跨域来源，逗号分隔。默认 *（仅建议内网）；生产建议填前端站点，例: https://app.example.com
CORS_ORIGIN=*
# 可选服务主密钥（Bearer）。设置后 /api/* 全部要求携带它，/health 除外（前端靠它探测在线）
# AUTH_TOKEN=change-me
{{/BACKEND}}
