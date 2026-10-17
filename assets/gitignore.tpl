# Dependencies
node_modules/
.pnp
.pnp.js

# Build
dist/
build/
.output/

# Environment
.env
.env.local
.env.*.local

# IDE
.idea/
.vscode/
*.swp
*.swo

# 本地开发/调试日志
.tmp-*
*.log

# AI 工具本地配置（每个 agent 自己的目录，不属于仓库）
.workbuddy/
.zcodeignore
.playwright-cli/

# 运行时数据（含用户/凭据等真实数据，误入提交即泄露）
{{#BACKEND}}server/data/
{{/BACKEND}}data/runtime/

# Windows 下 bash 的 `> nul` 会生成一个名为 nul 的真实文件，而不是丢弃输出
# （同类保留设备名 con/aux/prn/com1-9/lpt1-9 在 bash 里重定向也会建出真实文件，
#   且这类文件建出来可能删不掉，故一并忽略以防误入提交）
nul
con
aux
prn
com[1-9]
lpt[1-9]

# 设计沙箱/探针的临时构建产物：每个都内嵌一份源码快照，一改源码即过期
# 【待填】按本项目实际产物路径补充
design/probe/*bundle.js
