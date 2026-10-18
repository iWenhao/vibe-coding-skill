import { describe, expect, it } from 'vitest'
import { mount } from '@vue/test-utils'
import App from './App.vue'

// 冒烟测试的意义不是覆盖率，而是证明「构建链路 + 测试链路」真的通了：
// 新仓库一开始就有一条能跑的测试，比第一周补十个用例更重要。
describe('App', () => {
  it('渲染项目名', () => {
    const wrapper = mount(App)
    expect(wrapper.text()).toContain('{{TITLE}}')
  })
})
