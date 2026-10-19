/**
 * 推送前全量把关（纯函数 + CLI），由 scripts/hooks/pre-push 调用。
 *
 * 两级把关的分工（AGENTS.md「验证节奏」）：
 *   - **提交前**跑轻量集——受影响的测试 + 类型检查 + 行数检查，秒级，靠约定与 agent 自觉；
 *   - **推送前**跑全量四件套——就是本文件，机械强制，任一步失败即中止推送。
 *
 * 为什么全量放在 push 而不是每次提交：一次全量的固定开销（约 3~4 分钟）抵得上好几轮小改动，
 * 挂在提交上会把人训练成 `--no-verify`；而推送是「改动离开本机」前的最后一道，
 * 慢一点换来「推出去的每个提交都过过全量」，这笔账是划算的。
 *
 * 为什么每步失败自动重试一次：agent 沙箱与本机的临时目录权限会间歇性打断测试运行器
 * （vitest 的 SSR 缓存首当其冲）。症状是**用例全过、但汇总行带 `Errors`、退出码非 0**——与代码无关。
 * 不重试的话，这道钩子就会被偶发红灯磨成习惯性 `--no-verify`，那它等于没装。
 * 只重试一次：第二次仍失败就按真失败处理，不把真 bug 洗成绿灯。
 *
 * 为什么 lint 不在这份清单里：全量 lint 会被仓库既有报警淹没，信号被稀释——
 * 它留在「只跑改动文件」那一档（见 AGENTS.md「验证节奏」）。
 *
 * 退出码：0 = 放行（含「本次没有需要把关的引用」）；1 = 任一步重试后仍失败，钩子据此中止推送。
 * 改下面的步骤清单时，必须同步改 AGENTS.md「验证节奏」的推送级——两处不一致时以本文件为准，
 * 因为它才是真正拦住推送的那一道。
 */
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { spawnSync } from 'node:child_process'

/** 全 0 的 oid = git 用它表示「删除该远端引用」，不引入任何新代码 */
export const ZERO_OID = '0'.repeat(40)

/** 首次失败后额外重试的次数。只给 1：再多就是在掩盖真失败 */
export const RETRY_TIMES = 1

/** 行数检查兜底命令（项目没有 check:lines 脚本时用它，roots 与豁免得自己在参数里给） */
export const LINE_CHECK_FALLBACK = ['node', 'scripts/check-long-files.mjs']

/**
 * 解析 git 交给 pre-push 的清单：每行 `<本地 ref> <本地 oid> <远端 ref> <远端 oid>`。
 * @param {string} text stdin 全文
 * @returns {Array<{localRef: string, localOid: string, remoteRef: string, remoteOid: string}>|null}
 *   字段不齐（输入被截断、格式不是 git 那套）返回 null，由 decidePush 走最严路径
 */
export function parseRefLines(text) {
  const lines = String(text ?? '')
    .split(/\r?\n/)
    .filter((line) => line.trim() !== '')
  const refs = []
  for (const line of lines) {
    const [localRef, localOid, remoteRef, remoteOid] = line.trim().split(/\s+/)
    if (!localRef || !localOid || !remoteRef || !remoteOid) return null
    refs.push({ localRef, localOid, remoteRef, remoteOid })
  }
  return refs
}

/**
 * 这次推送要不要跑全量把关。**判据是「有没有新代码离开本机」**。
 * @param {ReturnType<typeof parseRefLines>} refs null = 清单不可得（手工运行、输入异常）
 * @returns {{skip: boolean, reason: string, checked: string[]}}
 */
export function decidePush(refs) {
  // 拿不到清单时按最严的路径处理：宁可多跑一次全量，也不能让「解析失败」变成静默放行
  if (refs === null) {
    return { skip: false, reason: '未取得待推送清单（手工运行或输入格式异常），按全量把关处理', checked: ['—'] }
  }
  if (refs.length === 0) {
    return { skip: true, reason: '本次推送没有携带任何引用', checked: [] }
  }
  const live = refs.filter((ref) => ref.localOid !== ZERO_OID)
  if (live.length === 0) {
    return { skip: true, reason: '本次只删除远端引用，不引入新代码', checked: [] }
  }
  const branches = live.filter((ref) => !ref.localRef.startsWith('refs/tags/'))
  if (branches.length === 0) {
    const tags = live.map((ref) => ref.localRef.replace('refs/tags/', ''))
    return {
      skip: true,
      reason: `只推送 tag（${tags.join('、')}）——它指向的提交已经随分支推送过全量，再等几分钟没有新信息`,
      checked: [],
    }
  }
  return {
    skip: false,
    reason: '',
    checked: branches.map((ref) => `${ref.localRef} → ${ref.remoteRef}`),
  }
}

/** lockfile 名 -> 包管理器命令；顺序即优先级 */
const LOCKFILES = [
  ['pnpm-lock.yaml', 'pnpm'],
  ['yarn.lock', 'yarn'],
  ['bun.lockb', 'bun'],
  ['package-lock.json', 'npm'],
]

/**
 * 挑包管理器命令。`packageManager` 字段优先（corepack 的显式声明），其次按 lockfile，兜底 npm。
 * @param {{packageManager?: string, files: string[]}} ctx files = 仓库根实际存在的文件名
 */
export function pickPackageManager(ctx) {
  const declared = String(ctx.packageManager ?? '').split('@')[0].trim()
  if (['pnpm', 'yarn', 'bun', 'npm'].includes(declared)) return declared
  for (const [file, pm] of LOCKFILES) {
    if (ctx.files.includes(file)) return pm
  }
  return 'npm'
}

/**
 * 决定本次要跑哪些步骤（纯函数，便于单测）。**清单里没有的步骤不会假装跑过**。
 * @param {{pm: string, hasVitest: boolean, packageScripts: Record<string, string>, hasLineChecker: boolean}} ctx
 * @returns {Array<{name: string, cmd: string, args: string[]}>}
 */
export function planSteps(ctx) {
  const steps = []
  // 全量测试用 npx 而不是 pnpm test：后者是 watch 模式，会把钩子挂住
  if (ctx.hasVitest) steps.push({ name: '全量测试', cmd: 'npx', args: ['vitest', 'run'] })
  // 前端类型检查不单独列一步：这套栈的 build 第一步就是 vue-tsc --noEmit，跑两遍是白付时间
  if (ctx.packageScripts.build !== undefined) {
    steps.push({ name: '构建（含 vue-tsc 类型检查）', cmd: ctx.pm, args: ['run', 'build'] })
  }
  // vue-tsc 的 include 不覆盖 server/**，这条是服务端唯一的类型把关入口
  if (ctx.packageScripts['typecheck:server'] !== undefined) {
    steps.push({ name: '服务端类型检查', cmd: ctx.pm, args: ['run', 'typecheck:server'] })
  }
  if (ctx.hasLineChecker) {
    steps.push(
      ctx.packageScripts['check:lines'] !== undefined
        ? { name: '行数检查', cmd: ctx.pm, args: ['run', 'check:lines'] }
        : { name: '行数检查', cmd: LINE_CHECK_FALLBACK[0], args: LINE_CHECK_FALLBACK.slice(1) },
    )
  }
  return steps
}

/** 读仓库根的 package.json；读不到或坏了返回 null（非 Node 仓库、monorepo 子目录等） */
function readPackage(root) {
  try {
    return JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'))
  } catch {
    return null
  }
}

/** Windows 上 pnpm/npx 都是 .cmd，Node ≥18 的安全策略要求经 shell 启动 */
const USE_SHELL = process.platform === 'win32'

/** 跑一步：失败自动重试，返回 {ok, attempts, seconds} */
function runStep(step, cwd) {
  let attempts = 0
  let code = null
  const started = Date.now()
  while (attempts <= RETRY_TIMES) {
    const result = spawnSync(step.cmd, step.args, { cwd, stdio: 'inherit', shell: USE_SHELL })
    if (result.error) {
      console.error(`\n[pre-push] 无法启动「${step.cmd} ${step.args.join(' ')}」：${result.error.message}`)
      code = -1
      break
    }
    attempts++
    code = result.status
    if (code === 0) break
    if (attempts <= RETRY_TIMES) {
      console.error(
        `\n[pre-push] ⚠️ ${step.name} 失败（退出码 ${code}）——自动重试第 ${attempts} 次。` +
          '运行环境被临时目录权限打断时会出这种「用例全过但退出码非 0」的假红灯。',
      )
    }
  }
  return { ok: code === 0, attempts, seconds: Math.round((Date.now() - started) / 1000) }
}

function secondsText(seconds) {
  return seconds >= 60 ? `${Math.floor(seconds / 60)} 分 ${seconds % 60} 秒` : `${seconds} 秒`
}

/**
 * 钩子环境下的仓库根：本文件在 `<root>/scripts/`，git 的 cwd 未必是仓库根，故按自身路径定位。
 */
function repoRoot() {
  return dirname(dirname(fileURLToPath(import.meta.url)))
}

/** 读 git 交给钩子的 stdin；手工在终端跑时 stdin 是 TTY，读不到清单 = 走最严路径 */
function readStdin() {
  if (process.stdin.isTTY === true) return null
  try {
    return parseRefLines(readFileSync(0, 'utf8'))
  } catch {
    return null
  }
}

// CLI 入口：node scripts/pre-push-check.mjs [远程名] [远程 URL] [--dry-run]
const invokedDirectly =
  process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href

if (invokedDirectly) {
  const root = repoRoot()
  const dryRun = process.argv.includes('--dry-run')
  const pkg = readPackage(root)
  const ctx = {
    pm: pickPackageManager({
      packageManager: pkg?.packageManager,
      files: ['pnpm-lock.yaml', 'yarn.lock', 'bun.lockb', 'package-lock.json'].filter((file) =>
        existsSync(join(root, file)),
      ),
    }),
    hasVitest:
      pkg?.devDependencies?.vitest !== undefined || pkg?.dependencies?.vitest !== undefined,
    packageScripts: pkg?.scripts ?? {},
    hasLineChecker: existsSync(join(root, 'scripts/check-long-files.mjs')),
  }

  const decision = decidePush(readStdin())
  if (decision.skip) {
    console.log(`[pre-push] 跳过全量把关：${decision.reason}`)
    process.exit(0)
  }

  const steps = planSteps(ctx)
  console.log(`[pre-push] 待推送：${decision.checked.join('，')}`)
  if (steps.length === 0) {
    console.log('[pre-push] 本仓库没有可执行的把关步骤（无 package.json 脚本、无行数检查脚本）——放行，但这次推送等于没把关')
    process.exit(0)
  }
  console.log(`[pre-push] 全量清单（${steps.length} 步，包管理器 ${ctx.pm}）：${steps.map((s) => s.name).join(' → ')}`)

  if (dryRun) {
    for (const step of steps) console.log(`  · ${step.name}：${step.cmd} ${step.args.join(' ')}`)
    console.log('[pre-push] --dry-run 只打印清单，不执行')
    process.exit(0)
  }

  // 全量跑的是工作树，不是待推送的那几个提交——工作区脏的时候这个结论有偏差，如实说出来
  const dirty = spawnSync('git', ['status', '--porcelain'], { cwd: root, encoding: 'utf8' })
  if (!dirty.error && dirty.status === 0 && dirty.stdout.trim() !== '') {
    console.log('[pre-push] · 提示：工作区有未提交改动，本次把关跑的是当前工作树，与待推送提交不完全等价')
  }

  // 依赖没装的话 npx 会去网上现拉一份，跑出来的结果与被钩子拦住的真实环境不是一回事
  if (pkg !== null && !existsSync(join(root, 'node_modules'))) {
    console.error('[pre-push] ❌ 推送中止：依赖未安装（没有 node_modules），全量检查无法执行。先跑 `pnpm install`')
    process.exit(1)
  }

  const started = Date.now()
  const results = []
  for (const [index, step] of steps.entries()) {
    console.log(`\n[pre-push] ${index + 1}/${steps.length} ${step.name}：${step.cmd} ${step.args.join(' ')}`)
    const result = runStep(step, root)
    results.push({ name: step.name, ...result })
    if (!result.ok) {
      console.error(`\n[pre-push] ❌ 推送中止：${step.name} 连续 ${result.attempts} 次失败（退出码见上方输出）。`)
      console.error('  · 若失败里有 EPERM 或汇总行带 `Errors`，那是运行环境被打断，不是代码坏了：' + '把 TEMP/TMP 指到可写目录重跑，或改用文件串行（vitest 是 `--no-file-parallelism`）。')
      console.error('  · 已过：' + (results.length > 1 ? results.slice(0, -1).map((item) => `${item.name}（${secondsText(item.seconds)}）`).join('、') : '无'))
      console.error('  · 约定见 AGENTS.md「验证节奏」；确需绕过用 `git push --no-verify`（兜底，不是日常）')
      process.exit(1)
    }
    console.log(`[pre-push] ✅ ${step.name} 通过（${secondsText(result.seconds)}）`)
  }

  console.log(
    `\n[pre-push] ✅ 全量把关通过：${steps.map((step) => step.name).join('、')}，共 ${secondsText(Math.round((Date.now() - started) / 1000))}`,
  )
  process.exit(0)
}
