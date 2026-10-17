# new-project-spec

> 仓库名是 `vibe-coding-skill`,技能名仍是 `new-project-spec`(`skills/new-project-spec/`),两者不一致——安装命令用前者,`--skill` 与放置目录用后者。

一个符合 [Agent Skills 规范](https://agentskills.io)的 Skill：把工程协作约定变成可复制的产物——`AGENTS.md` 骨架 + 能机械拦截提交的脚本 + 文档地图 + 可选技术栈配置。

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
npx skills add iWenhao/vibe-coding-skill --list   # 先只预览，不写盘
npx skills add iWenhao/vibe-coding-skill          # 交互式勾选装给哪些 agent
```

装进指定 agent、跳过提问：

```bash
npx skills add iWenhao/vibe-coding-skill -g -a claude-code -y
```

`npx skills` 是 Vercel Labs 的开放技能包管理器，支持 70+ 编码 agent，它会把 `skills/new-project-spec/` 整个目录接进各家 agent 的技能目录。

本机实测过的参数（`npx skills add --help`）：`-l/--list` 只预览不写盘、`-g` 用户级、`-a <agents>` 指定 agent（`*` 为全部）、`-s <skill>` 指定技能、`-y` 跳过提问、`--all` = `--skill '*' --agent '*' -y`。

**Windows 建议加 `--copy`**：默认用符号链接把技能接进各家目录，非管理员/未开开发者模式的机器上可能建不出来；`--copy` 直接拷文件，代价是升级要重装。


### 手工放置

任何认 [Agent Skills 规范](https://agentskills.io)的 agent，把 `skills/new-project-spec/` 整个目录（含 `SKILL.md`、`scripts/`、`references/`、`assets/`）放进它的技能目录即可。

**只记一条也够用：`.agents/skills/new-project-spec/`（用户级 `~/.agents/skills/new-project-spec/`）。** 这个共用目录被 Codex、Cursor、Gemini CLI、MiMo Code、Antigravity、Kimi Code CLI 六家的官方文档确认会扫——一处放置，六家通吃。

官方文档确认（可直接依赖）：

| Agent | 项目级 | 用户级 | 备注 |
| --- | --- | --- | --- |
| Claude Code | `.claude/skills/new-project-spec/` | `~/.claude/skills/new-project-spec/` | 斜杠命令与自动匹配两种都有 |
| OpenAI Codex | `.agents/skills/…` | `~/.agents/skills/…` | 另有管理级 `/etc/codex/skills`；用 `$new-project-spec` 或 `/skills` |
| Cursor | `.cursor/skills/…` 或 `.agents/skills/…` | `~/.cursor/skills/…` 或 `~/.agents/skills/…` | `/` 调用，或钉成 Custom Mode |
| Gemini CLI | `.gemini/skills/…` 或 `.agents/skills/…` | `~/.gemini/skills/…` 或 `~/.agents/skills/…` | 自动触发前会先弹一次审批 |
| Antigravity（谷歌） | `.agents/skills/…` | `~/.gemini/config/skills/…`；CLI 版另在 `~/.gemini/antigravity-cli/skills/` | `.agents/` 下 rules（常驻）、skills（按 description 匹配）、workflows（`/` 触发）是分开的三层，别把技能写进 rules |
| MiMo Code（小米） | `.mimocode/skills/…`，单数 `skill/` 亦认、递归发现；另兼容 `.claude`/`.agents`/`.codex`/`.opencode` | `~/.config/mimocode/skills/…` | 官方明确未识别的 frontmatter 字段一律忽略；技能名取自 frontmatter 而非文件夹名，重名后加载者胜 |
| CodeBuddy（腾讯） | `.codebuddy/skills/…` | `~/.codebuddy/skills/…` | 另有 `CodeBuddy.md` 上下文文件，属兜底路线 |
| Trae（字节） | `.trae/skills/…` | 国内版 `~/.trae-cn/skills/…` | AGENTS.md 只在 TRAE Work 里有，且要先在 设置→规则→导入设置 打开 |
| 通义灵码 | `.lingma/skills/…` | `~/.lingma/skills/…` | — |
| Kimi Code CLI | `.kimi-code/skills/…` 或 `.agents/skills/…` | `$KIMI_CODE_HOME/skills/…` 或 `~/.agents/skills/…` | 目录可用 `--skills-dir` 覆盖 |
| ZCode（智谱） | `.zcode/skills/…` | `~/.zcode/skills/…` | — |

（表中 `…` 一律代表 `new-project-spec`。）

只有二手口径（路径取自 `npx skills` 的 `src/agents.ts` 或社区实测，**不等于厂商承诺**）：

| Agent | 用户级 · 项目级 | 实测到的限制 |
| --- | --- | --- |
| DeepSeek Harness | `~/.dsh/skills` · `.dsh/skills`，以及 `~/.agents/skills` · `.agents/skills` | 技能发现只扫根目录直属层，**不递归 `**/SKILL.md`**——本技能的目录形状正好符合，但别把整个仓库丢进去；`description` 截断 500 字符；不在 `npx skills` 清单，需社区适配器 `dsh-skills-nexus` 注册；AGENTS.md 走用户消息注入，与 OpenCode 塞系统提示词的感知强度不同 |
| MiniMax Code | `~/.minimax/skills` · `.minimax/skills` | 官方文档确认「有技能功能」，但这两个目录只在安装器清单里出现过，路径未证实 |
| Qwen Code | `~/.qwen/skills` · `.qwen/skills` | 同上，取自安装器清单 |
| Qoder | `~/.qoder/skills` · `.qoder/skills` | 随插件分发亦可 |

> 表里没有不等于不存在：`npx skills` 的清单只是安装器支持的 target，厂商自己支持什么以其文档为准。还有两类要分开看：**WorkBuddy（腾讯）与千问办公确实有技能体系，但入口是网页/客户端上传，不是往仓库放目录**——对它们得把技能目录打包上传；**豆包专业版/工作版**的官方说明里包含「设备本地公共 agents skills 目录下已安装技能」，只是目录名未公开；**豆包消费版**两者都没有，跑不了本技能。

调用方式各家不同：Claude Code 与 Cursor 是斜杠命令加自动匹配，Codex 用 `$new-project-spec` 或 `/skills`，Gemini CLI 自动触发前会先弹一次审批。共同点是都靠 frontmatter 的 `description` 匹配，不需要额外注册。

> 规范只要求 `name` 与 `description`。本技能 frontmatter 另带的 `license`、`when_to_use`、`argument-hint` 里，`when_to_use` 是 Claude Code 认的字段，其余会被忽略（MiMo Code 的官方文档对这点写得很直白）。一个例外：走 claude.ai / API 的技能打包会对非规范键报错，命令行用法不受影响——若要上架那类市场，先删掉这三个扩展键。

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

技能放在 `skills/<name>/` 子目录而不是仓库根，是各家 plugin 市场与 `vercel-labs/agent-skills` 这类仓库的通用约定，便于按目录发现；各家 agent 与 `npx skills` 认的都是这个形状。注意各家扫 `SKILL.md` 的深度不一样（见上表 DeepSeek Harness 那行：只扫直属层），而安装器把技能摊平成 `<agent>/skills/new-project-spec/` 后正好每家都满足——这也是为什么手工放置时同样别把整个仓库塞进技能目录。

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
