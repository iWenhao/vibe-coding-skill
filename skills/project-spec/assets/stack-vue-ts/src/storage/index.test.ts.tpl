import { beforeEach, describe, expect, it, vi } from 'vitest'
import { getStorage, initStorage, resetStorageForTest } from './index'
{{#BACKEND}}
import { ApiRequestError } from '../api/client'
{{/BACKEND}}

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

{{#BACKEND}}
/** 最小假响应：用例只经手 ok / status / json，不去依赖运行环境有没有 Response 构造器 */
function fakeResponse(status: number, body: unknown): Response {
  return { ok: status >= 200 && status < 300, status, json: async () => body } as unknown as Response
}

/**
 * 打桩 fetch：/health 一律 200（让 initStorage 选中远程实现），其余按场景回信封。
 * 这里的形状与 docs/DEPLOY.md 的码表对齐——服务端动形状时这几个用例应当一起红，
 * 而不是让远程实现在没人注意的地方悄悄读到 undefined。
 */
function stubRemoteFetch(scenario: 'ok' | 'key-missing' | 'wrong-base') {
  return vi.fn(async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    if (String(input) === '/api/health') return fakeResponse(200, { data: { name: 'probe', version: '0' } })
    if (scenario === 'wrong-base') {
      return fakeResponse(404, { error: { code: 'ROUTE_NOT_FOUND', message: '未知的接口路径' } })
    }
    if (scenario === 'key-missing') {
      return fakeResponse(404, { error: { code: 'KEY_NOT_FOUND', message: '键不存在' } })
    }
    if (init?.method === 'PUT' || init?.method === 'DELETE') return fakeResponse(200, { data: { key: 'theme' } })
    return fakeResponse(200, { data: { key: 'theme', value: 'dark' } })
  })
}

describe('storage 远程形态', () => {
  beforeEach(() => {
    stubLocalStorage()
    resetStorageForTest()
    vi.unstubAllGlobals()
  })

  it('探测到在线就走远程，路径与请求体都对（请求体不带信封）', async () => {
    const fetchMock = stubRemoteFetch('ok')
    vi.stubGlobal('fetch', fetchMock)
    await initStorage()
    expect(await getStorage().get('theme')).toBe('dark')

    await getStorage().set('theme', 'light')
    const putCall = fetchMock.mock.calls.find(([, init]) => init?.method === 'PUT')
    expect(String(putCall?.[0])).toBe('/api/storage/theme')
    expect(putCall?.[1]?.body).toBe(JSON.stringify({ value: 'light' }))

    await getStorage().remove('theme')
    expect(fetchMock.mock.calls.some(([, init]) => init?.method === 'DELETE')).toBe(true)
  })

  it('远程形态也带命名空间：请求路径与本地键保持同一种 ns:key 语义', async () => {
    const fetchMock = stubRemoteFetch('ok')
    vi.stubGlobal('fetch', fetchMock)
    await initStorage('alice')
    await getStorage().get('theme')

    // encodeURIComponent('alice:theme') = alice%3Atheme
    const dataCall = fetchMock.mock.calls.find(([input]) => String(input) !== '/api/health')
    expect(String(dataCall?.[0])).toBe('/api/storage/alice%3Atheme')
  })

  it('键确实没写过（KEY_NOT_FOUND）读出 null，与本地形态同义', async () => {
    vi.stubGlobal('fetch', stubRemoteFetch('key-missing'))
    await initStorage()
    expect(await getStorage().get('theme')).toBeNull()
  })

  it('路径配错（同为 404 的 ROUTE_NOT_FOUND）必须抛出，不能被读成「没有这个键」', async () => {
    vi.stubGlobal('fetch', stubRemoteFetch('wrong-base'))
    await initStorage()
    const error = await getStorage()
      .get('theme')
      .catch((caught: unknown) => caught)
    // 断言只落在 status 与 code 上，不断言 message——文案可随时改动，不该牵动这里的语义
    expect(error).toBeInstanceOf(ApiRequestError)
    expect((error as ApiRequestError).status).toBe(404)
    expect((error as ApiRequestError).code).toBe('ROUTE_NOT_FOUND')
  })

  it('探测不通就回落本地，除探测外一次都不碰远程', async () => {
    const fetchMock = vi.fn(async () => {
      throw new Error('offline')
    })
    vi.stubGlobal('fetch', fetchMock)
    await initStorage('alice')
    await getStorage().set('theme', 'dark')
    expect(fetchMock).toHaveBeenCalledTimes(1)
    const raw = (globalThis as unknown as { localStorage: Storage }).localStorage
    expect(raw.getItem('alice:theme')).toBe('dark')
  })
})
{{/BACKEND}}
