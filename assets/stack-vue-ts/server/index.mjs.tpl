/**
 * 零依赖存储服务——前端持久化后端（可选，不启动时前端自动回落 localStorage）。
 *
 * 模块职责：只做「命名空间 + 键 → 字符串值」的读写删，不提供业务语义。
 * 依赖约定：**只用 node: 内置模块**，不引入框架——这样 `node server/index.mjs` 在任何
 * 有 Node 的机器上都能起来，部署时不需要构建步骤。
 *
 * 接口约定（与前端 src/storage 的远程实现一一对应，改任一侧必须同步）：
 *   GET    /health                      → { ok, name, version }，前端据此判断是否在线
 *   GET    /api/storage/:key            → { key, value }；不存在返回 404
 *   PUT    /api/storage/:key            → body { value }，写入并返回 { key, ok }
 *   DELETE /api/storage/:key            → 删除；不存在视为成功（幂等）
 *   前端经 Vite 代理访问：浏览器侧路径是 /api/*，所以这里的路由要带 /api 前缀
 *
 * 安全与兼容注意点：
 *   - 默认只监听 127.0.0.1：局域网/公网可达需要显式设 HOST=0.0.0.0；
 *   - AUTH_TOKEN 一旦设置，所有 /api/* 都要求 Bearer 一致（/health 不要求，前端要靠它探测）；
 *   - 键名会被拼进文件路径，必须清洗（见 safeFileName），否则 `../../etc/passwd` 这类键能越出数据目录；
 *   - 请求体有上限，防止一次大上传把内存打满；
 *   - 数据目录里的 *.json 含真实数据，已在 .gitignore 中排除，别提交、别放进公开备份。
 */
import { createServer } from 'node:http'
import { mkdir, readFile, readdir, rename, rm, writeFile } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { join, resolve } from 'node:path'
import { randomUUID } from 'node:crypto'
import { fileURLToPath } from 'node:url'

const HERE = fileURLToPath(new URL('.', import.meta.url))
const PKG = JSON.parse(await readFile(new URL('../package.json', import.meta.url), 'utf8'))

const PORT = Number(process.env.PORT ?? 5174)
const HOST = process.env.HOST ?? '127.0.0.1'
// 数据目录默认 server/data，可用 DATA_DIR 指到持久卷
const DATA_DIR = resolve(process.env.DATA_DIR ?? join(HERE, 'data'))
// 请求体上限（字节），默认 20MB
const MAX_BODY_BYTES = Number(process.env.MAX_BODY_BYTES ?? 20971520)
// 允许的跨域来源，逗号分隔；默认 * 仅建议内网使用
const CORS_ORIGIN = process.env.CORS_ORIGIN ?? '*'
// 可选服务主密钥；设置后 /api/* 需要 Bearer 匹配
const AUTH_TOKEN = process.env.AUTH_TOKEN ?? ''

await mkdir(DATA_DIR, { recursive: true })

/** 把键名压成安全文件名：只留字母数字与 . _ -，其余替换为 _，并限制长度 */
function safeFileName(key) {
  const cleaned = String(key).replace(/[^a-zA-Z0-9._-]/g, '_').slice(0, 120)
  // 纯点号（.. / .）会被拼成父目录，加前缀规避
  return cleaned.replace(/^\.+/, '_') + '.json'
}

/** 统一 JSON 响应：附带 CORS 头，前端与探针脚本都能直接读 */
function sendJson(res, status, payload) {
  const body = JSON.stringify(payload)
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': CORS_ORIGIN,
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Allow-Methods': 'GET, PUT, DELETE, OPTIONS',
    'Content-Length': Buffer.byteLength(body),
  })
  res.end(body)
}

/** 读取并解析请求体，超过上限直接拒绝 */
async function readBody(req) {
  const chunks = []
  let size = 0
  for await (const chunk of req) {
    size += chunk.length
    if (size > MAX_BODY_BYTES) {
      const error = new Error('请求体超过 MAX_BODY_BYTES')
      error.status = 413
      throw error
    }
    chunks.push(chunk)
  }
  if (chunks.length === 0) return {}
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'))
  } catch {
    const error = new Error('请求体不是合法 JSON')
    error.status = 400
    throw error
  }
}

/** 鉴权：未设置 AUTH_TOKEN 时放行（开发形态），设置后要求 Bearer 完全一致 */
function authorized(req) {
  if (AUTH_TOKEN === '') return true
  return req.headers.authorization === `Bearer ${AUTH_TOKEN}`
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url ?? '/', `http://${req.headers.host ?? 'localhost'}`)

  // 预检请求：204 不能带 body，只回头部
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': CORS_ORIGIN,
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      'Access-Control-Allow-Methods': 'GET, PUT, DELETE, OPTIONS',
      'Access-Control-Max-Age': '600',
    })
    return res.end()
  }
  if (url.pathname === '/health') {
    return sendJson(res, 200, { ok: true, name: PKG.name, version: PKG.version })
  }

  const match = url.pathname.match(/^\/api\/storage\/([^/]+)$/)
  if (match === null) return sendJson(res, 404, { error: '未知的接口路径' })
  if (!authorized(req)) return sendJson(res, 401, { error: '未授权' })

  // 键名先解码再清洗：URL 里是 encodeURIComponent 过的
  const key = decodeURIComponent(match[1])
  const file = join(DATA_DIR, safeFileName(key))

  try {
    if (req.method === 'GET') {
      if (!existsSync(file)) return sendJson(res, 404, { key, error: '键不存在' })
      const text = await readFile(file, 'utf8')
      return sendJson(res, 200, { key, value: JSON.parse(text).value ?? null })
    }

    if (req.method === 'PUT') {
      const { value } = await readBody(req)
      if (typeof value !== 'string') return sendJson(res, 400, { error: 'value 必须是字符串' })
      // 先写临时文件再改名：进程中途被杀不会留下半个 JSON
      const tmp = `${file}.${randomUUID()}.tmp`
      await writeFile(tmp, JSON.stringify({ key, value, updatedAt: new Date().toISOString() }), 'utf8')
      await rename(tmp, file)
      return sendJson(res, 200, { key, ok: true })
    }

    if (req.method === 'DELETE') {
      await rm(file, { force: true }) // force：不存在也不报错，保持幂等
      return sendJson(res, 200, { key, ok: true })
    }

    return sendJson(res, 405, { error: '方法不允许' })
  } catch (error) {
    return sendJson(res, error.status ?? 500, { error: error.message ?? '内部错误' })
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
