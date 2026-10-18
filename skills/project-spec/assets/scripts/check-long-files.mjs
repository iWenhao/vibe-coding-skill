/**
 * 收尾硬性检查：统计源码文件行数，列出超过各自阈值的文件。
 *
 * 用途：AGENTS.md「收尾硬性检查」要求的自检脚本，也是 CI 与提交前手动把关的入口。
 *       （刻意不挂成 pre-commit——历史欠账会挡住所有无关提交，见 AGENTS.md「收尾硬性检查」。）
 * 阈值按扩展名区分（与 AGENTS.md 约定一致）：*.vue / *.ts / *.tsx / *.js / *.mjs = 400 行，*.scss / *.css = 500 行。
 *
 * 用法（在仓库根目录执行）：
 *   node scripts/check-long-files.mjs
 *   node scripts/check-long-files.mjs --roots src,server --exclude "src/icons/*" --limit vue=500
 *   node scripts/check-long-files.mjs --json          # 给 CI/工具消费
 *   （`--名字 值` 与 `--名字=值` 两种写法等价；`--名字` 后面没跟值会告警并忽略该参数）
 *
 * 为什么是 Node 而不是 PowerShell：
 *   1. 跨平台——CI 与非 Windows 的 agent 也能跑同一条命令；
 *   2. 无编码陷阱——PS 5.1 按 ANSI 代码页读脚本，中文注释的 .ps1 必须存成带 BOM 的 UTF-8 才不 ParserError；
 *   3. 计行与行尾风格无关（见下方 countLines），仓库内 CRLF/LF 混用是常态。
 *
 * 例外必须可见：命中 --exclude 的文件不参与门槛，但末尾会报出跳过数量，不能变成静默豁免。
 */
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { join, relative, sep } from 'node:path'
import { pathToFileURL } from 'node:url'

/** 扩展名 -> 行数阈值（不含前导点） */
export const DEFAULT_LIMITS = {
  vue: 400,
  ts: 400,
  tsx: 400,
  js: 400,
  mjs: 400,
  cjs: 400,
  scss: 500,
  css: 500,
}

/** 不扫描的目录名（任何层级命中即跳过） */
export const DEFAULT_SKIP_DIRS = ['node_modules', 'dist', 'build', '.git', 'coverage', 'server/data']

/** 默认扫描目录：无配置时的兜底，实际项目用 --roots 指定 */
export const DEFAULT_ROOTS = ['src']

/**
 * 计行：读全文后按换行切分，并丢弃末尾空元素。
 * 语义等价于 .NET 的 ReadAllLines().Count——不能用「非空行数」，那会让接近阈值的文件静默通过。
 * @param {string} text
 */
export function countLines(text) {
  const parts = text.split(/\r\n|\r|\n/)
  if (parts.length > 0 && parts[parts.length - 1] === '') parts.pop()
  return parts.length
}

/** 把 a\\b\\c 归一成相对仓库根的正斜杠路径，便于与 --exclude 的 glob 比对 */
function toPosix(repoRoot, absolute) {
  let rel = relative(repoRoot, absolute)
  if (rel === '') rel = absolute
  return rel.split(sep).join('/')
}

/** glob 只支持结尾 *（覆盖其下所有层级）与前缀匹配，够用且可预测 */
function isExcluded(path, patterns) {
  return patterns.some((pattern) => {
    if (pattern.endsWith('*')) return path.startsWith(pattern.slice(0, -1))
    return path === pattern
  })
}

/**
 * 扫描超长文件。
 * @param {string} repoRoot 仓库根（绝对路径）
 * @param {{roots?: string[], limits?: Record<string, number>, exclude?: string[], skipDirs?: string[]}} [options]
 * @returns {{over: Array<{lines: number, limit: number, path: string}>, scanned: number, skipped: number}}
 */
export function scanLongFiles(repoRoot, options = {}) {
  const roots = options.roots ?? DEFAULT_ROOTS
  const limits = { ...DEFAULT_LIMITS, ...(options.limits ?? {}) }
  const exclude = options.exclude ?? []
  const skipDirs = options.skipDirs ?? DEFAULT_SKIP_DIRS

  const results = []
  let scanned = 0
  let skipped = 0

  const walk = (dir) => {
    let entries
    try {
      entries = readdirSync(dir, { withFileTypes: true })
    } catch {
      return // 目录不存在/无权限：跳过而不是让整次检查崩掉
    }
    for (const entry of entries) {
      const absolute = join(dir, entry.name)
      if (entry.isDirectory()) {
        const rel = toPosix(repoRoot, absolute)
        if (skipDirs.includes(entry.name) || skipDirs.includes(rel)) continue
        walk(absolute)
        continue
      }
      if (!entry.isFile()) continue
      const ext = entry.name.split('.').pop().toLowerCase()
      const limit = limits[ext]
      if (limit === undefined) continue
      // 测试与声明文件按内容性质不受「逻辑文件超长」约束
      if (/\.(test|spec)\.[cm]?[jt]sx?$/.test(entry.name) || entry.name.endsWith('.d.ts')) continue

      const rel = toPosix(repoRoot, absolute)
      if (isExcluded(rel, exclude)) {
        skipped++
        continue
      }
      let text
      try {
        text = readFileSync(absolute, 'utf8')
      } catch {
        continue
      }
      const lines = countLines(text)
      scanned++
      if (lines > limit) results.push({ lines, limit, path: rel })
    }
  }

  for (const root of roots) {
    const absolute = join(repoRoot, root)
    try {
      if (!statSync(absolute).isDirectory()) continue
    } catch {
      continue // 该仓库没有这个目录，正常情况
    }
    walk(absolute)
  }

  results.sort((a, b) => b.lines - a.lines)
  return { over: results, scanned, skipped }
}

// CLI 入口；退出码 0 = 无超限，1 = 有超限（供 CI/钩子拦截）
const invokedDirectly =
  process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href

if (invokedDirectly) {
  const argv = process.argv.slice(2)
  /** `--名字=值` 与 `--名字 值` 两种写法都吃，与 scaffold.mjs 的空格风格保持一致 */
  const readFlag = (name) => {
    const inline = argv.find((item) => item.startsWith(`--${name}=`))
    if (inline !== undefined) return inline.slice(name.length + 3)
    const index = argv.indexOf(`--${name}`)
    if (index === -1) return undefined
    const value = argv[index + 1]
    if (value === undefined || value.startsWith('--')) {
      console.error(`⚠️ --${name} 后面没取到值，本次忽略该参数`)
      return undefined
    }
    return value
  }

  const rootsRaw = readFlag('roots')
  const excludeRaw = readFlag('exclude')
  const limitsRaw = readFlag('limit')
  const asJson = argv.includes('--json')

  const limits = {}
  for (const item of (limitsRaw ?? '').split(',').filter(Boolean)) {
    const [ext, value] = item.split('=')
    const parsed = Number(value)
    if (ext && Number.isFinite(parsed)) limits[ext.replace(/^\./, '').toLowerCase()] = parsed
  }

  const { over, skipped } = scanLongFiles(process.cwd(), {
    roots: rootsRaw === undefined ? DEFAULT_ROOTS : rootsRaw.split(',').filter(Boolean),
    exclude: excludeRaw === undefined ? [] : excludeRaw.split(',').filter(Boolean),
    limits,
  })

  if (asJson) {
    console.log(JSON.stringify({ over, skipped }))
  } else if (over.length > 0) {
    console.log('以下文件超过行数阈值（AGENTS.md：属本次改动新增或触及的，当次拆完再提交）：')
    for (const item of over) {
      console.log(`  ${String(item.lines).padStart(5)} / ${item.limit}  ${item.path}`)
    }
  } else {
    console.log('OK: 所有文件均在阈值以内。')
  }

  if (skipped > 0 && !asJson) {
    console.log(`（已按例外跳过 ${skipped} 个文件——例外必须可见）`)
  }

  process.exit(over.length > 0 ? 1 : 0)
}
