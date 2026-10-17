# 前端构建时注入（vite build / dev 会读取；改这些值必须重新构建，它们是构建期替换的）
# 存储后端 API 根路径。同源反代用默认 /api；前后端分开部署且不同域时填完整地址
VITE_API_BASE=/api

# 可选「服务主密钥」，与后端 AUTH_TOKEN 一致。日常请留空，用登录会话
# （仅探针/CI 等无浏览器场景使用）
VITE_API_TOKEN=

{{#BACKEND}}
# —— 后端 node server/index.mjs ——
PORT={{API_PORT}}
# 监听地址，默认 127.0.0.1（只本机可访问）。容器/局域网部署改 0.0.0.0
# HOST=0.0.0.0
# 数据目录（容器部署时挂持久卷）。默认 server/data
# DATA_DIR=/var/lib/{{NAME}}/data
# 请求体上限（字节），默认 20971520 (20MB)
MAX_BODY_BYTES=20971520
# 允许的跨域来源，逗号分隔。默认 *（仅建议内网）；生产建议填前端站点
# 例: https://app.example.com
CORS_ORIGIN=*
# 可选服务主密钥（Bearer）。设置后该 Token 拥有全部权限；登录会话仍可用
# 生产建议设置，并妥善保管；账号体系见 DATA_DIR/_users.json（scrypt 哈希）
# AUTH_TOKEN=change-me
# 首次运行时种子账号的初始口令。留空则随机生成并打印在启动日志里（推荐）
# SEED_PASSWORD=
# 对外 HTTP 出口是否允许发往内网/回环地址。默认 0（拦截，防 SSRF）；
# 现场 webhook 就在内网时设 1
# NOTIFY_ALLOW_PRIVATE=0
# 外部 HTTP 请求超时（毫秒），默认 10000
# NOTIFY_TIMEOUT_MS=10000
# 邮件是否校验服务器证书，默认 1（校验）。自签证书服务器设 0
# SMTP_REJECT_UNAUTHORIZED=1
{{/BACKEND}}
