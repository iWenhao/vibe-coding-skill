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

**只记一条也够用：`.agents/skills/new-project-spec/`（用户级 `~/.agents/skills/new-project-spec/`）。** 这个共用目录被 Codex、Cursor、Gemini CLI、OpenCode、Pi、Grok Build、Muse Code、DeepSeek Harness、MiMo Code、Antigravity、Kimi Code、Trae 十二家的官方文档确认会扫——一处放置，十二家通吃（Trae 要先打开开关，见下表）。

官方文档确认（可直接依赖）：

| Agent | 项目级 | 用户级 | 备注 |
| --- | --- | --- | --- |
| Claude Code | `.claude/skills/new-project-spec/` | `~/.claude/skills/new-project-spec/` | 斜杠命令与自动匹配两种都有 |
| OpenAI Codex | `.agents/skills/…` | `~/.agents/skills/…` | 另有管理级 `/etc/codex/skills`；用 `$new-project-spec` 或 `/skills` |
| Cursor | `.cursor/skills/…` 或 `.agents/skills/…` | `~/.cursor/skills/…` 或 `~/.agents/skills/…` | `/` 调用，或钉成 Custom Mode |
| Gemini CLI | `.gemini/skills/…` 或 `.agents/skills/…` | `~/.gemini/skills/…` 或 `~/.agents/skills/…` | 自动触发前会先弹一次审批 |
| OpenCode | `.opencode/skills/…`，另认 `.claude/skills/…`、`.agents/skills/…` | `~/.config/opencode/skills/…`，另认 `~/.claude/skills/…`、`~/.agents/skills/…` | 项目级从当前目录向上遍历到 git worktree 根；frontmatter 只识别 `name`/`description`/`license`/`compatibility`/`metadata`，未知字段忽略；`name` 必须与所在文件夹名一致 |
| Pi Coding Agent（Earendil 开源） | `.agents/skills/…`，项目级会向上遍历到仓库根 | `~/.agents/skills/…`；Pi 自家的 user/project skills 目录官方说可由 settings、packages 配置，该页未写默认值 | 官方文档原话：「Pi also supports the Agent Skills locations `~/.agents/skills/` and `.agents/skills/`」；**明确不读 `.claude/skills/`**；frontmatter 认 `name`/`description`/`license`/`compatibility`/`metadata`/`allowed-tools`/`disable-model-invocation`，未知字段忽略；`npm i -g --ignore-scripts @earendil-works/pi-coding-agent`，MIT |
| Grok Build（xAI，命令名 `grok`） | `.grok/skills/…`（当前目录优先级最高，仓库根次之），另扫 `.agents/skills/…`、`.claude/skills/…`、`.cursor/skills/…` | `~/.grok/skills/…`，另扫 `~/.agents/skills/…`、`~/.claude/skills/…`、`~/.cursor/skills/…` | 官方用户指南 `crates/codegen/xai-grok-pager/docs/user-guide/08-skills.md` 原话：「Grok also scans `.agents/skills/` (and `commands/`) at each tier (alongside `.grok/`) and walks every directory between your working directory and the repo root」；`.claude`/`.cursor` 默认也扫，要在 `~/.grok/config.toml` 的 `[compat.claude]`/`[compat.cursor]` 里设 `false` 才停；未信任的目录启动时不加载其技能；再加目录用 `[skills] paths` |
| Muse Code（Meta，命令名 `muse`） | `.agents/skills/…`，另扫 `.claude/skills/…`、`.codex/skills/…` | `~/.agents/skills/…`、`$XDG_CONFIG_HOME/muse/skills/…`，另扫 `~/.claude/skills/…`、`$CODEX_HOME/skills/…`（未设时回落 `~/.codex/skills`） | 官方文档 `dev.meta.ai/docs/muse-code/extending` 原话：「Skills load from four sources: **User** in `$XDG_CONFIG_HOME/muse/skills` and `~/.agents/skills`, and **Project** under `<repo>/.agents/skills/<skill-id>/SKILL.md`」；配套 `muse skills list/inspect/enable/validate/install`，`muse skills import --from claude|codex` 能把已有技能平迁进来；首次进工作区会问是否 trust，不 trust 就不加载它的 skills/rules/hooks。社区实测说公测仅 macOS/Linux，官方该页未写 Windows 支持情况 |
| DeepSeek Harness（`dsh`，开源） | 按 rank 扫六个根：`<项目根>/.dsh/skills`(100) → `<项目根>/.agents/skills`(200) → `Config.customSkillDirs`(300) → `<dshHome>/skills`(400) → `<agentsHome>/skills`(500) → 随包目录(600) | 用户级即 `<dshHome>/skills` = `~/.dsh/skills`、`<agentsHome>/skills` = `~/.agents/skills` | 官方架构文档 `deepseek-harness.github.io/deepseek-harness/reference/subsystems/skills` 的「本地发现优先级」表原样给出这六个根，rank 越小越优先；`dshHome` 默认 `$DSH_HOME` 或 `~/.dsh`、`agentsHome` 默认 `$DSH_AGENTS_HOME` 或 `~/.agents`；项目根＝含 `.git` 的最近祖先目录，找不到就用当前 cwd。**两种形状都认**：`<name>/SKILL.md` 或扁平 `<name>.md`，但官方明写「嵌套递归的 `**/SKILL.md` 发现不受支持」，所以别把整个仓库丢进去；名称必须是 kebab-case（`^[a-z0-9]+(?:-[a-z0-9]+)*$`）；喂给模型的目录只取 `name` 加 `description`，`description` 截断长度由 `catalogDescriptionMaxLength` 控制、默认 500；根目录有 watcher，改正文热更新不用重启；它的 AGENTS.md 走 user 角色消息注入，不像 OpenCode 那样塞进系统提示词，感知强度不同 |
| Antigravity（谷歌） | `.agents/skills/…` | `~/.gemini/config/skills/…`；CLI 版另在 `~/.gemini/antigravity-cli/skills/` | `.agents/` 下 rules（常驻）、skills（按 description 匹配）、workflows（`/` 触发）是分开的三层，别把技能写进 rules |
| MiMo Code（小米） | `.mimocode/skills/…`，单数 `skill/` 亦认、递归发现；另兼容 `.claude`/`.agents`/`.codex`/`.opencode` | `~/.config/mimocode/skills/…` | 官方明确未识别的 frontmatter 字段一律忽略；技能名取自 frontmatter 而非文件夹名，重名后加载者胜 |
| CodeBuddy（腾讯） | `.codebuddy/skills/…` | `~/.codebuddy/skills/…` | 另有 `CodeBuddy.md` 上下文文件，属兜底路线 |
| WorkBuddy Enterprise（腾讯） | `.codebuddy/skills/…` | 官方未写用户级 | 腾讯云文档中心 WorkBuddy Enterprise → Skills 页原话：「创建目录：在 `.codebuddy/skills/` 下创建新的 Skill 目录」——和 CodeBuddy 共用同一套目录。**这只覆盖 Enterprise 版**：桌面消费版 WorkBuddy 的厂商口径仍是界面「添加技能」（上传含 `SKILL.md` 的目录或 ZIP、技能市场、让 AI 帮你创建），社区教程另说 `~/.workbuddy/skills/` 与项目 `./.workbuddy/skills/` 也认，那部分属二手 |
| Trae（字节） | `.trae/skills/…`，或 `.agents/skills/…` | 国内版 `~/.trae-cn/skills/…`（Windows 为 `%userprofile%/.trae-cn/skills`） | 走 `.agents/skills/` 必须先在 设置 → 技能与命令 → 导入设置 打开「启用 .agents 技能目录」；AGENTS.md 只在 TRAE Work 里有，且要在 设置 → 规则 → 导入设置 打开 |
| 通义灵码 | `.lingma/skills/…` | `~/.lingma/skills/…` | — |
| Kimi Code CLI / Desktop | `.kimi-code/skills/…` 或 `.agents/skills/…` | `$KIMI_CODE_HOME/skills/…` 或 `~/.agents/skills/…` | 目录可用 `--skills-dir` 覆盖。Desktop 1.0（2026-09-21，macOS/Windows，入口 `kimi.com/code`）与 CLI 共用账号和额度，官方文档未单独公布桌面版技能目录——按同一套路径放置即可，这点属推断 |
| ZCode（智谱） | `.zcode/skills/…` | `~/.zcode/skills/…` | — |
| 千问办公（阿里） | 官方未公布项目级目录 | `~/.qwenworkcn/skills/…` | 官方文档原话：技能是「包含 `SKILL.md` 的文件夹，存放于 `~/.qwenworkcn/skills/`」且「可直接在文件系统中增删和编辑」；另有对话安装（把仓库地址发给它）、技能广场、界面上传三条路。它把技能当跨会话的全局资产，不跟仓库走 |

（表中 `…` 一律代表 `new-project-spec`。）

只有二手口径，或厂商只承认「有技能能力」、没公布目录（路径取自 `npx skills` 的 `src/agents.ts` 或社区实测，**不等于厂商承诺**）：

| Agent | 用户级 · 项目级 | 实测到的限制 |
| --- | --- | --- |
| MiniMax Code | `~/.minimax/skills` · `.minimax/skills` | 官方文档确认「有技能功能」，但**从头到尾没写出该把 `SKILL.md` 放进哪个目录**，这两个路径只在安装器清单里出现过——CLI 全部九页文档、桌面端各页、开源仓库 `MiniMax-AI/minimax-code` 的 docs 都翻过，没有一处给目录。官方给的替代口径有三条：① changelog v3.0.33（2026-05-29）原话「Skill Auto-Discovery: Automatically scans and imports existing skills from Claude Code, Codex, and other AI coding tools — no manual reinstall needed」，也就是说别的工具的 `SKILL.md` 会被它扫进去，但"导入"是直接读还是复制入库，官方没写；② 技能作为**插件包**交付——包内 `skills/<skill-name>/SKILL.md`，逐条列进 `.minimax-plugin/plugin.json` 的 `skills` 数组，frontmatter 的 `name` 必须与目录一致、`description` 非空；③ CLI（`MiniMax-AI/minimax-code`，命令 `mcode`）的数据根 `~/.minimax` 官方原话「stores configuration, sessions, logs, plugins, skills, and other runtime data」，`MINIMAX_DATA_DIR` 可改，TUI 里 `/skills [filter]` 查已发现的技能。侧面印证：MiniMax 自己的 `MiniMax-AI/skills` 仓库只教怎么装进 Claude Code、Cursor、Codex、OpenCode，没有一条装进 MiniMax Code 的说明。另注意桌面端（`agent.minimax.io/docs/code`）与 CLI 是两条产品线，别混 |
| Qwen Code | `~/.qwen/skills` · `.qwen/skills` | 同上，取自安装器清单 |
| Qoder | `~/.qoder/skills` · `.qoder/skills` | 随插件分发亦可 |
| CatPaw IDE / 妙手（美团） | 未查到 `SKILL.md` 技能目录 | 两个产品别混：「妙手」是 CatPaw 在 2026-09-20/21 启用的中文名，指 `catpaw.meituan.com` 的 AI 经营工作台（App/Web），它的「专家与技能」是美团自己封装的行业能力，不是让第三方往里放 `SKILL.md`；面向编程的 CatPaw IDE（公测 2025-11-10）官方可查证的扩展只有 `.catpaw/rules` 规则目录与 MCP。给它用本技能请走下面「不装也能用」那条路 |
| 豆包 / 豆包工作（字节） | 上传为主；本地目录官方只写作「设备本地公共 `agents.skill` 文件目录」，未给确切路径 | 《豆包工作任务功能须知》原文把「你设备本地公共 agents.skill 文件目录下已安装技能」列为可调用来源之一，并承诺「本地技能本身不会上云，我们仅在当前设备上、且当任务执行需要时结合对应技能说明文档进行调用」——所以只有选**本地电脑**模式才读得到它，走云电脑模式读不到。安装：电脑版进 技能·连接器·伙伴 → 我的技能 → 新建 → 上传技能，把含 `SKILL.md` 的目录或 ZIP 直接拖进去、不用解压；调用是在「工作」模式输入框敲 `/`（不是聊天窗口）。手机 App 无安装入口，只能远程给电脑派活。「豆包工作」是脱胎于豆包「工作任务」模式的独立 PC 客户端（删掉了聊天模块），账号与专业版额度跟豆包互通、技能入口一致。客户端版本过旧会让技能按钮变灰。本技能的脚本要跑 Node，而官方未承诺终端执行权限，先只试只读的 `audit` |

> 表里没有不等于不存在：`npx skills` 的清单只是安装器支持的 target，厂商自己支持什么以其文档为准；反过来，一个品牌下往往同时有消费版、企业版和 CLI 好几个产品，官方给某个版本写明的目录，不能直接算到别的版本头上（WorkBuddy 就是例子——Enterprise 版有官方目录，桌面消费版仍只有界面上传那条路）。

调用方式各家不同：Claude Code 与 Cursor 是斜杠命令加自动匹配，Codex 用 `$new-project-spec` 或 `/skills`，Gemini CLI 自动触发前会先弹一次审批。共同点是都靠 frontmatter 的 `description` 匹配，不需要额外注册。

> 规范只把 `name` 与 `description` 定为必填，`license`、`compatibility`、`metadata` 是可选字段——本技能带的 `license: MIT` 属于规范内，OpenCode 的官方文档明确会识别。真正超出规范的是 `when_to_use` 和 `argument-hint`——Claude Code 认，Grok Build 也认（它的键写作 kebab 的 `when-to-use`，另外还吃 `user-invocable`、`disable-model-invocation`），其余 agent 一律忽略（MiMo Code 与 OpenCode 对这点都写得很直白）。一个例外：走 claude.ai / API 的技能打包会对非规范键报错，命令行用法不受影响——若要上架那类市场，先删掉这两个扩展键。

### 装完怎么用

装好后在 agent 里说人话即可——技能正文开头有一张模式判断表，agent 读到它自己会选模式：

- **新建**：「帮我新建一个项目，叫 `my-app`，是个内部工单看板，用 Vue3 栈、带个本地后端」→ 走 scaffold。四项输入（项目名 / 一句话描述 / 技术栈 / 要不要后端）缺了会**一次问齐**，不逐个追问。
- **体检**：「给这个仓库上规范，缺什么补什么，别动我已有的约定」→ 走 audit。只补缺项、不覆盖既有约定，输出按四组给出 ✅ 已具备 / ⬜ 缺失 / ⚠️ 存在但不合规。

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

本 Skill 只造「规范 + 骨架」，不生成领域代码。画布渲染、图形元素注册、数据源适配器这类业务实现属于源项目自身，不会往新项目里塞。原机器的私有事实（系统代理端口、凭据助手弹窗等）以 `〔本机〕` 标注区分，不带入新仓库。

## 许可证

[MIT](LICENSE)
