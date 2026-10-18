import { beforeEach, describe, expect, it, vi } from 'vitest'
import { getStorage, initStorage, resetStorageForTest } from './index'

// localStorage 在 jsdom 里存在，但用例之间会互相留痕，所以换成显式的 Map 实现打桩
function stubLocalStorage() {
  const map = new Map<string, string>()
  vi.stubGlobal('localStorage', {
    getItem: (key: string) => map.get(key) ?? null,
    setItem: (key: string, value: string) => {
      map.set(key, value)
    },
    removeItem: (key: string) => {
      map.delete(key)
    },
  })
  return map
}

describe('storage 抽象层', () => {
  beforeEach(() => {
    stubLocalStorage()
    resetStorageForTest()
  })

  it('读写删除走同一条路径', async () => {
    await initStorage()
    const store = getStorage()
    await store.set('theme', 'dark')
    expect(await store.get('theme')).toBe('dark')
    await store.remove('theme')
    expect(await store.get('theme')).toBeNull()
  })

  it('命名空间隔离多个用户/项目的数据', async () => {
    await initStorage('alice')
    await getStorage().set('theme', 'light')
    const raw = (globalThis as unknown as { localStorage: Storage }).localStorage
    expect(raw.getItem('alice:theme')).toBe('light')
  })
})
