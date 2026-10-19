/**
 * 前端请求的唯一入口：拼 base、带凭据、拆信封、把非 2xx 抛成 ApiRequestError。
 *
 * 为什么收成一处：响应信封只在这里拆，服务端的形状改动才有唯一的落点。
 * 业务代码各自调底层 fetch 就会各拆各的信封，第三次复制必然出现（见 AGENTS.md「防重复」），
 * 而形状一改要翻遍全仓才找得到那些散落的拆包点。
 *
 * 约定：成功 2xx 是 `data` + 可选 `meta`，失败是 `error` 里的 code + message；
 * 成败只按 HTTP 状态码判，**调用方比对 code，绝不比对 message**。
 * 不适用本文件的两个例外：**只看服务存活与否的探测**（只读状态码，不该被信封约束）、
 * **对接第三方数据源的适配器**（响应形状由对方定义，我们的信封管不到它）。
 * 例外要连着写清「为什么是例外」，否则后来人会把它们读成「可以各开一套」的授权。
 */

/** 响应体不合约定、拿不到 code 时的本地兜底码——它不在服务端码表里，别拿它做服务端语义的分支 */
const CODE_MISSING = 'CODE_MISSING'

/** 键确实没写过。码值来自 docs/DEPLOY.md「接口错误码」，新增分支先回那张表确认码存在 */
export const CODE_KEY_NOT_FOUND = 'KEY_NOT_FOUND'

export class ApiRequestError extends Error {
  /**
   * @param status HTTP 状态码，即成败判据
   * @param code 服务端错误码（拿不到时为 CODE_MISSING）
   * @param message 服务端给人读的文案，**不要对它做分支**
   */
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message)
    this.name = 'ApiRequestError'
  }
}

const BASE = (import.meta.env.VITE_API_BASE ?? '/api').replace(/\/$/, '')
const TOKEN = import.meta.env.VITE_API_TOKEN ?? ''

/**
 * 发一次带凭据的请求，原样交出 Response——需要读状态码或响应头时用它，不要去猜信封。
 * @param path 以 / 开头、不含 base 前缀的路径，例如 `/storage/` + encodeURIComponent(key)
 */
export function apiFetch(path: string, init?: RequestInit): Promise<Response> {
  return fetch(`${BASE}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(TOKEN === '' ? {} : { Authorization: `Bearer ${TOKEN}` }),
      ...init?.headers,
    },
  })
}

/**
 * 请求并取回成功信封里的 data；非 2xx 一律抛 ApiRequestError（带上服务端的 code）。
 * 需要 meta 时改用 apiFetch 自己读：现有端点都不产 meta，别提前给业务代码留拆信封的口子。
 */
export async function apiData<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await apiFetch(path, init)
  if (!res.ok) throw await toRequestError(res)
  const body = (await res.json()) as { data: T }
  return body.data
}

/** 失败文案仍带回 message 供人看，但分支所需的语义只取自 code */
async function toRequestError(res: Response): Promise<ApiRequestError> {
  try {
    const body = (await res.json()) as { error?: { code?: string; message?: string } }
    const code = body.error?.code
    if (typeof code !== 'string') return new ApiRequestError(res.status, CODE_MISSING, res.statusText)
    return new ApiRequestError(res.status, code, body.error?.message ?? res.statusText)
  } catch {
    return new ApiRequestError(res.status, CODE_MISSING, res.statusText)
  }
}
