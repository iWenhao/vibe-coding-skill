#!/usr/bin/env node
/**
 * 「目标仓库的事实」探测层：读文件、走目录、判语言、跑 git、加载目标仓库自己的校验脚本。
 * 从 audit.mjs 拆出来的，两边同目录、随 Skill 一起分发。
 *
 * 分工：这一层只回答「有没有、是什么」，不判断合规、不产出报告——所有 ⬜/⚠️ 判定留在 audit.mjs。
 * 这样拆还有个副作用上的好处：这一层里没有任何「缺失」措辞，读代码的人不会把探测函数误当成判据。
 */
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { execFileSync } from 'node:child_process'

const SKILL_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')

/** 文件不存在返回 null（不抛），让调用方把「读不到」当成一种事实而不是异常 */
export function readIf(path) {
  try {
    return existsSync(path) && statSync(path).isFile() ? readFileSync(path, 'utf8') : null
  } catch {
    return null
  }
}

/** 相对仓库根的正斜杠路径清单；构建产物与依赖目录不进候选集 */
export function walk(dir, filter, prefix = '') {
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

export const LANG_BY_EXT = new Map([
  ['js', 'node'], ['mjs', 'node'], ['cjs', 'node'], ['ts', 'node'], ['tsx', 'node'], ['jsx', 'node'], ['vue', 'node'],
  ['py', 'python'], ['go', 'go'], ['java', 'java'], ['kt', 'kotlin'], ['rs', 'rust'],
])

/** 各生态测试文件的命名形状；不在表内的语言只报数量，不判缺失 */
export const TEST_SHAPES = [
  { lang: 'node', re: /\.(test|spec)\.[cm]?[jt]sx?$/ },
  { lang: 'python', re: /(?:test_[^/\\]+\.py|[^/\\]+_test\.py)$/ },
  { lang: 'go', re: /[^/\\]+_test\.go$/ },
  { lang: 'java', re: /[^/\\]+Tests?\.java$/ },
]

/**
 * 生态探测：**只用来决定「这项检查适不适用」**，不用来判断合规。
 * 理由：把「工具不认识这门语言」写成「这个项目缺了东西」会产出假缺失，
 * 而退出码 1 正是驱动「只补缺项」流程的信号，被假缺失污染后整个流程失去意义。
 */
export function detectLangs(files) {
  const langs = new Set()
  for (const path of files) {
    const ext = path.slice(path.lastIndexOf('.') + 1).toLowerCase()
    const lang = LANG_BY_EXT.get(ext)
    if (lang !== undefined) langs.add(lang)
  }
  return langs
}

/** 约定目录一个都不存在时，用「顶层有源码的目录」兜底，免得整仓扫不到东西却报缺失 */
export function inferRoots(files) {
  const dirs = new Set()
  for (const path of files) {
    const top = path.split('/')[0]
    if (top !== path && !['docs', 'public'].includes(top)) dirs.add(top)
  }
  return [...dirs].sort()
}

/** 优先用目标仓库自己的校验器；没有则退回 Skill 的 asset 副本（并据此判定该项缺失） */
export async function loadChecker(target, fileName) {
  const projectPath = join(target, 'scripts', fileName)
  if (readIf(projectPath) !== null) {
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
export function isGitRepo(dir) {
  return existsSync(join(dir, '.git'))
}

export function git(target, args) {
  if (!isGitRepo(target)) return null
  try {
    // stderr 一并吞掉：空仓库跑 `git log` 会往报告里插一行 fatal，看着像工具本身坏了
    return execFileSync('git', ['-C', target, ...args], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim()
  } catch {
    return null
  }
}
