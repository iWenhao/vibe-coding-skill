#!/usr/bin/env node
/**
 * 体检：检查一个仓库有没有把约定落成可执行的约束，输出 ✅/⬜/⚠️ 清单。
 *
 * 用法：node scripts/audit.mjs [目标目录，默认当前目录]
 * 退出码：0 = 无缺失项（可能仍有 ⚠️）；1 = 有 ⬜ 缺失项；2 = 用法/目录错误
 *
 * 关键设计：**校验规则一律从目标仓库自己的脚本里 import**，Skill 的 asset 副本只作兜底。
 * 理由是每个项目的前缀白名单与阈值可以不同，用错来源会得到一份「按别的项目体检」的报告。
 *
 * 第二条设计：**生态探测只决定「这项检查适不适用」**。非 Node 仓库会跳过 node_modules/dist、
 * package.json 脚本等条目并说明原因，而不是报成缺失——假缺失会污染退出码 1 的信号。
 */
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { execFileSync } from 'node:child_process'

const SKILL_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const REQUIRED_AGENT_SECTIONS = [
  '项目概述',
  '常用命令',
  '环境与已知坑',
  '任务清单',
  '工作流约定',
  '架构与扩展点',
  '代码风格',
  '验证节奏',
  '测试',
]

/**
 * AGENTS.md 的体积预算，单位**字节**：Codex 的 `project_doc_max_bytes` 默认 32 * 1024，
 * 算的是「项目根 → 当前工作目录」这条链上所有 AGENTS.md **合并后的总量**，
 * 一旦拼到上限就停止继续加载更靠近工作目录的那份——不是把尾部字节裁掉。
 *
 * 为什么按字节而不是行数：中文在 UTF-8 里一个字占 3 字节，同样 200 行，
 * 中文仓库的真实体积是英文仓库的近三倍。按行数出的结论会系统性偏松。
 * （用户级 `~/.codex/AGENTS.md` 与这份预算共享，但它在仓库外，本脚本看不到，
 * 所以这里只报「仓库内可见的量」，不据此判缺失——假缺失会污染退出码 1。）
 */
const AGENT_DOC_BUDGET_BYTES = 32 * 1024

/** status: ok=✅ missing=⬜ warn=⚠️ info=· */
function makeReporter() {
  const rows = []
  const report = (group, status, text) => rows.push({ group, status, text })
  return {
    report,
    print() {
      const symbol = { ok: '✅', missing: '⬜', warn: '⚠️', info: '·' }
      let group = ''
      let missing = 0
      let warnings = 0
      for (const row of rows) {
        if (row.group !== group) {
          group = row.group
          console.log(`\n## ${group}`)
        }
        console.log(`  ${symbol[row.status]} ${row.text}`)
        if (row.status === 'missing') missing++
        if (row.status === 'warn') warnings++
      }
      console.log(`\n合计：${missing} 项缺失、${warnings} 项待注意`)
      return missing
    },
  }
}

function readIf(path) {
  try {
    return existsSync(path) && statSync(path).isFile() ? readFileSync(path, 'utf8') : null
  } catch {
    return null
  }
}

function walk(dir, filter, prefix = '') {
  const found = []
  let entries
  try {
    entries = readdirSync(dir, { withFileTypes: true })
  } catch {
    return found
  }
  for (const entry of entries) {
    const rel = prefix === '' ? entry.name : `${prefix}/${entry.name}`
    if (entry.isDirectory()) {
      if (['node_modules', 'dist', 'build', '.git', 'coverage'].includes(entry.name)) continue
      found.push(...walk(join(dir, entry.name), filter, rel))
      continue
    }
    if (filter(entry.name)) found.push(rel)
  }
  return found
}

/**
 * 生态探测：**只用来决定「这项检查适不适用」**，不用来判断合规。
 * 理由：把「工具不认识这门语言」写成「这个项目缺了东西」会产出假缺失，
 * 而退出码 1 正是驱动「只补缺项」流程的信号，被假缺失污染后整个流程失去意义。
 */
const LANG_BY_EXT = new Map([
  ['js', 'node'], ['mjs', 'node'], ['cjs', 'node'], ['ts', 'node'], ['tsx', 'node'], ['jsx', 'node'], ['vue', 'node'],
  ['py', 'python'], ['go', 'go'], ['java', 'java'], ['kt', 'kotlin'], ['rs', 'rust'],
])

/** 各生态测试文件的命名形状；不在表内的语言只报数量，不判缺失 */
const TEST_SHAPES = [
  { lang: 'node', re: /\.(test|spec)\.[cm]?[jt]sx?$/ },
  { lang: 'python', re: /(?:test_[^/\\]+\.py|[^/\\]+_test\.py)$/ },
  { lang: 'go', re: /[^/\\]+_test\.go$/ },
  { lang: 'java', re: /[^/\\]+Tests?\.java$/ },
]

function detectLangs(files) {
  const langs = new Set()
  for (const path of files) {
    const ext = path.slice(path.lastIndexOf('.') + 1).toLowerCase()
    const lang = LANG_BY_EXT.get(ext)
    if (lang !== undefined) langs.add(lang)
  }
  return langs
}

/** 约定目录一个都不存在时，用「顶层有源码的目录」兜底，免得整仓扫不到东西却报缺失 */
function inferRoots(files) {
  const dirs = new Set()
  for (const path of files) {
    const top = path.split('/')[0]
    if (top !== path && !['docs', 'public'].includes(top)) dirs.add(top)
  }
  return [...dirs].sort()
}

/** 优先用目标仓库自己的校验器；没有则退回 Skill 的 asset 副本（并据此判定该项缺失） */
async function loadChecker(target, fileName) {
  const projectPath = join(target, 'scripts', fileName)
  const projectSource = readIf(projectPath)
  if (projectSource !== null) {
    try {
      const mod = await import(pathToFileURL(projectPath).href)
      return { mod, fromProject: true }
    } catch {
      /* 项目里的脚本坏了，退回副本 */
    }
  }
  const mod = await import(pathToFileURL(join(SKILL_ROOT, 'assets', 'scripts', fileName)).href)
  return { mod, fromProject: false }
}

/**
 * 只在目标目录自身是 git 仓库时才执行 git 命令。
 * 必须显式判 .git：`git -C <子目录>` 会一路向上找到外层仓库，
 * 于是把父仓库的 hooksPath 与提交历史当成被体检项目的结论——实测发生过，报告看着全绿其实全错。
 */
function isGitRepo(dir) {
  return existsSync(join(dir, '.git'))
}

function git(target, args) {
  if (!isGitRepo(target)) return null
  try {
    return execFileSync('git', ['-C', target, ...args], { encoding: 'utf8' }).trim()
  } catch {
    return null
  }
}

async function main() {
  const arg = process.argv[2]
  if (arg === '--help' || arg === '-h') {
    console.log('用法: node scripts/audit.mjs [目标目录]')
    return
  }
  const target = resolve(arg ?? process.cwd())
  if (!existsSync(target) || !statSync(target).isDirectory()) {
    console.log(`⚠️ 目录不存在：${target}`)
    process.exit(2)
  }

  const r = makeReporter()
  const agents = readIf(join(target, 'AGENTS.md'))
  const pkgText = readIf(join(target, 'package.json'))
  const pkg = pkgText === null ? null : JSON.parse(pkgText)
  const gitignore = readIf(join(target, '.gitignore'))
  const sourceFiles = walk(target, (name) => LANG_BY_EXT.has(name.slice(name.lastIndexOf('.') + 1).toLowerCase()))
  const langs = detectLangs(sourceFiles)
  const langList = langs.size > 0 ? [...langs].sort().join(', ') : '无源码文件'

  // ---------- 文件级：约定的载体在不在 ----------
  if (agents === null) {
    r.report('文件级', 'missing', 'AGENTS.md 不存在——代理与新人都没有工作指南')
  } else {
    const agentLines = agents.split(/\r?\n/).length
    const agentBytes = Buffer.byteLength(agents, 'utf8')
    const agentPct = Math.round((agentBytes * 100) / AGENT_DOC_BUDGET_BYTES)
    const sizeText = `AGENTS.md（${agentLines} 行、${agentBytes} 字节，占 Codex 默认合并预算 ${agentPct}%）`
    if (agentBytes > AGENT_DOC_BUDGET_BYTES) {
      r.report('文件级', 'missing', `AGENTS.md 单文件 ${agentBytes} 字节，已超 ${AGENT_DOC_BUDGET_BYTES} 字节预算——往里加内容会把更靠近工作目录的 AGENTS.md 整份挤出加载范围，先精简或拆进 docs/`)
    } else if (agentBytes * 4 > AGENT_DOC_BUDGET_BYTES * 3) {
      r.report('文件级', 'warn', `${sizeText}——逼近预算。加条目前先自问「agent 读代码能不能自己推出来」，能推就删；只在特定轮次用的细则挪到 docs/ 并在此写明何时必读`)
    } else {
      r.report('文件级', 'ok', sizeText)
    }
    for (const section of REQUIRED_AGENT_SECTIONS) {
      if (!agents.includes(section)) {
        r.report('文件级', 'missing', `AGENTS.md 缺「${section}」章节`)
      }
    }
    const todo = (agents.match(/【待填】/g) ?? []).length
    if (todo > 0) {
      r.report('文件级', 'warn', `AGENTS.md 有 ${todo} 处【待填】未补（尤其「架构与扩展点」「环境与已知坑」必须人工写）`)
    }
    if (/\{\{[#^A-Z]/.test(agents)) r.report('文件级', 'warn', 'AGENTS.md 残留模板占位符 {{...}}')

    // 预算是逐层相加的：子目录里的 AGENTS.md 同样占这份额度（同目录的 override 与 AGENTS.md 只会加载一份，故这里是上限）
    const agentDocs = walk(target, (name) => name === 'AGENTS.md' || name === 'AGENTS.override.md')
    if (agentDocs.length > 1) {
      const totalBytes = agentDocs.reduce((sum, rel) => sum + Buffer.byteLength(readFileSync(join(target, rel), 'utf8'), 'utf8'), 0)
      r.report('文件级', 'info', `仓库内共 ${agentDocs.length} 份 AGENTS.md，合计上限 ${totalBytes} 字节——预算是根到工作目录逐层累加的，子目录那份也占额度`)
    }
  }

  const changelog = readIf(join(target, 'CHANGELOG.md'))
  if (changelog === null) r.report('文件级', 'missing', 'CHANGELOG.md 不存在（提交细节的统一去处）')
  else if (!changelog.includes('[Unreleased]')) r.report('文件级', 'warn', 'CHANGELOG.md 没有 [Unreleased] 区')
  else r.report('文件级', 'ok', 'CHANGELOG.md 含 [Unreleased]')

  const docs = existsSync(join(target, 'docs'))
    ? readdirSync(join(target, 'docs'), { withFileTypes: true }).filter((entry) => entry.isFile() && entry.name.endsWith('.md')).map((entry) => entry.name)
    : []
  if (docs.length === 0) r.report('文件级', 'missing', 'docs/ 为空——文档地图缺使用者手册/部署文档')
  else r.report('文件级', 'ok', `docs/ 有 ${docs.length} 份：${docs.slice(0, 4).join(', ')}${docs.length > 4 ? ' …' : ''}`)

  if (readIf(join(target, 'README.md')) === null) r.report('文件级', 'missing', 'README.md 不存在')

  // ---------- 执行级：约定是不是真能拦住 ----------
  const hook = readIf(join(target, 'scripts/hooks/commit-msg'))
  const checker = readIf(join(target, 'scripts/commit-msg-check.mjs'))
  if (hook === null) r.report('执行级', 'missing', '缺 scripts/hooks/commit-msg（提交信息没有机械拦截）')
  else if (checker === null) r.report('执行级', 'missing', '钩子存在但缺 scripts/commit-msg-check.mjs，钩子会静默跳过校验')
  else r.report('执行级', 'ok', 'commit-msg 钩子与校验脚本齐备')

  // 文档同步拦截是后加的能力：旧版校验脚本没有 checkDocSync 导出，报 warn 引导重拷升级
  if (checker !== null) {
    let hasDocSync = false
    try {
      const mod = await import(pathToFileURL(join(target, 'scripts', 'commit-msg-check.mjs')).href)
      hasDocSync = typeof mod.checkDocSync === 'function'
    } catch {
      /* 项目脚本损坏：历史级会经 loadChecker 兜底报告，这里不重复报 */
    }
    if (hasDocSync) r.report('执行级', 'ok', '文档同步拦截已内置（checkDocSync：重要文件改动需同步 README）')
    else r.report('执行级', 'warn', 'commit-msg-check.mjs 缺 checkDocSync（旧版本）——重要文件改动不会拦 README 未同步，从 Skill 的 assets/scripts/ 重拷可升级')
  }

  const inRepo = isGitRepo(target)
  if (!inRepo) {
    r.report('执行级', 'missing', `${target} 不是 git 仓库——钩子与提交历史无从生效（先 git init）`)
  }
  const hooksPath = git(target, ['config', 'core.hooksPath'])
  if (inRepo && hooksPath === null) r.report('执行级', 'missing', 'core.hooksPath 未设置——钩子实际不会运行（执行 scaffold.mjs --link-hooks）')
  else if (inRepo && hooksPath !== 'scripts/hooks') r.report('执行级', 'warn', `core.hooksPath = ${hooksPath}，与 scripts/hooks 不一致`)
  else if (inRepo) r.report('执行级', 'ok', 'core.hooksPath 已指向 scripts/hooks')

  const lineChecker = readIf(join(target, 'scripts/check-long-files.mjs'))
  if (lineChecker === null) r.report('执行级', 'missing', '缺 scripts/check-long-files.mjs（收尾行数硬检查无法执行）')
  else if (agents !== null && !agents.includes('check-long-files')) r.report('执行级', 'warn', '检查脚本存在，但 AGENTS.md 没把它写进收尾必做项')

  // ---------- 配置级 ----------
  if (gitignore === null) {
    r.report('配置级', 'missing', '.gitignore 不存在')
  } else {
    const patterns = gitignore.split(/\r?\n/).map((line) => line.trim())
    // 容忍 `dist` 与 `dist/` 两种写法，别因为少一个斜杠就报缺失
    const covers = (name) => patterns.some((line) => line.replace(/\/+$/, '') === name)
    if (langs.has('node')) {
      for (const [needle, label] of [
        ['node_modules', '依赖目录'],
        ['dist', '构建产物'],
      ]) {
        if (covers(needle)) r.report('配置级', 'ok', `.gitignore 覆盖${label}`)
        else r.report('配置级', 'missing', `.gitignore 未忽略${label}（${needle}/）`)
      }
    } else {
      r.report('配置级', 'info', `识别到的生态：${langList}——不是 Node 项目，跳过 node_modules/dist 检查（构建产物目录请按项目实际补进 .gitignore）`)
    }
    const coversRuntime = patterns.some((line) => /data\/$|server\/data\/$|\/data$/u.test(line))
    if (coversRuntime) r.report('配置级', 'ok', '.gitignore 覆盖运行时数据目录')
    else r.report('配置级', 'warn', '.gitignore 未忽略运行时数据目录——含真实数据的 *.json 最容易在 git add -A 时误入')
    if (patterns.includes('nul')) r.report('配置级', 'ok', '.gitignore 覆盖 Windows 保留设备名（防 `> nul` 误建文件入库）')
    else r.report('配置级', 'warn', '.gitignore 未忽略 nul/con/aux 等保留设备名（bash 里 `> nul` 会建出真实文件）')
  }

  if (pkg !== null) {
    const scripts = pkg.scripts ?? {}
    for (const key of ['build', 'test', 'lint']) {
      if (scripts[key] === undefined) r.report('配置级', 'missing', `package.json 缺 "${key}" 脚本（AGENTS.md 常用命令指向的东西要真存在）`)
    }
    if (scripts.server !== undefined && scripts['typecheck:server'] === undefined) {
      r.report('配置级', 'warn', '有 server 脚本却没有 typecheck:server——后端改动将没有任何类型把关')
    }
    const hasVue = pkg.dependencies?.vue !== undefined || pkg.devDependencies?.vue !== undefined
    const tsconfig = readIf(join(target, 'tsconfig.json'))
    if (hasVue && tsconfig === null) r.report('配置级', 'missing', '有 Vue 依赖却没有 tsconfig.json')
    else if (tsconfig !== null) {
      for (const flag of ['"strict"', '"noUnusedLocals"', '"noUnusedParameters"']) {
        if (!tsconfig.includes(flag)) r.report('配置级', 'missing', `tsconfig.json 未开 ${flag}——严格模式是构建期兜错的最低成本配置`)
      }
    }
  } else {
    r.report('配置级', 'info', `没有 package.json，跳过 build/test/lint 脚本与 tsconfig 检查（识别到的生态：${langList}）`)
  }

  // ---------- 历史级：既有提交符不符合约定 ----------
  const subjectsRaw = git(target, ['log', '--format=%s', '-n', '30'])
  if (subjectsRaw !== null && checker !== null) {
    const loaded = await loadChecker(target, 'commit-msg-check.mjs')
    const subjects = subjectsRaw.split(/\r?\n/).filter((line) => line !== '')
    const bad = subjects.filter((subject) => !loaded.mod.checkCommitMessage(subject).ok)
    if (subjects.length === 0) r.report('历史级', 'info', '仓库暂无提交')
    else if (bad.length === 0) r.report('历史级', 'ok', `最近 ${subjects.length} 条提交标题全部合规（来源：${loaded.fromProject ? '项目自身脚本' : 'Skill 副本'}）`)
    else {
      r.report('历史级', 'warn', `最近 ${subjects.length} 条里有 ${bad.length} 条不合规，示例：${bad.slice(0, 3).join(' ｜ ')}`)
      r.report('历史级', 'info', '历史不合规属欠账，不要求改写；约定是从下一个提交开始生效')
    }
  } else if (checker === null) {
    r.report('历史级', 'info', '无校验脚本，跳过历史提交抽样')
  } else {
    r.report('历史级', 'info', '非 git 仓库或暂无提交，跳过历史提交抽样')
  }

  // ---------- 代码健康 ----------
  const loadedLines = await loadChecker(target, 'check-long-files.mjs')
  const fixedRoots = ['src', 'server', 'shared', 'scripts'].filter((root) => existsSync(join(target, root)))
  const roots = fixedRoots.length > 0 ? fixedRoots : inferRoots(sourceFiles)
  if (roots.length === 0) r.report('代码健康', 'info', '没有可扫描的源码目录')
  else {
    if (fixedRoots.length === 0) r.report('代码健康', 'info', `约定目录（src/server/shared/scripts）都不存在，改用顶层源码目录：${roots.join(', ')}`)
    if (!langs.has('node')) r.report('代码健康', 'info', `行数阈值只覆盖 js/ts/vue/css 扩展名，${langList} 的文件不参与检查（需要门槛用 --limit <扩展名>=400 自行加）`)
    const { over, skipped } = loadedLines.mod.scanLongFiles(target, { roots, exclude: [] })
    if (over.length === 0) r.report('代码健康', 'ok', `${roots.join(', ')} 内无超长文件`)
    else {
      for (const item of over.slice(0, 8)) {
        r.report('代码健康', 'warn', `超长 ${item.lines}/${item.limit} 行：${item.path}`)
      }
      if (over.length > 8) r.report('代码健康', 'info', `另有 ${over.length - 8} 个超长文件，跑 node scripts/check-long-files.mjs 看全量`)
      r.report('代码健康', 'info', '既有欠账不阻塞无关提交，但触及这些文件时必须当次拆完')
      r.report('代码健康', 'info', '本体检不带项目的豁免：数据/图标定义类长文件属正常，请把 --exclude 写进项目的 check:lines 参数（例外必须可见）')
    }
    if (skipped > 0) r.report('代码健康', 'info', `有 ${skipped} 个文件命中豁免（豁免应写在检查脚本参数里，且必须可见）`)
  }

  const shapes = TEST_SHAPES.filter((shape) => langs.has(shape.lang))
  const tests = sourceFiles.filter((path) => shapes.some((shape) => shape.re.test(path)))
  if (shapes.length === 0) {
    r.report('代码健康', 'info', `没有为「${langList}」定义测试文件的命名形状，跳过测试文件检查（别把工具不认识当成项目缺失）`)
  } else if (tests.length === 0) r.report('代码健康', 'missing', '一个测试文件都没有——核心逻辑没有同目录测试')
  else if (!langs.has('node')) {
    r.report('代码健康', 'ok', `${tests.length} 个测试文件（非 Node 生态，只报数量——「与被测文件同目录」是本项目约定的惯例，各语言习惯不同，不据此判缺失）`)
  } else {
    const coLocated = tests.filter((path) => !path.includes('/__tests__/'))
    r.report('代码健康', 'ok', `${tests.length} 个测试文件（其中 ${coLocated.length} 个与被测文件同目录）`)
    if (langs.has('node') && coLocated.length === 0) {
      r.report('代码健康', 'warn', '测试全部集中在 __tests__，未遵循「与被测文件同目录」')
    }
  }

  const missingCount = r.print()
  process.exit(missingCount > 0 ? 1 : 0)
}

main().catch((error) => {
  console.log(`⚠️ 体检中断：${error instanceof Error ? error.message : String(error)}`)
  process.exit(2)
})
