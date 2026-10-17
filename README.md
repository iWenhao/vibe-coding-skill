# new-project-spec

一个 Qoder Skill：把从工业组态平台项目沉淀出来的工程协作约定，变成可复制的产物——`AGENTS.md` 骨架 + 能机械拦截提交的脚本 + 文档地图 + 可选技术栈配置。

约定的内核是**栈无关**的；技术栈只决定额外生成哪些配置文件。所有条目都遵循同一条原则：**能用脚本拦住的，绝不只写成文字规约**。

## 功能特性

- **一句话生成新仓库骨架**：`AGENTS.md`、`CHANGELOG.md`、`README.md`、`docs/`、`.gitignore`、`.env.example`，以及提交信息钩子与超长文件检查脚本。
- **提交信息机械拦截**：`commit-msg` 钩子调用 Node 校验器，标题必须命中前缀白名单且不超 30 字符（汉字算 1 个，按 Unicode 码点计，避开 shell 按字节统计的误判）。
- **给已有仓库体检上规范**：`audit` 按「文件级 / 配置级 / 执行级 / 历史级」四组输出 ✅ 已具备、⬜ 缺失、⚠️ 存在但不合规，只补缺项、不覆盖项目已有约定。
- **可选技术栈落地**：`--stack vue-ts` 额外生成 Vue3 + TypeScript + Vite + Pinia + Element Plus 的完整配置与最小可跑入口；`--backend` 再加一个本地零依赖 Node 存储后端（不启动则前端回落 localStorage）。
- **跨平台的行数阈值检查**：用 `.mjs` 而不是 `.ps1`，CI 与非 Windows agent 同样可跑，计行结果与行尾风格无关。

## 环境要求

- Node ≥ 18（脚本零第三方依赖，不需要 `npm install`）
- Git（钩子通过 `core.hooksPath` 启用）

## 快速开始

### 一行装到本机所有 agent（推荐）

```bash
npx skills add iWenhao/new-project-spec --list   # 先只预览，不写盘
npx skills add iWenhao/new-project-spec          # 交互式勾选装给哪些 agent
```

装进指定 agent、跳过提问：

```bash
npx skills add iWenhao/new-project-spec -g -a claude-code -y
```

`npx skills` 是 Vercel Labs 的开放技能包管理器，支持 70+ 编码 agent，它会把 `skills/new-project-spec/` 整个目录放进各家 agent 的技能目录。

### 手工放置

任何认 [Agent Skills 规范](https://agentskills.io)的 agent，把 `skills/new-project-spec/` 整个目录（含 `SKILL.md`、`scripts/`、`references/`、`assets/`）放进下表位置即可：

| Agent | 用户级 | 项目级（可随仓库提交） | 依据 |
| --- | --- | --- | --- |
| Claude Code | `~/.claude/skills/new-project-spec/` | `.claude/skills/new-project-spec/` | 官方文档实测口径 |
| OpenAI Codex | `~/.agents/skills/new-project-spec/` | `.agents/skills/new-project-spec/` | 官方文档（另有 `/etc/codex/skills`） |
| Cursor | `~/.cursor/skills/new-project-spec/` | `.cursor/skills/new-project-spec/` | 二手来源，未本机验证 |
| Gemini CLI | `~/.gemini/skills/new-project-spec/` | — | 二手来源，未本机验证 |
| Qoder | 随插件分发（`plugins/marketplaces/`），或直接把本仓库作为项目打开 | 同左 | 本机观察 |

调用方式各家不同（Claude Code 自动匹配、Codex 用 `$new-project-spec` 或 `/skills`），但触发都靠 frontmatter 里的 `description`，无需额外配置。

> frontmatter 里的 `when_to_use` 与 `argument-hint` 是 Qoder 用的扩展键；规范要求的是 `name` 与 `description`，不认识扩展键的 agent 直接忽略，不影响触发。

### 不装也能用

技能正文只是操作手册，真正干活的是三个纯 Node 脚本。任何能执行 shell 的 agent（甚至纯手工）都可以直接跑：

```bash
node skills/new-project-spec/scripts/scaffold.mjs \
  --target D:/code/my-app --name my-app --desc "内部工单看板" \
  --stack vue-ts --backend

node skills/new-project-spec/scripts/audit.mjs /path/to/existing-repo   # 体检，退出码 1 = 有缺失项
node skills/new-project-spec/scripts/scaffold.mjs --link-hooks D:/code/my-app
```

生成后 `core.hooksPath` 是**每个克隆执行一次**的本地配置，无法随仓库提交——这一点会写进生成项目的 `AGENTS.md`。


## scaffold 参数

| 参数 | 说明 |
| --- | --- |
| `--target` | 目标目录 |
| `--name` | 项目名（kebab-case） |
| `--desc` | 一句话中文描述 |
| `--stack` | `vue-ts`（默认）或 `none` |
| `--backend` | 附带本地零依赖 Node 存储后端 |
| `--dev-port` / `--api-port` | 前端 / 后端端口 |
| `--force` | 目标已有同名文件时覆盖（默认跳过并告警） |
| `--link-hooks <目录>` | 只启用钩子，不生成骨架 |

## 项目结构

技能放在 `skills/<name>/` 子目录而不是仓库根，是因为 `npx skills` 与各家 plugin 市场按 `<目录>/SKILL.md` 发现技能；仓库根本身只放 README 与 LICENSE。

```
README.md
LICENSE                             MIT
skills/new-project-spec/            ← 一个完整的 Agent Skill，可整目录拷走
  SKILL.md                          入口：模式判断、操作步骤与关键取舍
  scripts/
    scaffold.mjs                    生成骨架；--stack / --backend / --link-hooks
    audit.mjs                       四组检查的体检清单，退出码反映是否有缺失
  assets/
    *.tpl                           AGENTS.md / CHANGELOG / README / docs / gitignore 骨架模板
    scripts/                        拷进新项目的钩子与校验脚本（提交信息、超长文件）
    stack-vue-ts/                   Vue3 + TS + Vite + Pinia 配置模板与最小入口
  references/
    conventions-kernel.md           栈无关约定内核全文
    stack-vue-ts.md                 技术栈落地细节与逐项配置理由
    pitfalls.md                     「环境与已知坑」的写法规约与通用条目
```

脚本用 `import.meta.url` 相对定位资源，所以整目录搬到任何路径、任何机器都能跑；`assets/` 只在 scaffold 时读取，无需预先加载进上下文，`references/` 按需展开——`SKILL.md` 只保留决策所需的主干，这正是渐进式披露（progressive disclosure）的省上下文做法。


## 约定内核

写进新仓库 `AGENTS.md` 时不可缺的七节：常用命令、环境与已知坑、任务清单与进度可见性、工作流约定（分支模型 / 提交前缀白名单 / 版本号只在明确发版时动 / 细节写 CHANGELOG）、代码风格（注释中文且只说「为什么」、三次必收敛、超阈值必拆）、验证节奏（按改动范围分级）、测试（单测与被测文件同目录）。

提交前缀白名单：`功能` `修复` `优化` `重构` `清理` `文档` `测试` `构建` `发版`。
行数阈值：`*.vue` `*.ts` `*.tsx` `*.js` `*.mjs` 400 行，`*.scss` `*.css` 500 行。

## 边界

本 Skill 只造「规范 + 骨架」，不生成领域代码。画布渲染、图元注册、数据源适配器这类业务实现属于源项目自身，不会往新项目里塞。原机器的私有事实（系统代理端口、凭据助手弹窗等）以 `〔本机〕` 标注区分，不带入新仓库。

## 许可证

[MIT](LICENSE)
