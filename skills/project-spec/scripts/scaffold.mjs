#!/usr/bin/env node
/**
 * 按约定内核生成新项目骨架（把 assets/ 下的模板落到目标目录并完成占位替换）。
 *
 * 用法：
 *   node scripts/scaffold.mjs --target D:/code/my-app --name my-app --desc "内部工单看板" \
 *        [--stack vue-ts|none] [--backend] [--dev-port 5173] [--api-port 5174] [--force]
 *        （--backend 仅能与 --stack vue-ts 搭配：none 没有承载它的前端请求层与构建脚本）
 *   node scripts/scaffold.mjs --link-hooks D:/code/my-app     # 单独启用提交信息钩子
 *
 * 设计约束：
 *   - 脚本只生成「规范 + 骨架」，不生成领域代码；AGENTS.md 里【待填】的章节必须人工补。
 *   - 默认不覆盖已有文件（逐个告警），--force 才覆盖——体检补齐场景不能顺手改坏别人的仓库。
 *   - 输出给 agent 读：一条文件一行，末尾固定一段 NEXT 提示，不打印堆栈。
 */
import { chmodSync, existsSync, readdirSync, readFileSync, mkdirSync, writeFileSync } from 'node:fs'
import { basename, dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { execFileSync } from 'node:child_process'

const SKILL_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const ASSETS_ROOT = join(SKILL_ROOT, 'assets')

/** 递归收集 assets 下的模板文件，返回 {src, dest} 相对路径对 */
function collectFiles(dir, prefix = '') {
  const found = []
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const rel = prefix === '' ? entry.name : `${prefix}/${entry.name}`
    const absolute = join(dir, entry.name)
    if (entry.isDirectory()) {
      found.push(...collectFiles(absolute, rel))
      continue
    }
    if (entry.isFile()) found.push({ src: rel, absolute })
  }
  return found
}

/** 目标文件名：gitignore/env.example 需要补回前导点，其余只去掉 .tpl 后缀 */
function targetName(rel) {
  if (rel === 'gitignore.tpl') return '.gitignore'
  if (rel === 'env.example.tpl') return '.env.example'
  return rel.endsWith('.tpl') ? rel.slice(0, -4) : rel
}

/**
 * 决定是否纳入本次生成，并返回落到目标仓库的相对路径。
 * stack-vue-ts/ 整个目录只在 Vue 栈下出；后端相关文件只在 --backend 下出。
 * 返回 null 表示不生成。
 */
function includeFile(rel, vars) {
  const isStack = rel.startsWith('stack-vue-ts/')
  if (isStack && vars.STACK !== 'vue-ts') return null
  const withoutPrefix = isStack ? rel.slice('stack-vue-ts/'.length) : rel
  const destRel = targetName(withoutPrefix)
  // 后端专属三处：服务端目录、服务端类型检查配置，以及前端那层请求封装——
  // 没有后端就没有信封可拆，生成一份没人调用的 client.ts 只是让新仓库多一个死文件
  const backendOnly =
    destRel === 'tsconfig.server.json' || destRel.startsWith('server/') || destRel.startsWith('src/api/')
  if (!vars.BACKEND && backendOnly) {
    return null
  }
  // 下面两类文件只对 Vue 栈有意义：none 没有构建期环境变量，也没有 vitest/TypeScript 运行时，
  // 生成过去只会留下打不开的死配置与跑不了的死测试。
  if (!vars.VUE_TS && destRel === '.env.example') return null
  if (!vars.VUE_TS && destRel.endsWith('.test.ts')) return null
  return destRel
}

/** 可作为块条件（{{#X}} / {{^X}}）的变量名。不在表内就报错——静默当假值会让整段内容无声消失 */
const BLOCK_VARS = ['VUE_TS', 'BACKEND']

/** 块作用域取真值：0 与空串都算假，符合模板里「没传就等于不生成这段」的直觉 */
function truthy(value) {
  return value !== undefined && value !== null && value !== false && value !== '' && value !== 0
}

/** 从 from 起找到与 name 配对的闭合标签（支持同名块嵌套） */
function findClose(text, name, from) {
  const scan = new RegExp(`\\{\\{([#^/])${name}\\}\\}`, 'g')
  scan.lastIndex = from
  let depth = 1
  let match
  while ((match = scan.exec(text)) !== null) {
    if (match[1] === '/') {
      depth--
      if (depth === 0) return { start: match.index, end: match.index + match[0].length }
    } else {
      depth++
    }
  }
  throw new Error(`模板块 {{#${name}}} 缺少闭合 {{/${name}}}`)
}

function renderBlocks(text, vars, sourceName) {
  const tag = /\{\{([#^])([A-Za-z_][A-Za-z0-9_]*)\}\}/
  let out = ''
  let cursor = 0
  while (cursor < text.length) {
    const rest = text.slice(cursor)
    const match = tag.exec(rest)
    if (match === null) {
      out += rest
      break
    }
    out += rest.slice(0, match.index)
    const name = match[2]
    if (!BLOCK_VARS.includes(name)) {
      throw new Error(`${sourceName}: 块 {{${match[1]}${name}}} 的条件变量未声明，可用条件仅 ${BLOCK_VARS.join(' / ')}`)
    }
    const bodyStart = match.index + match[0].length
    const close = findClose(text, name, cursor + bodyStart)
    const body = text.slice(cursor + bodyStart, close.start)
    const keep = match[1] === '^' ? !truthy(vars[name]) : truthy(vars[name])
    if (keep) out += renderBlocks(body, vars, sourceName)
    cursor = close.end
  }
  return out
}

function render(template, vars, sourceName) {
  const blocked = renderBlocks(template, vars, sourceName)
  return blocked.replace(/\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}/g, (all, name) => {
    if (!(name in vars)) throw new Error(`${sourceName}: 模板变量 ${all} 没有对应取值`)
    return String(vars[name])
  })
}

function parseArgs(argv) {
  const args = {}
  for (let i = 0; i < argv.length; i++) {
    const item = argv[i]
    if (!item.startsWith('--')) continue
    const eq = item.indexOf('=')
    if (eq !== -1) {
      args[item.slice(2, eq)] = item.slice(eq + 1)
      continue
    }
    const key = item.slice(2)
    const next = argv[i + 1]
    if (next !== undefined && !next.startsWith('--')) {
      args[key] = next
      i++
    } else {
      args[key] = true
    }
  }
  return args
}

/** 启用钩子：core.hooksPath 是每个克隆一次的本地配置，无法随仓库提交 */
function linkHooks(target) {
  if (!existsSync(join(target, '.git'))) {
    console.log(`⚠️ ${target} 还不是 git 仓库——先执行 git init，再重跑本命令`)
    process.exit(1)
  }
  if (!existsSync(join(target, 'scripts/hooks/commit-msg'))) {
    console.log('⚠️ 未找到 scripts/hooks/commit-msg，先用 scaffold.mjs 生成骨架')
    process.exit(1)
  }
  try {
    execFileSync('git', ['-C', target, 'config', 'core.hooksPath', 'scripts/hooks'], { stdio: 'ignore' })
    const configured = execFileSync('git', ['-C', target, 'config', 'core.hooksPath'], { encoding: 'utf8' }).trim()
    console.log(`✅ core.hooksPath = ${configured}`)
    // 把「接上了哪几条」念出来：只说 commit-msg 会让推送前那道全量把关没人知道它在
    const wired = readdirSync(join(target, 'scripts/hooks')).filter((f) => !f.startsWith('.'))
    console.log(`   本次接上的钩子：${wired.join(' / ')}`)
  } catch {
    console.log('⚠️ git 不可用，请手工执行：git config core.hooksPath scripts/hooks')
    process.exit(1)
  }
}

function main() {
  const args = parseArgs(process.argv.slice(2))

  if (args['link-hooks'] !== undefined) {
    linkHooks(resolve(String(args['link-hooks'])))
    return
  }

  if (args.target === undefined) {
    console.log('用法: node scripts/scaffold.mjs --target <目录> --name <项目名> [--desc "..."] [--stack vue-ts|none] [--backend]')
    process.exit(2)
  }

  const target = resolve(String(args.target))
  const name = String(args.name ?? basename(target))
  const vars = {
    NAME: name,
    TITLE: String(args.title ?? name),
    DESC: String(args.desc ?? '【待填】一句话描述这个项目'),
    STACK: String(args.stack ?? 'vue-ts'),
    // 模板里的条件块按「是不是这套栈」判断，而不是比较字符串
    VUE_TS: String(args.stack ?? 'vue-ts') === 'vue-ts',
    BACKEND: args.backend === true,
    DEV_PORT: String(args['dev-port'] ?? '5173'),
    API_PORT: String(args['api-port'] ?? '5174'),
  }
  if (!['vue-ts', 'none'].includes(vars.STACK)) {
    console.log(`⚠️ --stack 只支持 vue-ts 或 none，收到 ${vars.STACK}`)
    process.exit(2)
  }
  if (vars.STACK === 'none' && vars.BACKEND) {
    console.log('⚠️ --backend 需要与 --stack vue-ts 搭配：后端的前端请求封装、构建脚本与服务端类型检查都随 Vue 栈生成；')
    console.log('   --stack none 只会留下文档和一个没有前端调用的服务端。请去掉 --backend，或改用 --stack vue-ts。')
    process.exit(2)
  }

  mkdirSync(target, { recursive: true })

  /** 只有 .tpl 才做占位替换：脚本类资产原样拷贝，避免把 JSDoc 里的 {{...}} 误判成残留 */
  const written = []
  const skipped = []
  let placeholders = 0

  for (const file of collectFiles(ASSETS_ROOT)) {
    const destRel = includeFile(file.src, vars)
    if (destRel === null) continue
    const dest = join(target, destRel)
    if (existsSync(dest) && args.force !== true) {
      skipped.push(destRel)
      continue
    }

    const raw = readFileSync(file.absolute, 'utf8')
    const isTemplate = file.src.endsWith('.tpl')
    const content = isTemplate ? render(raw, vars, file.src) : raw
    placeholders += (content.match(/【待填】/g) ?? []).length
    mkdirSync(dirname(dest), { recursive: true })
    writeFileSync(dest, content, 'utf8')
    // 钩子必须带可执行位，否则 core.hooksPath 指向它也不会被调用。
    // 按前缀判定，不要逐个列名字——漏一个就是一道只在开发机生效的把关（Windows 的 git 不看这个位）。
    if (destRel.startsWith('scripts/hooks/')) chmodSync(dest, 0o755)
    written.push({ path: destRel, rendered: isTemplate })
  }

  // 未替换干净的占位符 = 模板变量没喂到，必须当场暴露
  const leftovers = written
    .filter((item) => item.rendered)
    .filter((item) => /\{\{[#^\/A-Za-z]/.test(readFileSync(join(target, item.path), 'utf8')))
    .map((item) => item.path)

  console.log(`项目骨架 → ${target}`)
  if (vars.VUE_TS) {
    console.log(`  栈=${vars.STACK} 后端=${vars.BACKEND ? '有' : '无'} 端口=${vars.DEV_PORT}${vars.BACKEND ? `/${vars.API_PORT}` : ''}`)
  } else {
    console.log('  栈=none（无内置技术栈；只生成规范、钩子与检查脚本）')
  }
  for (const item of written) console.log(`  + ${item.path}`)
  for (const destRel of skipped) console.log(`  = ${destRel}（已存在，跳过；--force 才覆盖）`)
  if (leftovers.length > 0) {
    console.log(`⚠️ 以下文件残留模板占位符，检查变量是否漏传：${leftovers.join(', ')}`)
  }

  console.log('')
  console.log('下一步（脚本代不了）：')
  console.log('  1. 启用钩子（每个克隆一次，本地配置无法提交；一次配置同时接上提交信息拦截与推送前全量把关）：')
  console.log(`     node ${join(SKILL_ROOT, 'scripts/scaffold.mjs')} --link-hooks ${target}`)
  if (vars.VUE_TS) {
    console.log('  2. 装依赖并跑通：pnpm install && pnpm build && npx vitest run')
  } else {
    console.log('  2. 按 AGENTS.md「常用命令」补齐本栈的安装/开发/构建/测试命令（当前是【待填】），并真跑一次')
  }
  console.log(`  3. 补 AGENTS.md 的【待填】章节，共 ${placeholders} 处（搜「【待填】」）——`)
  console.log('     其中「架构与扩展点」与「环境与已知坑」必须人工写，脚手架编不出来')
  console.log('  4. 验证钩子真的会拒绝不合规提交（见 SKILL.md 模式一第 5 步），别只看绿灯')
}

main()
