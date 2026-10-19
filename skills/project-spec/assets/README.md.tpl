# {{TITLE}}

{{DESC}}

技术栈与架构决策见 [AGENTS.md](AGENTS.md)；使用者操作手册见 [docs/USER_GUIDE.md](docs/USER_GUIDE.md)；部署见 [docs/DEPLOY.md](docs/DEPLOY.md)；改动来由见 [CHANGELOG.md](CHANGELOG.md)。

## 功能特性

【待填】按用户能感知的能力列，不要列内部模块名。

## 系统架构

【待填】一张 ASCII/mermaid 图 + 数据流向说明。这一节同时是二次开发的入口地图：
新读者应该能从这里推断「我要改 X，去看哪个目录」。

## 快速开始

{{#VUE_TS}}
```bash
pnpm install
pnpm dev{{#BACKEND}}      # 另开一个终端：pnpm server（存储后端，不启动则回落 localStorage）{{/BACKEND}}
```

浏览器打开 http://localhost:{{DEV_PORT}} 。

```bash
npx vitest run    # 单次跑测试（pnpm test 是 watch 模式）
pnpm build        # 生产构建 = 类型检查 + 打包
```

启用钩子（每个克隆执行一次，是本地配置、无法随仓库提交）。一条命令同时接上两条钩子：`commit-msg` 拦提交信息与「重要文件动了而 README 没同步」，`pre-push` 在推送前自动跑全量把关（全量测试 + 类型检查 + 构建 + 行数检查，任一步失败即中止）：

```bash
git config core.hooksPath scripts/hooks
```
{{/VUE_TS}}
{{^VUE_TS}}
【待填】install / dev / test / build 四条命令，以及「每个克隆执行一次」的本地配置（如 `git config core.hooksPath scripts/hooks`）。
{{/VUE_TS}}

## 项目结构

【待填】目录树 + 每行一句职责说明。与 AGENTS.md「架构与扩展点」不重复：这里给静态结构，那里给「改动该怎么走」。

## 二次开发指南

【待填】高频扩展的样板文件路径与注册步骤（与 AGENTS.md 同一套，此处面向人类读者展开）。

## 许可证

【待填】见 LICENSE。
