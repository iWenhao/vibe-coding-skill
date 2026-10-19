import { describe, expect, it } from 'vitest'
import {
  LINE_CHECK_FALLBACK,
  ZERO_OID,
  decidePush,
  parseRefLines,
  pickPackageManager,
  planSteps,
} from './pre-push-check.mjs'

// 与 pre-push-check.mjs 同目录：这道钩子是「推送前唯一会跑全量」的地方，
// 判错一次要么白等几分钟，要么把没过检查的代码推出去——两种都比少一个用例贵得多。

const ref = (localRef = 'refs/heads/main', localOid = 'a'.repeat(40), remoteOid = 'b'.repeat(40)) => ({
  localRef,
  localOid,
  remoteRef: localRef,
  remoteOid,
})

describe('parseRefLines', () => {
  it('解析 git 的四字段清单并忽略空行', () => {
    const refs = parseRefLines(`${ref().localRef} ${ref().localOid} refs/heads/main ${ZERO_OID}\n\n`)
    expect(refs).toHaveLength(1)
    expect(refs?.[0].remoteRef).toBe('refs/heads/main')
  })

  it('字段不齐返回 null，空清单是「没推引用」不是「读不到」', () => {
    expect(parseRefLines('refs/heads/main')).toBeNull()
    expect(parseRefLines('')).toEqual([])
  })
})

describe('decidePush', () => {
  it('拿不到清单时不跳过：解析失败不能变成静默放行', () => {
    expect(decidePush(null).skip).toBe(false)
  })

  it('只推 tag、只删引用、空清单三种没有新代码的情况都跳过', () => {
    expect(decidePush([]).skip).toBe(true)
    expect(decidePush([ref('refs/tags/v1.2.0')]).skip).toBe(true)
    // git 用「本地 oid 全 0」表示删除远端引用，这次推送不引入任何新代码
    expect(decidePush([ref('refs/heads/old', ZERO_OID)]).skip).toBe(true)
  })

  it('新建分支要跑：远端 oid 全 0 是「对端还没有这个引用」，不是删除', () => {
    expect(decidePush([ref('refs/heads/new', 'a'.repeat(40), ZERO_OID)]).skip).toBe(false)
  })

  it('分支推送要跑，且报告里说清推的是哪条', () => {
    const decision = decidePush([ref()])
    expect(decision.skip).toBe(false)
    expect(decision.checked.join()).toContain('refs/heads/main')
  })

  it('只推 tag 时把 tag 名列出来，免得看着像漏跑', () => {
    expect(decidePush([ref('refs/tags/v1.2.0')]).reason).toContain('v1.2.0')
  })
})

describe('pickPackageManager', () => {
  it('packageManager 字段优先于 lockfile', () => {
    expect(pickPackageManager({ packageManager: 'pnpm@11.5.0', files: ['package-lock.json'] })).toBe('pnpm')
  })

  it('没声明时按 lockfile 判，都没有才退回 npm', () => {
    expect(pickPackageManager({ files: ['yarn.lock'] })).toBe('yarn')
    expect(pickPackageManager({ files: [] })).toBe('npm')
  })
})

describe('planSteps', () => {
  const base = { pm: 'pnpm', hasVitest: false, packageScripts: {}, hasLineChecker: false }

  it('没有 package.json 也没有行数检查脚本时返回空清单——清单外的步骤绝不假装跑过', () => {
    expect(planSteps(base)).toEqual([])
  })

  it('按存在的能力逐步加，全量测试用 npx vitest run 而不是 watch 模式的 pnpm test', () => {
    const steps = planSteps({
      ...base,
      hasVitest: true,
      packageScripts: { build: 'vue-tsc --noEmit && vite build', test: 'vitest' },
      hasLineChecker: true,
    })
    expect(steps.map((step) => step.name)).toEqual(['全量测试', '构建（含 vue-tsc 类型检查）', '行数检查'])
    expect(steps[0].args).toEqual(['vitest', 'run'])
  })

  it('有 check:lines 走项目脚本，没有则用兜底命令', () => {
    expect(planSteps({ ...base, hasLineChecker: true })[0].args).toEqual(LINE_CHECK_FALLBACK.slice(1))
    expect(planSteps({ ...base, hasLineChecker: true, packageScripts: { 'check:lines': 'x' } })[0].cmd).toBe('pnpm')
  })

  it('服务端类型检查单独一步：build 里的 vue-tsc 不覆盖 server/**', () => {
    expect(planSteps({ ...base, packageScripts: { 'typecheck:server': 'tsc -p tsconfig.server.json' } })).toHaveLength(1)
  })
})
