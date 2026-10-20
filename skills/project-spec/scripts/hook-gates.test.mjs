import assert from 'node:assert/strict'
import { test } from 'node:test'
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import {
  DOC_SYNC_MARKER,
  DOC_SYNC_RULES,
  MAX_SUBJECT_LENGTH,
  PREFIXES,
  checkCommitMessage,
  checkDocSync,
} from '../assets/scripts/commit-msg-check.mjs'
import {
  ZERO_OID,
  decidePush,
  parseRefLines,
  pickPackageManager,
  planSteps,
} from '../assets/scripts/pre-push-check.mjs'
import { scanLongFiles } from '../assets/scripts/check-long-files.mjs'

// 本仓库吃自己的狗粮：钩子用的就是 assets/ 里这份校验器，所以它也得有自己的测试。
// 用 node:test 而不是 vitest——本仓库零第三方依赖，`node --test "skills/project-spec/scripts/*.test.mjs"` 直接跑。
// 同一套断言在生成的项目里由 scripts/commit-msg-check.test.ts 与 scripts/pre-push-check.test.ts 跑（那是给用户仓库的那一份）。

test('标题按字符计长度，中文不会被按字节误判', () => {
  const long = `功能: ${'测'.repeat(MAX_SUBJECT_LENGTH)}`
  assert.equal([...long].length, MAX_SUBJECT_LENGTH + 4)
  assert.equal(checkCommitMessage(long).ok, false)
  assert.equal(checkCommitMessage('修复: 亮色主题下画布背景仍是黑色').ok, true)
})

test('前缀白名单与豁免前缀行为', () => {
  assert.ok(PREFIXES.length >= 9)
  assert.equal(checkCommitMessage('新增: 一个按钮').ok, false)
  assert.equal(checkCommitMessage('Merge branch "dev" into master').exempt, true)
})

test('文档同步是成对规则：每条规则只认自己那份文档', () => {
  const docs = new Set(DOC_SYNC_RULES.map((rule) => rule.doc))
  assert.ok(docs.has('README.md') && docs.has('docs/DEPLOY.md'))
  assert.equal(checkDocSync(['server/index.mjs', 'README.md'], '功能: 加端点').blocked, true)
  assert.equal(checkDocSync(['server/index.mjs', 'docs/DEPLOY.md'], '功能: 加端点').blocked, false)
  assert.equal(checkDocSync(['package.json', 'README.md'], '功能: 换构建脚本').blocked, false)
})

test('规则文件清单只到目录级与根文件级，不带任何项目自有名字', () => {
  // 校验器会原样拷进任何项目，清单里出现某个项目的端点路径或业务名，换一个项目就变成误拦。
  // 允许 `src/api/`、`server/` 这类 Skill 自己定义的目录，禁的是目录以下的具名条目。
  const forbidden = /storage|scada|konva|ticket|工单|图元|health/i
  for (const rule of DOC_SYNC_RULES) {
    for (const pattern of rule.files) {
      const text = typeof pattern === 'string' ? pattern : pattern.source
      assert.doesNotMatch(text, forbidden, `规则 ${rule.doc} 的清单含项目自有名字：${text}`)
    }
  }
})

test('豁免标记放行两条规则并留下可见提示', () => {
  const result = checkDocSync(['package.json', 'server/index.mjs'], `功能: 加端点\n\n${DOC_SYNC_MARKER}`)
  assert.equal(result.blocked, false)
  assert.match(result.notices[0], /skip-docs/)
})

test('取不到暂存区清单时降级为提示，不堵死提交', () => {
  const result = checkDocSync(null, '功能: 加端点')
  assert.equal(result.blocked, false)
  assert.equal(result.notices.length, 1)
})

const REAL_OID = 'a'.repeat(40)
const ref = (localRef, localOid = REAL_OID, remoteOid = 'b'.repeat(40)) => ({
  localRef,
  localOid,
  remoteRef: localRef,
  remoteOid,
})

test('推送清单解析：四字段齐才算数，缺字段返回 null', () => {
  assert.equal(parseRefLines(`refs/heads/main ${REAL_OID} refs/heads/main ${'b'.repeat(40)}`).length, 1)
  assert.deepEqual(parseRefLines(''), [], '空清单是「这次没推引用」，与「清单读不到」是两件事')
  assert.equal(parseRefLines('refs/heads/main aaaa'), null)
})

test('只有真的有新代码离开本机才跑全量', () => {
  assert.equal(decidePush(null).skip, false, '清单不可得时按最严路径，不能变成静默放行')
  assert.equal(decidePush([]).skip, true)
  // git 用「本地 oid 全 0」表示删除远端引用；「远端 oid 全 0」是**新建分支**，那是新代码，必须跑
  assert.equal(decidePush([ref('refs/heads/x', ZERO_OID)]).skip, true)
  assert.equal(decidePush([ref('refs/heads/new', REAL_OID, ZERO_OID)]).skip, false)
  assert.equal(decidePush([ref('refs/tags/v1.0.0')]).skip, true)
  assert.equal(decidePush([ref('refs/heads/dev')]).skip, false)
})

test('把关步骤按仓库实际能力生成，清单外的步骤绝不假装跑过', () => {
  const empty = { pm: 'npm', hasVitest: false, packageScripts: {}, hasLineChecker: false }
  assert.deepEqual(planSteps(empty), [])
  assert.deepEqual(
    planSteps({ ...empty, hasVitest: true, packageScripts: { build: 'vue-tsc --noEmit && vite build' } }).map((s) => s.name),
    ['全量测试', '构建（含 vue-tsc 类型检查）'],
  )
  assert.deepEqual(planSteps({ ...empty, hasLineChecker: true })[0].args, ['scripts/check-long-files.mjs'])
})

test('包管理器取仓库声明，其次 lockfile，都没有退回 npm', () => {
  assert.equal(pickPackageManager({ packageManager: 'pnpm@11.5.0', files: ['package-lock.json'] }), 'pnpm')
  assert.equal(pickPackageManager({ files: ['yarn.lock'] }), 'yarn')
  assert.equal(pickPackageManager({ files: [] }), 'npm')
})

test('行数检查默认扫仓库根，src 之外的超长文件也会被扫到', () => {
  const repo = mkdtempSync(join(tmpdir(), 'line-scan-'))
  try {
    mkdirSync(join(repo, 'src'), { recursive: true })
    mkdirSync(join(repo, 'packages', 'foo'), { recursive: true })
    writeFileSync(join(repo, 'src', 'small.ts'), 'const a = 1\n')
    writeFileSync(join(repo, 'packages', 'foo', 'big.js'), 'x\n'.repeat(401))

    const result = scanLongFiles(repo)
    assert.equal(result.scanned, 2)
    assert.deepEqual(
      result.over.map((item) => item.path),
      ['packages/foo/big.js'],
    )
  } finally {
    rmSync(repo, { recursive: true, force: true })
  }
})

test('体检在 monorepo 里扫描顶层源码目录并报出超长文件', () => {
  const repo = mkdtempSync(join(tmpdir(), 'audit-mono-'))
  try {
    mkdirSync(join(repo, 'src'), { recursive: true })
    mkdirSync(join(repo, 'packages', 'foo'), { recursive: true })
    writeFileSync(join(repo, 'package.json'), '{"name":"mono","private":true}\n')
    writeFileSync(join(repo, 'src', 'small.ts'), 'export const a = 1\n')
    writeFileSync(join(repo, 'packages', 'foo', 'big.js'), 'x\n'.repeat(401))

    const audit = fileURLToPath(new URL('./audit.mjs', import.meta.url))
    const result = spawnSync(process.execPath, [audit, repo], { encoding: 'utf8' })
    assert.equal(result.status, 1)
    assert.match(result.stdout, /扫描顶层源码目录：packages/)
    assert.match(result.stdout, /超长 401\/400 行：packages\/foo\/big\.js/)
    assert.doesNotMatch(result.stdout, /体检中断/)
  } finally {
    rmSync(repo, { recursive: true, force: true })
  }
})

test('体检也扫描仓库根上的源码文件', () => {
  const repo = mkdtempSync(join(tmpdir(), 'audit-rootfile-'))
  try {
    mkdirSync(join(repo, 'src'), { recursive: true })
    writeFileSync(join(repo, 'package.json'), '{"name":"root-file","private":true}\n')
    writeFileSync(join(repo, 'src', 'small.ts'), 'export const a = 1\n')
    writeFileSync(join(repo, 'app.js'), 'x\n'.repeat(401))

    const audit = fileURLToPath(new URL('./audit.mjs', import.meta.url))
    const result = spawnSync(process.execPath, [audit, repo], { encoding: 'utf8' })
    assert.equal(result.status, 1)
    assert.match(result.stdout, /扫描根改用仓库根/)
    assert.match(result.stdout, /超长 401\/400 行：app\.js/)
  } finally {
    rmSync(repo, { recursive: true, force: true })
  }
})

test('行数检查扫到 0 个文件时以非 0 退出，不把空转打印成 OK', () => {
  const repo = mkdtempSync(join(tmpdir(), 'line-empty-'))
  try {
    const script = fileURLToPath(new URL('../assets/scripts/check-long-files.mjs', import.meta.url))
    const result = spawnSync(process.execPath, [script], { cwd: repo, encoding: 'utf8' })
    assert.equal(result.status, 1)
    assert.match(result.stdout, /没有扫描到任何源码文件/)
    assert.doesNotMatch(result.stdout, /OK:/)
  } finally {
    rmSync(repo, { recursive: true, force: true })
  }
})
