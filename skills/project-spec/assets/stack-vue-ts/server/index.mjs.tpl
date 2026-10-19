/**
 * 零依赖存储服务——前端持久化后端（可选，不启动时前端自动回落 localStorage）。
 *
 * 模块职责：只做「命名空间 + 键 → 字符串值」的读写删，不提供业务语义。
 * 依赖约定：**只用 node: 内置模块与本目录 lib/**，不引入框架**——这样 `node server/index.mjs` 在任何
 * 有 Node 的机器上都能起来，部署时不需要构建步骤。
 *
 * 响应形状不在本文件里拼：成功走 lib/http.mjs 的 sendData，失败只抛 lib/apiError.mjs 的 ApiError，
 * 由 createServer 最外层捕获后统一翻译（约定与理由见 AGENTS.md「代码风格」，码表见 docs/DEPLOY.md）。
 *   成功 2xx → { data, meta? }；失败 → { error: { code, message, meta? } }；判据只有 HTTP 状态码。
 *
 * 接口清单（与前端 src/api/client.ts + src/storage 一一对应，改任一侧必须同步）：
 *   GET  /health 与 /api/health   → data { name, version }，前端只看状态码判断是否在线
 *     两个路径都要认：Vite 代理**不做 rewrite**，浏览器侧 base 是 /api，探测打出去就是 /api/health；
 *     而部署探针直连后端时打的是裸 /health。只留一个路径，另一种场景就静默 404——
 *     而探测失败的表征是「回落本地存储」，看起来像后端没启动，配错了也很难看出来。
 *   GET    /api/storage/:key      → data { key, value }；键没写过 → 404 KEY_NOT_FOUND
 *   PUT    /api/storage/:key      → body { value }，写入并回显 data { key }
 *   DELETE /api/storage/:key      → 删除并回显 data { key }；不存在视为成功（幂等）
 *   其它 /api/* 路径              → 404 ROUTE_NOT_FOUND（刻意与 KEY_NOT_FOUND 分开，见码表）
 *
 * 安全与兼容注意点（只写代码层面的不变量；配置项与默认值一律看 .env.example，不在此重复）：
 *   - /health 不鉴权，其余 /api/* 在设置了 AUTH_TOKEN 后要求 Bearer 一致——前端正是靠 /health 判断在线；
 *   - 键名会被拼进文件路径，必须清洗（见 safeFileName），否则 `../../etc/passwd` 这类键能越出数据目录；
 *   - 数据目录里的 *.json 是应用写入的真实数据，已在 .gitignore 中排除，别提交、别放进公开备份。
 */
import { createServer } from 'node:http'
import { mkdir, readFile, readdir, rename, rm, writeFile } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { join, resolve } from 'node:path'
import { randomUUID } from 'node:crypto'
import { fileURLToPath } from 'node:url'
import { ApiError, CODES } from './lib/apiError.mjs'
import { sendCorsPreflight, sendData, sendFail } from './lib/http.mjs'

const HERE = fileURLToPath(new URL('.', import.meta.url))
const PKG = JSON.parse(await readFile(new URL('../package.json', import.meta.url), 'utf8'))

const PORT = Number(process.env.PORT ?? 5174)
const HOST = process.env.HOST ?? '127.0.0.1'
// 数据目录默认 server/data，可用 DATA_DIR 指到持久卷
const DATA_DIR = resolve(process.env.DATA_DIR ?? join(HERE, 'data'))
// 请求体上限（字节），默认 20MB
const MAX_BODY_BYTES = Number(process.env.MAX_BODY_BYTES ?? 20971520)
// 可选服务主密钥；设置后 /api/* 需要 Bearer 匹配
const AUTH_TOKEN = process.env.AUTH_TOKEN ?? ''

await mkdir(DATA_DIR, { recursive: true })

/** 把键名压成安全文件名：只留字母数字与 . _ -，其余替换为 _，并限制长度 */
function safeFileName(key) {
  const cleaned = String(key).replace(/[^a-zA-Z0-9._-]/g, '_').slice(0, 120)
  // 纯点号（.. / .）会被拼成父目录，加前缀规避
  return cleaned.replace(/^\.+/, '_') + '.json'
}

/** 读取并解析请求体，超过上限直接拒绝 */
async function readBody(req) {
  const chunks = []
  let size = 0
  for await (const chunk of req) {
    size += chunk.length
    if (size > MAX_BODY_BYTES) throw new ApiError(413, CODES.BODY_TOO_LARGE, '请求体超过 MAX_BODY_BYTES')
    chunks.push(chunk)
  }
  if (chunks.length === 0) return {}
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'))
  } catch {
    throw new ApiError(400, CODES.MALFORMED_JSON, '请求体不是合法 JSON')
  }
}

/** 鉴权：未设置 AUTH_TOKEN 时放行（开发形态），设置后要求 Bearer 完全一致 */
function authorized(req) {
  if (AUTH_TOKEN === '') return true
  return req.headers.authorization === `Bearer ${AUTH_TOKEN}`
}

/**
 * 路由本体：只回答「数据是什么 / 抛哪个码」，不碰响应写法。
 * 新增端点时照 GET 那一段抄：取数→sendData，失败→throw ApiError。
 * @param {import('node:http').IncomingMessage} req
 * @param {import('node:http').ServerResponse} res
 * @param {URL} url
 */
async function handle(req, res, url) {
  if (url.pathname === '/health' || url.pathname === '/api/health') {
    return sendData(res, { name: PKG.name, version: PKG.version })
  }

  const match = url.pathname.match(/^\/api\/storage\/([^/]+)$/)
  if (match === null) throw new ApiError(404, CODES.ROUTE_NOT_FOUND, '未知的接口路径')
  if (!authorized(req)) throw new ApiError(401, CODES.UNAUTHORIZED, '未授权')

  // 键名先解码再清洗：URL 里是 encodeURIComponent 过的
  const key = decodeURIComponent(match[1])
  const file = join(DATA_DIR, safeFileName(key))

  if (req.method === 'GET') {
    if (!existsSync(file)) throw new ApiError(404, CODES.KEY_NOT_FOUND, '键不存在')
    const text = await readFile(file, 'utf8')
    return sendData(res, { key, value: JSON.parse(text).value ?? null })
  }

  if (req.method === 'PUT') {
    const { value } = await readBody(req)
    if (typeof value !== 'string') throw new ApiError(400, CODES.INVALID_VALUE, 'value 必须是字符串')
    // 先写临时文件再改名：进程中途被杀不会留下半个 JSON
    const tmp = `${file}.${randomUUID()}.tmp`
    await writeFile(tmp, JSON.stringify({ key, value, updatedAt: new Date().toISOString() }), 'utf8')
    await rename(tmp, file)
    return sendData(res, { key })
  }

  if (req.method === 'DELETE') {
    await rm(file, { force: true }) // force：不存在也不报错，保持幂等
    return sendData(res, { key })
  }

  throw new ApiError(405, CODES.METHOD_NOT_ALLOWED, '方法不允许', { allowed: ['GET', 'PUT', 'DELETE'] })
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url ?? '/', `http://${req.headers.host ?? 'localhost'}`)
  if (req.method === 'OPTIONS') return sendCorsPreflight(res)
  try {
    await handle(req, res, url)
  } catch (error) {
    // 失败的唯一出口：路由里不再各自判返回值，也不会出现「忘了判」的那一个
    sendFail(res, error)
  }
})

server.listen(PORT, HOST, () => {
  // 启动横幅刻意简单：这个进程常被放后台，多行装饰反而看不清端口
  console.log(`${PKG.name} 存储后端已启动 → http://${HOST}:${PORT}`)
  console.log(`  数据目录 ${DATA_DIR}`)
  console.log(`  鉴权 ${AUTH_TOKEN === '' ? '未设置 AUTH_TOKEN（开发形态，任意请求放行）' : 'Bearer 已启用'}`)
  readdir(DATA_DIR)
    .then((list) => {
      if (list.length === 0) console.log('  当前为空库，等待前端首次写入')
      else console.log(`  已有 ${list.length} 个键`)
    })
    .catch(() => {})
})
