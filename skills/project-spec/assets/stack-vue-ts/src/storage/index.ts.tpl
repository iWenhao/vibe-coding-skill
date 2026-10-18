/**
 * 持久化抽象层——仓库内**唯一**允许触碰底层存储的地方（约定见 AGENTS.md「代码风格」）。
 *
 * 为什么要这层：业务代码直接调 localStorage 会锁死「只能单机、只能浏览器」，
 * 换成远程存储时要改遍全仓；这里把 get/set/remove 收敛成一个接口，
 * 后端不在线时自动回落本地存储，两种部署形态共用一份业务代码。
 *
 * 用法：await initStorage() 后 getStorage().get(key) / .set(key, value) / .remove(key)
 * 约定：value 为字符串（复杂对象由调用方 JSON.stringify，避免这里偷偷决定序列化方式）；
 *       key 用模块级常量集中管理，不要散落字面量。
 */

export interface KeyValueStore {
  get(key: string): Promise<string | null>
  set(key: string, value: string): Promise<void>
  remove(key: string): Promise<void>
}

/** 本地回落实现：同步 API 包成 Promise，保持与远程实现同签名 */
function createLocalStore(namespace = ''): KeyValueStore {
  const wrap = (key: string) => (namespace === '' ? key : `${namespace}:${key}`)
  return {
    async get(key) {
      return localStorage.getItem(wrap(key))
    },
    async set(key, value) {
      localStorage.setItem(wrap(key), value)
    },
    async remove(key) {
      localStorage.removeItem(wrap(key))
    },
  }
}

{{#BACKEND}}
/**
 * 远程实现：走 VITE_API_BASE（默认 /api，由 Vite 代理到存储后端）。
 * 401/网络错误一律抛出，由 initStorage 的探测决定是否回落到本地。
 */
function createRemoteStore(token: string): KeyValueStore {
  const base = (import.meta.env.VITE_API_BASE ?? '/api').replace(/\/$/, '')
  const headers = (): Record<string, string> => ({
    'Content-Type': 'application/json',
    ...(token === '' ? {} : { Authorization: `Bearer ${token}` }),
  })
  return {
    async get(key) {
      const res = await fetch(`${base}/storage/${encodeURIComponent(key)}`, { headers: headers() })
      if (res.status === 404) return null
      if (!res.ok) throw new Error(`storage get ${res.status}`)
      const data = (await res.json()) as { value?: string }
      return data.value ?? null
    },
    async set(key, value) {
      const res = await fetch(`${base}/storage/${encodeURIComponent(key)}`, {
        method: 'PUT',
        headers: headers(),
        body: JSON.stringify({ value }),
      })
      if (!res.ok) throw new Error(`storage set ${res.status}`)
    },
    async remove(key) {
      const res = await fetch(`${base}/storage/${encodeURIComponent(key)}`, {
        method: 'DELETE',
        headers: headers(),
      })
      if (!res.ok && res.status !== 404) throw new Error(`storage remove ${res.status}`)
    },
  }
}

/** 探测后端是否在线：一次轻量请求，失败即视为「无后端」形态 */
async function probeRemote(token: string): Promise<boolean> {
  try {
    const base = (import.meta.env.VITE_API_BASE ?? '/api').replace(/\/$/, '')
    const res = await fetch(`${base}/health`, { headers: { ...(token === '' ? {} : { Authorization: `Bearer ${token}` }) } })
    return res.ok
  } catch {
    return false
  }
}
{{/BACKEND}}

let store: KeyValueStore = createLocalStore()

/** 初始化存储后端{{#BACKEND}}：在线用远程，不在线回落 localStorage{{/BACKEND}} */
export async function initStorage(namespace?: string): Promise<void> {
{{#BACKEND}}
  const token = import.meta.env.VITE_API_TOKEN ?? ''
  if (await probeRemote(token)) {
    store = createRemoteStore(token)
    return
  }
{{/BACKEND}}
  store = createLocalStore(namespace)
}

/** 取当前存储实现。必须在 initStorage() 之后调用，否则拿到的是回落实现 */
export function getStorage(): KeyValueStore {
  return store
}

/** 仅供测试：重置为本地实现，避免用例之间互相污染 */
export function resetStorageForTest(namespace?: string): void {
  store = createLocalStore(namespace)
}
