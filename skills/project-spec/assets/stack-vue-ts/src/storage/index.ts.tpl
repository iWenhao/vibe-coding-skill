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
{{#BACKEND}}
 * 远程取数一律经 src/api/client，本文件不直接调 fetch；唯一的例外是「后端在不在」的探测，
 * 它只读状态码——理由与例外条款写在 client.ts 头注释里。
{{/BACKEND}}
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
import { ApiRequestError, apiData, apiFetch, CODE_KEY_NOT_FOUND } from '../api/client'

/**
 * 远程实现：base、凭据、拆信封全在 src/api/client，这里只回答「这个键、这个动作」。
 */
function createRemoteStore(): KeyValueStore {
  const path = (key: string) => `/storage/${encodeURIComponent(key)}`
  return {
    async get(key) {
      try {
        const data = await apiData<{ key: string; value: string | null }>(path(key))
        return data.value ?? null
      } catch (error) {
        // 分支只看码。同为 404 的 ROUTE_NOT_FOUND（base 配错、代理指到别处）必须抛出去——
        // 若照状态码一并当成「没有值」，配置错误会被静默读成「这个键还没写过」，
        // 症状是一屏空数据而不报错，比崩掉难查一个量级（码表见 docs/DEPLOY.md）
        if (error instanceof ApiRequestError && error.code === CODE_KEY_NOT_FOUND) return null
        throw error
      }
    },
    async set(key, value) {
      await apiData<{ key: string }>(path(key), { method: 'PUT', body: JSON.stringify({ value }) })
    },
    async remove(key) {
      // 服务端删除是幂等的（不存在也回 200），所以这里不需要为 404 开洞
      await apiData<{ key: string }>(path(key), { method: 'DELETE' })
    },
  }
}

/**
 * 探测后端是否在线：刻意只看状态码——「对方在不在」用不到、也不该依赖信封。
 * 仍复用 apiFetch，是为了让 base 拼装与凭据注入只有一处。
 */
async function probeRemote(): Promise<boolean> {
  try {
    return (await apiFetch('/health')).ok
  } catch {
    return false
  }
}
{{/BACKEND}}

let store: KeyValueStore = createLocalStore()

/** 初始化存储后端{{#BACKEND}}：在线用远程，不在线回落 localStorage{{/BACKEND}} */
export async function initStorage(namespace?: string): Promise<void> {
{{#BACKEND}}
  if (await probeRemote()) {
    store = createRemoteStore()
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
