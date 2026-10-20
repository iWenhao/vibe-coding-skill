---
name: project-spec
license: MIT
description: 用一套栈无关的工程协作约定，快速新建项目仓库或给已有仓库补齐规范约束。两种模式——scaffold 生成带 AGENTS.md 骨架、提交信息机械拦截钩子、超长文件检查脚本、CHANGELOG 与版本规则、文档地图，以及可选 Vue3+TypeScript+Vite+Pinia+Element Plus 技术栈配置的新仓库；audit 按文件级/执行级/配置级/历史级/代码健康五组体检已有仓库，只补缺项、不覆盖既有约定。当用户说「新建一个项目/仓库」「补一份 AGENTS.md」「约束提交信息、版本号、变更日志」「这个项目规不规矩/该上规范了」「把这套约定搬到别的项目」时使用。
when_to_use: 新项目起步需要工程约定，或已有仓库要补齐 AGENTS.md、提交钩子与收尾检查
argument-hint: <新项目目录> | audit [已有项目目录]
---

# Project Spec

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

**第 1 步——凑齐 4 个输入，缺的一次问完**（不要逐个追问）：项目名（kebab-case）、一句话中文描述、技术栈（`vue-ts` 或 `none`）、有没有本地零依赖后端（决定 `--backend`，**仅 `vue-ts` 可选**——`none` 没有承载它的前端请求层与构建脚本，组合会被脚本拒绝）。

**第 2 步——生成**：

```bash
node <skill-dir>/scripts/scaffold.mjs \
  --target D:/code/my-app --name my-app --desc "内部工单看板" \
  --stack vue-ts --backend
```

可选：`--dev-port 5173` `--api-port 5174` `--force`（目标目录已有同名文件时默认跳过并告警，`--force` 才覆盖）。`--backend` 与 `--stack none` 互斥，脚本会在写入任何文件之前拒绝。

产物：`AGENTS.md` `CHANGELOG.md` `README.md` `docs/{USER_GUIDE,DEPLOY,TESTING,WORKFLOW}.md` `.gitignore`、`scripts/{commit-msg-check.mjs,pre-push-check.mjs,check-long-files.mjs,hooks/{commit-msg,pre-push}}`（钩子文件统一带 0755），`--stack vue-ts` 时再加 `package.json` `tsconfig*.json` `vite.config.ts` `vitest.config.ts` `eslint.config.js` `pnpm-workspace.yaml` `.env.example`、`scripts/{commit-msg-check,pre-push-check}.test.ts` 与 `src/` 最小可跑入口；加 `--backend` 时再加 `server/**`（含 `server/lib/`）与 `src/api/`。`--stack none` 只出规范、钩子与检查脚本，不生成 `package.json`、前端源码、`.env.example` 或跑不了的 `.test.ts`。

**第 3 步——脚本生成不了的两节，必须人工补**，否则 AGENTS.md 只是空壳：

- **「架构与扩展点」**：这个项目最高频的改动是什么？给出「照哪个文件抄格式 + 分几步注册 + 同步哪些文档」的具体路径。新仓库还没有扩展点时，先写成待填清单，别编造。
- **「环境与已知坑」**：先只写**写法规约**（通用坑 vs `〔本机〕` 标注，见 `references/pitfalls.md`），坑要靠实跑积累，不要在第一天硬凑。

**第 4 步——首次安装**（脚本会给提示，按顺序执行）：

```bash
git init
node <skill-dir>/scripts/scaffold.mjs --link-hooks <target>   # 或手工 git config core.hooksPath scripts/hooks
# --stack vue-ts 时继续：
pnpm install
pnpm build && npx vitest run
```

`--stack none` 没有内置技术栈，跳过安装/构建，按生成的 AGENTS.md「常用命令」补齐本栈命令后真跑一次。`core.hooksPath` 是**每个克隆执行一次**的本地配置，不能提交代替；这一点必须在 AGENTS.md 与汇报里都说清。

**第 5 步——验证钩子真的会拦截**（不验证就等于没装）：

写一条注定超长的标题喂给校验脚本，确认它拒绝：

```bash
cd <target> && node -e "require('fs').writeFileSync('../msg-probe.txt','功能: 这条提交信息故意写得很长很长用来验证钩子确实会拒绝这次提交')"
node <target>/scripts/commit-msg-check.mjs ../msg-probe.txt; echo "exit=$?"
```

期望 `exit=1` 并报「标题 33 字符，超出上限 30 字符」（这条是实测过的，正好命中超长分支——顺带写带前缀但不超长的样例只会命中「未知前缀」，测不到长度那道）。验证完删掉 `msg-probe.txt`。绿灯不代表脚本正确，**红灯才代表**。

文档同步拦截同法验证——它是**成对规则**（`DOC_SYNC_RULES`，一组改动文件配一份该同步的文档），每条规则都要见红。直接在生成仓库里改文件再 `git add` 会污染它的暂存区，而且未修改的文档 `git add` 不会进暂存 diff；改用一个临时探针仓库，两条规则一次验完：

```bash
probe=$(mktemp -d) && cd "$probe" && git init -q
git config user.email probe@example.com && git config user.name probe
cp <target>/scripts/commit-msg-check.mjs .
mkdir -p server docs
echo '{}' > package.json; echo '# readme' > README.md
echo '// server' > server/index.mjs; echo '# deploy' > docs/DEPLOY.md
git add . && git commit -qm "构建: 验证用初始提交"
node -e "require('fs').writeFileSync('msg.txt','功能: 验证文档同步\n')"

echo >> package.json; echo >> server/index.mjs
git add package.json server/index.mjs
node commit-msg-check.mjs msg.txt; echo "exit=$?"   # 期望 1：README.md 与 docs/DEPLOY.md 都报未同步

echo >> README.md; echo >> docs/DEPLOY.md
git add README.md docs/DEPLOY.md
node commit-msg-check.mjs msg.txt; echo "exit=$?"   # 期望 0：两条规则都满足

node -e "require('fs').appendFileSync('msg.txt','\n[skip-docs]\n')"
git restore --staged README.md docs/DEPLOY.md
node commit-msg-check.mjs msg.txt; echo "exit=$?"   # 期望 0：豁免放行且提示可见

cd - && rm -rf "$probe"
```

每条规则都红绿分明才算装好——只测 README 那条，接口文档那道坏了也不会被发现。探针仓库用完即删，生成仓库的暂存区与工作树保持原样。

推送前那道全量把关（`scripts/hooks/pre-push`）同样要见红才算装上。**`git push --dry-run` 也会触发钩子**（实测），所以验它不必真的把改动推出去，也不需要本地起服务：

```bash
git init --bare ../probe-remote.git && git remote add origin ../probe-remote.git
git push --dry-run origin <分支>     # 应看到 [pre-push] 全量清单，全绿约十几秒
```

清单随栈变化：`--stack vue-ts` 是 4 步（全量测试 → 构建 → 服务端类型检查 → 行数），`--stack none` 只有 1 步行数检查——别把「只看到行数检查」当成钩子没接上。

想验「真能中止」：vue-ts 项目临时加一个带类型错误的 `.ts` 文件，none 项目临时加一个超过 400 行的 `.mjs`/`.js` 文件，提交一次再跑上面的 dry-run——期望前者在「构建（含 vue-tsc 类型检查）」、后者在「行数检查」连续两次失败后打印 `[pre-push] ❌ 推送中止` 并以非 0 退出（其余步骤照常通过，说明清单逐步在跑）。验完删探针文件与其提交、`rm -rf ../probe-remote.git`、`git remote remove origin`。**钩子的可执行位在这台 Windows 机器上验不出来**：git for Windows 不看 x 位，`statSync` 的 mode 又一律报 `0666`，所以 scaffold 里那句 chmod 只能靠代码路径保证、`audit` 在非 win32 平台才检查它——别因为在 Windows 上「推得动」就断定 Linux/CI 上也推得动。项目若已按 [references/verification-ci.md](references/verification-ci.md) 把全量移到 CI，这里的预期步骤按那份文档改——pre-push 只跑轻量集，别拿全量清单去验。

## 模式二：给已有项目上规范

**第 1 步——体检**：

```bash
node <skill-dir>/scripts/audit.mjs [目标目录，默认当前]
```

输出按「文件级 / 执行级 / 配置级 / 历史级 / 代码健康」五组分组，✅ 已具备、⬜ 缺失、⚠️ 存在但不合规、· 说明（代码健康组含超长文件清单与测试文件检查，历史级含历史提交不合规抽样）。退出码 1 表示有缺失项。

**第 2 步——只补缺，不覆盖**。已有项目往往有自己的约定变体（前缀不同、版本号规则不同）：

- 先读现有 `AGENTS.md`/`package.json`/`.gitignore`，**与待补文件 diff**；
- 语义冲突（如前缀白名单、分支模型）以项目现有约定为准，改 asset 里的常量而不是改项目历史；
- 纯缺失（压根没有钩子/检查脚本）才直接拷贝；
- 不重构与规范无关的代码，不为了让检查变绿而拆分与本次无关的历史超长文件（既有欠账只如实列出）。

**第 3 步——回填项目特有内容**：同模式一第 3 步。

**第 4 步——复跑 audit 并把两份输出都贴给用户**（补之前 / 补之后），让他看见差值。用户可见清单用 `✅ 已完成 / 🔄 进行中 / ⬜ 未开始`。

## 约定内核

写进新仓库 AGENTS.md 时不可缺的九节（与 `audit.mjs` 的 `REQUIRED_AGENT_SECTIONS` 对齐；细则见 [references/conventions-kernel.md](references/conventions-kernel.md)）：

1. **项目概述**——一句话描述 + 技术栈 + 页面/模块结构与数据来源；脚手架只能给【待填】占位，必须人工补。
2. **常用命令**——只列命令，门槛指向「验证节奏」，两处不重复。
3. **环境与已知坑**——仓库属性 vs `〔本机〕` 分开标注，换机器不照搬。
4. **任务清单与进度可见性**——多步任务必须有对用户可见的清单，开工与收尾各附一份。
5. **工作流约定**——分支模型、一个功能一个提交、并行改动按「原生工作树隔离 → 手工 worktree → 同工作树三条硬规矩」分层、提交信息前缀白名单 + 标题 ≤30 **字符**（汉字算 1）、细节写 CHANGELOG、重要文件改动同轮同步对应文档（README / 接口码表，钩子按成对规则拦截）、版本号只在明确发版时动。其中「怎么开工作树、版本号怎么进位」这类**只在某一轮用得上**的细则外置到 `docs/WORKFLOW.md`，主文件留硬规矩加触发条件——每轮都要守的那半句（绝不 `git add -A`、平时不动版本号）**不能挪**。
6. **架构与扩展点**——AGENTS.md 里唯一不能靠模板生成、价值最高的一节，给高频改动「照哪个文件抄格式 + 分几步注册 + 同步哪些文档」的具体路径；必须人工填，缺这节 `audit` 会报 ⬜。
7. **代码风格**——注释中文且只说「为什么」；先找现成的、**三次必收敛**；超阈值必拆。对外暴露端点时再加一条**接口响应约定**：主文件只留硬规矩（形状只有两种：成功=数据+可选元信息 / 失败=错误码+人读文案；判据只有状态码；服务端出口与前端入口各唯一；**调用方只比错误码不比文案**）与「新增端点先读 DEPLOY」的触发条件，全文细则与逐端点码表外置到 `docs/DEPLOY.md`——这条外置由 `DOC_SYNC_RULES` 的成对规则兜住（改 `server/**`、`src/api/**` 不同步码表就拒绝提交）。
8. **验证节奏**——默认动作是「跑受影响的测试」而不是全量（受限环境里全量的绿灯本身可能不可信），按改动范围分级的表格，含「用户可见输出必须真跑一次」这条优先级最高的例外。
9. **测试**——单测放被测文件同目录；核心逻辑补测，UI 不强求但改 UI 要浏览器实测；纯逻辑用例自己声明轻量环境，别一律吃浏览器模拟环境。

默认档的权威时机是 pre-push 全量；只有 CI 能机器强制时才把全量上移。这个可选档的切换方案与前置条件见 [references/verification-ci.md](references/verification-ci.md)，默认不启用——别把这段当九节清单的一部分写进项目。

技术栈相关细节（strict 四件套、ESLint flat 双块、vitest include、按范围挑着跑的三条命令与纯逻辑用例的环境头、unplugin dts、服务端 tsconfig、前端可选后端与回落存储）见 [references/stack-vue-ts.md](references/stack-vue-ts.md)。

## 关键取舍

生成或补齐前先照这几条判断，别机械照搬源仓库：

- **机械拦截优先**：提交信息、文档同步与文件行数都做成脚本 + 钩子，文字约定只解释「为什么」。检查脚本存在但没接钩子 = 约定没生效（audit 的「执行级」专查这个）。
- **Windows 坑用 Node 替 PowerShell**：本 Skill 的行数检查是 `check-long-files.mjs`，不是原仓库的 `.ps1`。理由：不依赖 PS 5.1 的 ANSI 代码页（`.ps1` 无 BOM 会 ParserError）、CI 与非 Windows agent 可跑、计行与行尾风格无关。
- **`AGENTS.md` 只装「每轮都要用」的规则，并按字节算预算**：Codex 的 `project_doc_max_bytes` 默认把「项目根 → 工作目录」这条链上所有 AGENTS.md **合并**算 32 KiB，拼满就不再加载更靠近工作目录的那份（是整份进不来，不是尾部截断）。细则只能挪进同仓库 `docs/` 并写明何时必读，**不能挪进本 Skill 的 `references/`**——references 不随生成的仓库走，挪过去等于内容消失。`audit` 按这份预算报字节与占比，体积因此是看得见的数字。
- **不生成领域代码**：本 Skill 只造「规范 + 骨架」。渲染引擎、图形元素注册、数据源适配器这类业务实现属于源仓库自身，别往新项目里塞。
- **具体名字只能出现在本身就具体的层**：判据是一句话——**这个名字对拿到生成的新仓库来说，是不是它自己的事实？**是，就留在会渲染给它的那一层；不是（那是源仓库或某个可选实现的事实），写进通用层就是把别人的路径当真理，换个项目即失效，还会让人照着去补一个不存在的端点。允许实名的三类：`{{#BACKEND}}` / `{{^BACKEND}}` 这类**条件块**（只在真有那段代码时才落到文件里）、`assets/stack-vue-ts/**`（生成的就是真配置）、`references/stack-vue-ts.md`（按栈写的落地细节）。栈无关的四处——`AGENTS.md.tpl` 非条件部分、`references/conventions-kernel.md`、本文件、`references/pitfalls.md` 的通用坑——只写**角色**（「服务端统一出口」「前端请求入口」「探测路由」），并在同一条里留指针指向实名那份。源仓库的业务领域名（产品线、图元、第三方服务）任何层都不许出现。
- **工具认不出的生态要跳过，不是报缺失**：`audit` 先探测仓库语言再决定哪些检查适用——把「工具不认识这门语言」写成「这个项目缺东西」会让退出码 1 失去意义，也会误导用户去补不存在的问题。行数阈值同理只覆盖 js/ts/vue/css。
- **`〔本机〕` 内容不带入新仓库**：系统代理端口、凭据助手弹窗、TUN 拦 `::1` 等是原机器的事实；新项目里只保留「如何标注与排查这类坑」的方法。
- **占位符不留尾**：生成后 grep 一遍 `{{`，有残留就是模板变量没喂到——比留着强。

## Resources

- [references/conventions-kernel.md](references/conventions-kernel.md)——栈无关约定内核全文（提交/文档同步/版本/CHANGELOG/并行改动隔离/接口响应信封/防重复/拆分/进度清单/验证分级/测试）。
- [references/stack-vue-ts.md](references/stack-vue-ts.md)——Vue3 + TS + Vite + Pinia 落地细节与配置逐项理由。
- [references/pitfalls.md](references/pitfalls.md)——「环境与已知坑」一节的写法规约与通用条目。
- [references/verification-ci.md](references/verification-ci.md)——可选档：把全量从 pre-push 移到强制 CI 的前置条件、实现要点、落地顺序与本仓库改动点（默认不启用）。
- `scripts/scaffold.mjs`——生成骨架，支持 `--stack vue-ts|none`、`--backend`、`--link-hooks`。
- `scripts/audit.mjs`——五组检查的体检清单，退出码反映是否有缺失。
- `scripts/repo-facts.mjs`——audit 的事实探测层（读文件、走目录、判语言、跑 git、加载目标仓库自己的校验器）；**只探不判**，所有 ⬜/⚠️ 判定留在 audit.mjs。
- `scripts/hook-gates.test.mjs`——本仓库对自己两道闸门（提交信息 + 推送前把关）做的自测（`node --test "skills/project-spec/scripts/*.test.mjs"`），零第三方依赖。
- `assets/scripts/check-long-files.mjs`——跨平台行数阈值检查（拷进生成的仓库，audit 从目标仓库加载它复用同一套阈值逻辑）。
- `assets/scripts/commit-msg-check.mjs`——提交信息校验 + 文档同步检查（纯函数 + CLI），前缀白名单、长度与 `DOC_SYNC_RULES` 在文件头常量；`DOC_SYNC_RULES` 是**成对规则**（一组改动文件 → 该同步的那份文档），新增一类「改了代码必须同步文档」的约定时往里加一条，不要另写一个检查器。
- `assets/scripts/pre-push-check.mjs`——推送前全量把关（测试/构建/服务端类型/行数四步，失败自动重试一次），由 `assets/scripts/hooks/pre-push` 调用；**步骤清单以它为准**，AGENTS.md 与内核的验证节奏表只是它的镜像。仓库根按 `git rev-parse --show-toplevel` 定位（与 git 执行钩子的目录一致），纯函数由同目录的 `pre-push-check.test.ts` 覆盖。
- `assets/`——`AGENTS.md.tpl` 等骨架模板与 `stack-vue-ts/` 配置模板；只在 scaffold 时读取，不必预先加载进上下文。
