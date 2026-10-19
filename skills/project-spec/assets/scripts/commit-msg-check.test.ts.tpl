import { describe, expect, it } from 'vitest'
import { MAX_SUBJECT_LENGTH, PREFIXES, checkCommitMessage, checkDocSync } from './commit-msg-check.mjs'

// 工具脚本也要有同目录测试——这条规则本身就是 AGENTS.md 的约定之一。
// 校验器是最不该「改了没人测」的代码：它错了，全仓库的提交历史就跟着错。
describe('checkCommitMessage', () => {
  it('接受合规的中文标题', () => {
    const result = checkCommitMessage('修复: 亮色主题下画布背景仍是黑色\n')
    expect(result.ok).toBe(true)
    // 17 = 2 汉字 + 「: 」+ 13 汉字，按码点计；同一条按 UTF-8 字节算是 47
    expect(result.length).toBe(17)
  })

  it('按字符而不是按字节计长度', () => {
    // 30 个汉字的标题：按字节算约 90，会误判成超限
    const long = `功能: ${'测'.repeat(MAX_SUBJECT_LENGTH)}`
    expect([...long].length).toBeGreaterThan(MAX_SUBJECT_LENGTH)
    expect(checkCommitMessage(long).ok).toBe(false)
  })

  it('拒绝未知前缀并列出可用前缀', () => {
    const result = checkCommitMessage('新增: 一个按钮')
    expect(result.ok).toBe(false)
    expect(result.errors[0]).toContain(PREFIXES[0])
  })

  it('放行 Git 自动生成的提交信息', () => {
    expect(checkCommitMessage('Merge branch "dev" into master').exempt).toBe(true)
    expect(checkCommitMessage('Revert "功能: 某件事"').exempt).toBe(true)
  })

  it('正文只提示不阻断', () => {
    const result = checkCommitMessage('文档: 补部署说明\n\n第二段\n第三段')
    expect(result.ok).toBe(true)
    expect(result.warnings.length).toBe(1)
  })

  it('剔除注释行后再取标题', () => {
    const result = checkCommitMessage('# 请写提交信息\n\n优化: 工具栏基线对齐\n')
    expect(result.ok).toBe(true)
    expect(result.subject).toBe('优化: 工具栏基线对齐')
  })

  it('空标题判为不合规', () => {
    expect(checkCommitMessage('\n\n  \n').ok).toBe(false)
  })
})

describe('checkDocSync', () => {
  it('非重要文件改动不拦', () => {
    const result = checkDocSync(['src/main.ts', 'docs/USER_GUIDE.md'], '优化: 调整入口逻辑')
    expect(result.blocked).toBe(false)
    expect(result.notices).toHaveLength(0)
  })

  it('重要文件改动而 README 未同步时拒绝，并列出命中文件与豁免出口', () => {
    const result = checkDocSync(['src/main.ts', 'package.json'], '优化: 调整构建脚本')
    expect(result.blocked).toBe(true)
    expect(result.reason).toContain('package.json')
    expect(result.reason).toContain('[skip-docs]')
  })

  it('README.md 一并暂存即通过', () => {
    expect(checkDocSync(['package.json', 'README.md'], '优化: 调整构建脚本').blocked).toBe(false)
  })

  it('正文含豁免标记时放行并给出可见提示', () => {
    const result = checkDocSync(['package.json'], '优化: 调整构建脚本\n\n[skip-docs]')
    expect(result.blocked).toBe(false)
    expect(result.notices[0]).toContain('[skip-docs]')
  })

  it('根目录配置文件按正则命中，嵌套路径不误伤', () => {
    expect(checkDocSync(['vite.config.ts'], '优化: 换构建配置').blocked).toBe(true)
    expect(checkDocSync(['src/inner.config.ts'], '优化: 内部配置').blocked).toBe(false)
    // monorepo 的子包 package.json 默认不在规则内，需要时自行往 DOC_SYNC_RULES 加条目
    expect(checkDocSync(['packages/app/package.json'], '优化: 子包依赖').blocked).toBe(false)
  })

  it('服务端与前端请求入口改动要求同步接口文档', () => {
    for (const file of ['server/index.mjs', 'src/api/client.ts']) {
      const result = checkDocSync([file], '功能: 加一个端点')
      expect(result.blocked).toBe(true)
      expect(result.reason).toContain('docs/DEPLOY.md')
      expect(result.reason).toContain(file)
    }
  })

  it('规则之间互不豁免：只补 README 不能放行改了服务端却没同步码表的提交', () => {
    const result = checkDocSync(['server/index.mjs', 'README.md'], '功能: 加一个端点')
    expect(result.blocked).toBe(true)
    expect(result.reason).toContain('docs/DEPLOY.md')
  })

  it('两条规则同时缺同步时一起报出各自的文档', () => {
    const result = checkDocSync(['package.json', 'server/index.mjs'], '功能: 加端点并换构建脚本')
    expect(result.blocked).toBe(true)
    expect(result.reason).toContain('README.md')
    expect(result.reason).toContain('docs/DEPLOY.md')
  })

  it('命中规则的文档已同步时通过', () => {
    expect(
      checkDocSync(['server/index.mjs', 'docs/DEPLOY.md'], '功能: 加一个端点').blocked,
    ).toBe(false)
  })

  it('取不到暂存区清单时降级为提示而不是拦死', () => {
    const result = checkDocSync(null, '优化: 调整构建脚本')
    expect(result.blocked).toBe(false)
    expect(result.notices).toHaveLength(1)
  })
})
