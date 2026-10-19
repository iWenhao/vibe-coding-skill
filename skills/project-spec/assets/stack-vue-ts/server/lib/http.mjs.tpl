/**
 * 响应信封的唯一出口：所有端点的成功与失败都从这里出去，路由不手拼 body。
 *
 * 形状约定（与前端 src/api/client.ts 一一对应，改任一侧必须同步）：
 *   成功 2xx → { data, meta? }                meta 放分页统计、校验标识这类附带信息，为空则整个键省略
 *   失败     → { error: { code, message, meta? } }   code 供机器比对，message 只给人读
 * 成败的唯一判据是 HTTP 状态码，响应体里不放成功标记。
 *
 * 为什么收成两个函数而不是每个端点自己写：把「装信封」与「判错误」复制进每个端点，
 * 就等于给下一个忘记判的端点预留了 bug——新增端点只需回答「数据是什么 / 抛哪个码」。
 */
import { ApiError, CODES } from './apiError.mjs'

// 允许的跨域来源，逗号分隔；默认 * 仅建议内网使用（含义与生产取值见 .env.example）
const CORS_ORIGIN = process.env.CORS_ORIGIN ?? '*'

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': CORS_ORIGIN,
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Access-Control-Allow-Methods': 'GET, PUT, DELETE, OPTIONS',
}

/**
 * @param {import('node:http').ServerResponse} res
 * @param {number} status
 * @param {object} payload
 */
function sendJson(res, status, payload) {
  const body = JSON.stringify(payload)
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    ...CORS_HEADERS,
  })
  res.end(body)
}

/** 预检请求：204 不能带 body，只回头部 */
export function sendCorsPreflight(res) {
  res.writeHead(204, { ...CORS_HEADERS, 'Access-Control-Max-Age': '600' })
  res.end()
}

/**
 * @param {import('node:http').ServerResponse} res
 * @param {object} data 业务数据，调用方拆信封时取这一层
 * @param {object} [meta] 附带信息；不传则响应体里连 meta 键都不出现
 */
export function sendData(res, data, meta) {
  sendJson(res, 200, meta === undefined ? { data } : { data, meta })
}

/**
 * 失败出口：只认 ApiError，其余一律降级成 500 兜底码。
 * 未预期异常的原始文案只进服务端日志、不回显给客户端——否则路径、堆栈这类内部事实会跟着泄漏。
 * @param {import('node:http').ServerResponse} res
 * @param {unknown} error
 */
export function sendFail(res, error) {
  const known = error instanceof ApiError
  if (!known) console.error('[server] 未预期的异常：', error)
  const detail = {
    code: known ? error.code : CODES.INTERNAL,
    message: known ? error.message : '内部错误',
  }
  if (known && error.meta !== undefined) detail.meta = error.meta
  sendJson(res, known ? error.status : 500, { error: detail })
}
