---
name: new-project-spec
license: MIT
description: 用一套栈无关的工程协作约定，快速新建项目仓库或给已有仓库补齐规范约束。两种模式——scaffold 生成带 AGENTS.md 骨架、提交信息机械拦截钩子、超长文件检查脚本、CHANGELOG 与版本规则、文档地图，以及可选 Vue3+TypeScript+Vite+Pinia+Element Plus 技术栈配置的新仓库；audit 按文件级/配置级/执行级/历史级四组体检已有仓库，只补缺项、不覆盖既有约定。当用户说「新建一个项目/仓库」「补一份 AGENTS.md」「约束提交信息、版本号、变更日志」「这个项目规不规矩/该上规范了」「把这套约定搬到别的项目」时使用。
when_to_use: 新项目起步需要工程约定，或已有仓库要补齐 AGENTS.md、提交钩子与收尾检查
argument-hint: <新项目目录> | audit [已有项目目录]
---

# New Project Spec

## Overview

把「一个仓库该怎么被 AI 代理和新人协作」变成可复制的产物：`AGENTS.md` 骨架 + 能机械拦截的检查脚本 + 文档地图 + 可选技术栈配置。

约定内核是**栈无关**的；技术栈只决定生成哪些配置文件。所有约定都遵循同一条原则：**能用脚本拦住的，绝不只写成文字规约**。

## 先判断模式

| 用户表述 | 模式 |
| --- | --- |
| 新建 / 起一个 / 从 0 开始 / 换个项目也要这套 | **scaffold**（生成骨架） |
| 检查 / 补齐 / 上规范 / 搬到已有仓库 / 这项目规不规范 | **enforce**（体检 + 补缺） |

不明确时问一句，别猜——两种模式动的项目不是同一个。

路径约定：下文 `<skill-dir>` 指本 Skill 所在目录的绝对路径，`<node>` 指当前可用的 Node（≥18）。

## 模式一：新建项目骨架

**第 1 步——凑齐 4 个输入，缺的一次问完**（不要逐个追问）：项目名（kebab-case）、一句话中文描述、技术栈（`vue-ts` 或 `none`）、有没有本地零依赖后端（决定 `--backend`）。

**第 2 步——生成**：

```bash
node <skill-dir>/scripts/scaffold.mjs \
  --target D:/code/my-app --name my-app --desc "内部工单看板" \
  --stack vue-ts --backend
```

可选：`--dev-port 5173` `--api-port 5174` `--force`（目标目录已有同名文件时默认跳过并告警，`--force` 才覆盖）。

产物：`AGENTS.md` `CHANGELOG.md` `README.md` `docs/{USER_GUIDE,DEPLOY}.md` `.gitignore` `.env.example`、`scripts/{commit-msg-check.mjs,check-long-files.mjs,hooks/commit-msg}`，`--stack vue-ts` 时再加 `package.json` `tsconfig*.json` `vite.config.ts` `vitest.config.ts` `eslint.config.js` `pnpm-workspace.yaml` 与 `src/` 最小可跑入口。

**第 3 步——脚本生成不了的两节，必须人工补**，否则 AGENTS.md 只是空壳：

- **「架构与扩展点」**：这个项目最高频的改动是什么？给出「照哪个文件抄格式 + 分几步注册 + 同步哪些文档」的具体路径。新仓库还没有扩展点时，先写成待填清单，别编造。
- **「环境与已知坑」**：先只写**写法规约**（通用坑 vs `〔本机〕` 标注，见 `references/pitfalls.md`），坑要靠实跑积累，不要在第一天硬凑。

**第 4 步——首次安装**（脚本会给提示，按顺序执行）：

```bash
git init
node <skill-dir>/scripts/scaffold.mjs --link-hooks <target>   # 或手工 git config core.hooksPath scripts/hooks
pnpm install
pnpm build && npx vitest run
```

`core.hooksPath` 是**每个克隆执行一次**的本地配置，不能提交代替；这一点必须在 AGENTS.md 与汇报里都说清。

**第 5 步——验证钩子真的会拦截**（不验证就等于没装）：

写一条注定超长的标题喂给校验脚本，确认它拒绝：

```bash
cd <target> && node -e "require('fs').writeFileSync('../msg-probe.txt','功能: 这条提交信息故意写得很长很长用来验证钩子确实会拒绝这次提交')"
node <target>/scripts/commit-msg-check.mjs ../msg-probe.txt; echo "exit=$?"
```

期望 `exit=1` 并报「标题 33 字符，超出上限 30 字符」（这条是实测过的，正好命中超长分支——顺带写带前缀但不超长的样例只会命中「未知前缀」，测不到长度那道）。验证完删掉 `msg-probe.txt`。绿灯不代表脚本正确，**红灯才代表**。

文档同步拦截同法验证：在仓库里改一行 `package.json` 并 `git add`（不动 README），跑 `node <target>/scripts/commit-msg-check.mjs <合法信息文件>`，期望 `exit=1` 且报「重要文件改动但 README.md 未同步」；再往信息文件加一行 `[skip-docs]` 重跑，期望 `exit=0`。两条都红绿分明才算装好。

## 模式二：给已有项目上规范

**第 1 步——体检**：

```bash
node <skill-dir>/scripts/audit.mjs [目标目录，默认当前]
```

输出按「文件级 / 配置级 / 执行级 / 历史级」分组，✅ 已具备、⬜ 缺失、⚠️ 存在但不合规（含超长文件清单与历史提交不合规抽样）。退出码 1 表示有缺失项。

**第 2 步——只补缺，不覆盖**。已有项目往往有自己的约定变体（前缀不同、版本号规则不同）：

- 先读现有 `AGENTS.md`/`package.json`/`.gitignore`，**与待补文件 diff**；
- 语义冲突（如前缀白名单、分支模型）以项目现有约定为准，改 asset 里的常量而不是改项目历史；
- 纯缺失（压根没有钩子/检查脚本）才直接拷贝；
- 不重构与规范无关的代码，不为了让检查变绿而拆分与本次无关的历史超长文件（既有欠账只如实列出）。

**第 3 步——回填项目特有内容**：同模式一第 3 步。

**第 4 步——复跑 audit 并把两份输出都贴给用户**（补之前 / 补之后），让他看见差值。用户可见清单用 `✅ 已完成 / 🔄 进行中 / ⬜ 未开始`。

## 约定内核

写进新仓库 AGENTS.md 时不可缺的七节（细则见 [references/conventions-kernel.md](references/conventions-kernel.md)）：

1. **常用命令**——只列命令，门槛指向「验证节奏」，两处不重复。
2. **环境与已知坑**——仓库属性 vs `〔本机〕` 分开标注，换机器不照搬。
3. **任务清单与进度可见性**——多步任务必须有对用户可见的清单，开工与收尾各附一份。
4. **工作流约定**——分支模型、一个功能一个提交、提交信息前缀白名单 + 标题 ≤30 **字符**（汉字算 1）、细节写 CHANGELOG、重要文件改动同轮同步 README（钩子拦截）、版本号只在明确发版时动。
5. **代码风格**——注释中文且只说「为什么」；先找现成的、**三次必收敛**；超阈值必拆。
6. **验证节奏**——按改动范围分级的表格，含「用户可见输出必须真跑一次」这条优先级最高的例外。
7. **测试**——单测放被测文件同目录；核心逻辑补测，UI 不强求但改 UI 要浏览器实测。

技术栈相关细节（strict 四件套、ESLint flat 双块、vitest include、unplugin dts、服务端 tsconfig、前端可选后端与回落存储）见 [references/stack-vue-ts.md](references/stack-vue-ts.md)。

## 关键取舍

生成或补齐前先照这几条判断，别机械照搬源仓库：

- **机械拦截优先**：提交信息、README 同步与文件行数都做成脚本 + 钩子，文字约定只解释「为什么」。检查脚本存在但没接钩子 = 约定没生效（audit 的「执行级」专查这个）。
- **Windows 坑用 Node 替 PowerShell**：本 Skill 的行数检查是 `check-long-files.mjs`，不是原仓库的 `.ps1`。理由：不依赖 PS 5.1 的 ANSI 代码页（`.ps1` 无 BOM 会 ParserError）、CI 与非 Windows agent 可跑、计行与行尾风格无关。
- **不生成领域代码**：本 Skill 只造「规范 + 骨架」。渲染引擎、图形元素注册、数据源适配器这类业务实现属于源仓库自身，别往新项目里塞。
- **工具认不出的生态要跳过，不是报缺失**：`audit` 先探测仓库语言再决定哪些检查适用——把「工具不认识这门语言」写成「这个项目缺东西」会让退出码 1 失去意义，也会误导用户去补不存在的问题。行数阈值同理只覆盖 js/ts/vue/css。
- **`〔本机〕` 内容不带入新仓库**：系统代理端口、凭据助手弹窗、TUN 拦 `::1` 等是原机器的事实；新项目里只保留「如何标注与排查这类坑」的方法。
- **占位符不留尾**：生成后 grep 一遍 `{{`，有残留就是模板变量没喂到——比留着强。

## Resources

- [references/conventions-kernel.md](references/conventions-kernel.md)——栈无关约定内核全文（提交/README 同步/版本/CHANGELOG/防重复/拆分/进度清单/验证分级/测试）。
- [references/stack-vue-ts.md](references/stack-vue-ts.md)——Vue3 + TS + Vite + Pinia 落地细节与配置逐项理由。
- [references/pitfalls.md](references/pitfalls.md)——「环境与已知坑」一节的写法规约与通用条目。
- `scripts/scaffold.mjs`——生成骨架，支持 `--stack vue-ts|none`、`--backend`、`--link-hooks`。
- `scripts/audit.mjs`——四组检查的体检清单，退出码反映是否有缺失。
- `scripts/check-long-files.mjs`——跨平台行数阈值检查（被 audit 复用，单一来源）。
- `scripts/commit-msg-check.mjs`——提交信息校验 + 文档同步检查（纯函数 + CLI），前缀白名单、长度与 `DOC_SYNC_PATTERNS` 在文件头常量。
- `assets/`——`AGENTS.md.tpl` 等骨架模板与 `stack-vue-ts/` 配置模板；只在 scaffold 时读取，不必预先加载进上下文。
