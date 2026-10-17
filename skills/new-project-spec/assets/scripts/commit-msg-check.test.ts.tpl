import { describe, expect, it } from 'vitest'
import { MAX_SUBJECT_LENGTH, PREFIXES, checkCommitMessage } from './commit-msg-check.mjs'

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
