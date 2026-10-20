# 可选档：本地轻量 + CI 全量

> **默认档没有变**：scaffold 生成的项目仍是「pre-push 全量四件套」。本文是项目具备**强制 CI** 后的升级方案，不是现成行为；切换要按「本仓库落点」逐项改，只改文档等于没改。

默认档的权威时机是 pre-push（[conventions-kernel.md](conventions-kernel.md) 第 8 节，脚本以 `assets/scripts/pre-push-check.mjs` 为准）。本档把权威时机上移到 CI，本地只保留分钟级快速失败。两档的硬规矩相同：**全量只认一个权威时机**——不能一边说「推送前全量」，一边说「CI 全量」，否则两处绿灯都只是半句话。

命令以本 Skill 的 `vue-ts` 栈为例；`none` 栈把测试、构建、类型检查换成该项目自己的命令。

## 前置条件（缺一不可）

1. **CI 跑得稳**：全量在 CI 上不会静默少跑文件；汇总行没有 `Errors` 才算数（判据见项目里的 `docs/TESTING.md`）。
2. **CI 拦得住**：目标分支开分支保护，并把 CI 的 gates job 设为 required check，CI 绿才能合并；`--no-verify` 绕得过本地钩子，绕不过 CI。
3. **有默认分支与 PR 流程**：日常推送只发生在 feature 分支。

缺任何一条，切过去就是「本地轻量 + 无人兜底」，门槛实际消失。单人单机、没有 CI 时保持默认档。

## 三级分工

| 时机 | 内容 | 定位 |
| --- | --- | --- |
| 提交 | 改动相关测试 + 前端类型检查 + 行数检查 | 人或代理执行，分钟级 |
| 推送（pre-push） | 本次推送 diff 映射出的同目录同名测试 + 前端类型检查 + 行数检查（建议再加服务端类型检查） | 机器强制，分钟级；可被 `--no-verify` 绕过 |
| 推送后（CI） | 全量测试 + 前端类型检查 + 服务端类型检查 + 生产构建 + 行数检查 | 机器强制、不可绕过；唯一权威 |

单人单机且钩子可靠时，可以只用默认档的 pre-push 全量；一旦出现第二个开发环境、协作者，或需要 Linux/macOS 兼容性验证，就按本档把全量移到 CI，本地降为轻量。

## 与默认档的差异

- **构建只在 CI 跑**。本地不再把 `pnpm build` 当类型检查——pre-push 单独跑 `vue-tsc --noEmit`。现有 `package.json` 只有 `build`（`vue-tsc --noEmit && vite build`），切换时补一条 `"typecheck": "vue-tsc --noEmit"`，否则每次类型检查都白付一次打包。
- **测试只跑 diff 映射到的同名测试**，跨目录覆盖交给 CI。这是有意的取舍：换来分钟级推送。
- **服务端类型检查建议留在 pre-push**。它只要 2~3 秒，却是 `vue-tsc` 的盲区；早失败比等 CI 便宜。即使移到 CI，也必须单列一步。
- **权威从钩子变成 CI**。钩子还能被 `--no-verify` 绕过，所以分支保护不是可选项。

## 实现要点

### 1. pre-push 的 diff 映射

从钩子 stdin 拿到 `<本地 oid> <远端 oid>`，按推送的提交范围取改动文件，不要按工作树：

```bash
# 已有远端引用
git diff --name-status "$remoteOid" "$localOid"
# 新分支（远端 oid 全 0）：与默认分支的远端跟踪引用比 merge-base
base=$(git merge-base "$localOid" origin/master) || base=
if [ -n "$base" ]; then
  git diff --name-status "$base" "$localOid"
else
  echo "取不到 merge-base，回退全量"   # 走全量清单
fi
```

映射规则：

- `src/foo.ts` / `src/foo.vue` → 同目录 `src/foo.test.ts`；改的就是测试文件 → 它自己；
- 删除/改名取**旧路径**的同名测试，再并上新路径；
- 多引用推送取并集；
- **共享层与工具链改动一律跑全量测试**：`shared/**`、`src/utils/**`、`*.d.ts`、`package.json`、lockfile、`tsconfig*`、`vitest.config.*`、`vite.config.*`。同名映射看不见跨目录消费者，这类改动靠 CI 兜太晚；
- 一个测试都没映射到 → **打印可见的跳过原因**（「0 个同名测试，跨目录覆盖交给 CI」），不许静默跳过；
- 解析失败、拿不到 merge-base、diff 命令出错 → **回退全量**，与现有 `decidePush` 的 fail-safe 一致。

不要用 `vitest related` 偷懒：它要转换整个模块图，慢，而且可能被沙箱信号杀掉；同名映射只挑文件，便宜得多。

工作区有未提交改动时要提示：映射按提交算，测试跑的是工作树，两者不严格等价（现有脚本已有这句提示，保留）。

### 2. 并行跑、按轮重试

- 独立检查并发跑：墙钟等于最慢一项，而不是各项之和；测试保留实时输出，其余步骤先缓冲、失败时统一回显。
- 失败按轮重试：首轮全部跑完后只重跑失败项，最多再跑两轮；既吸收沙箱 EPERM / 资源抖动，又不重复消耗已通过项。
- 重试用于吸收抖动，不是修 bug：两轮仍红就按真失败处理；能识别出 EPERM / 汇总行 `Errors` 的，优先归为环境类。
- 现有 `runStep` 是串行 + 每步失败重试一次；切本档要把它换成调度器，**规划仍是纯函数**（便于 `pre-push-check.test.ts` 覆盖）。

### 3. 增量缓存

- 每个 tsconfig 各自设 `incremental` + `tsBuildInfoFile`，缓存放 `node_modules/.cache/`（天然不入库）：

  ```jsonc
  {
    "compilerOptions": {
      "incremental": true,
      "tsBuildInfoFile": "node_modules/.cache/tsconfig.server.tsbuildinfo"
    }
  }
  ```

- CI 缓存 `node_modules/.cache`，key 里带 lockfile 与 tsconfig 的哈希。
- **必须用「临时写一个类型错误」验证缓存仍能报错**：连跑两次，第二次仍须失败；吞错的缓存等于没有类型检查。
- `vue-tsc --noEmit` 的增量行为随版本变，先在钉住的版本上实测；不支持就退回非增量，别写一条没验过的配置。

### 4. 服务端类型检查必须单列

前端 `vue-tsc` 的 include 只覆盖 `src/`，服务端 `.mjs` 会漏检。CI 里 `pnpm typecheck:server`（`tsc -p tsconfig.server.json`）单独一步，不跑等于服务端改动零类型把关。

### 5. 行数检查放两处（pre-push 顺手带上）

提交时避免超长文件进入历史，CI 做兜底；耗时 <0.5s，pre-push 顺手带上也不构成负担。

### 6. 时序测试不要固定 sleep

并发门槛下定时器回调会被推迟出窗口。改为轮询到条件满足并设上限，不要用整体重试掩盖。

### 7. CI 配置（以 GitHub Actions 为例）

```yaml
name: ci
on:
  push:
    branches: [master, dev]
  pull_request:
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
jobs:
  gates:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4        # 版本与 packageManager 字段一致
      - uses: actions/setup-node@v4
        with: { node-version: 22, cache: pnpm }
      - run: pnpm install --frozen-lockfile
      - run: npx vitest run                # 不用 pnpm test：它是 watch
      - run: pnpm build                    # 已含 vue-tsc，别再单跑一遍
      - run: pnpm typecheck:server         # 有后端时
      - run: pnpm check:lines              # none 栈用 node scripts/check-long-files.mjs
```

- 固定 Node / pnpm 版本、`--frozen-lockfile`；`concurrency` + `cancel-in-progress` 取消旧 run。
- 默认分支开分支保护，CI 绿才能合并。
- 步骤串行还是一步一个 job：分 job 并行墙钟短，但每个 job 都要重新安装；按项目实测选，别默认拆。
- 换 GitLab CI / Gitea Actions 同理，命令不变。

## 反例（都实际发生过）

- 把构建写成「提交前必跑」，与「全量留到推送」自相矛盾。
- 只跑前端类型检查，服务端类型错误一路推到远端。
- 固定等 150ms 的心跳用例在五路并发下偶发失败，靠重试才过；修法是轮询，不是加重试次数。
- 凭感觉把 jsdom 测试切到 node：10 个疑似纯逻辑用例里 7 个直接失败，必须逐个真跑验证。

## 实测数据（单机参考，不构成承诺）

来自一个真实 Vue + TS 项目的单机数据，换项目先自己量：

- 四项串行约 89s → 并发 47s；构建是长板（单独 25s，并发下 47s）。
- `vue-tsc` 增量热跑 7~9s，非增量 11~13s；服务端 `tsc` 冷 3s / 热 2s。
- 全量测试 74 文件 / 740 用例；五项并发门槛整体 47s。

## 落地顺序（别一步到位）

1. **先加 CI 全量**，本地 pre-push 仍全量，双跑几天，确认 CI 稳定、分支保护真的拦得住。
2. **再降 pre-push**：改 `planSteps` / `decidePush`，加 diff 映射与全量回退；补 `typecheck` 脚本。
3. **同步文案**（表与脚本不一致时以脚本为准，这条不变）：
   - `assets/AGENTS.md.tpl`「验证节奏」的「准备提交或交付」「推送」两行；
   - `references/conventions-kernel.md` 第 8 节同两行；
   - `assets/docs/TESTING.md.tpl`「这次全量算不算数」——把 CI 写成权威时机；
   - `SKILL.md` 模式一第 5 步的推送验证预期、`README.md` 的功能特性。
4. **自测与探针**：
   - `pre-push-check.test.ts` 覆盖新分支 / 删除 / 改名 / 共享层 / 0 个同名测试 / 解析失败回退全量；
   - `hook-gates.test.mjs` 跑 dry-run；
   - 用临时探针确认 CI 红灯能阻止合并（分支保护），别只看 CI 页面变红。
5. 跑一周再回看：CI 红灯是否有人及时处理；没有的话回退默认档。

**回退**：恢复 `planSteps` 的全量清单即可，CI 留着不冲突。分支保护被关、或 CI 长期红而无人处理时，立即回退。

## 本仓库落点（切换时逐项改）

路径相对 `skills/project-spec/`；`README.md` 指仓库根那份。

| 文件 | 改什么 |
| --- | --- |
| `assets/scripts/pre-push-check.mjs` | `planSteps` 接收 diff 文件列表；测试步骤改为映射集合；加 `typecheck` 步骤；失败调度 |
| `assets/scripts/pre-push-check.test.ts.tpl` | 补 diff 映射边界用例 |
| `scripts/hook-gates.test.mjs` | 同步自测预期 |
| `assets/stack-vue-ts/package.json.tpl` | 加 `typecheck: vue-tsc --noEmit` |
| `assets/stack-vue-ts/tsconfig*.json.tpl` | `incremental` + `tsBuildInfoFile` |
| `assets/AGENTS.md.tpl` | 「验证节奏」两行 + 触发条件 |
| `references/conventions-kernel.md` | 第 8 节两行 |
| `assets/docs/TESTING.md.tpl` | 全量权威时机的判据 |
| `SKILL.md` / `README.md` | 模式一验证步骤、功能特性与本文链接 |
| CI 模板（新） | `assets/` 下新增 workflow 模板并在 `scripts/scaffold.mjs` 挂载；不挂载则只在采用的项目里手写 |

> scaffold **默认不生成 CI**，也不自动进入本档；上面的模板与脚本改动只在目标项目明确采用时做。
