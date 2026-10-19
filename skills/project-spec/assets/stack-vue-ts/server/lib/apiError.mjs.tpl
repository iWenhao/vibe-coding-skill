/**
 * 失败的唯一表达方式：异常对象同时带 HTTP 状态码与供机器比对的错误码。
 *
 * 为什么语义挂在码上而不是文案上：调用方比对的是 code，message 只给人读。
 * 若拿文案做分支，改一句中文提示就能把「重试」变成「直接失败」，而测试里看不出来——没人给文案写断言。
 * meta 是可选附带信息，只在「光靠码说不清」时带（如 405 带上允许的方法），调用方不拿它做判据。
 */
export class ApiError extends Error {
  /**
   * @param {number} status HTTP 状态码，即成败的唯一判据
   * @param {string} code 见 CODES，对外契约的一部分
   * @param {string} message 给人读的文案，可随时改动
   * @param {unknown} [meta] 该错误的附带细节
   */
  constructor(status, code, message, meta) {
    super(message)
    this.name = 'ApiError'
    /** @type {number} */
    this.status = status
    /** @type {string} */
    this.code = code
    /** @type {unknown} */
    this.meta = meta
  }
}

/**
 * 码表单一来源：新增码先在这里加常量，再到 docs/DEPLOY.md「接口错误码」补一行。
 * 码值一旦发布就是对外契约——只能新增，不要重命名或复用旧码改语义（调用方按码分支）。
 */
export const CODES = {
  /** 路径不属于本服务：base 配错、代理指到别处时会命中这个码 */
  ROUTE_NOT_FOUND: 'ROUTE_NOT_FOUND',
  /** 路径认得、键确实没写过：与 ROUTE_NOT_FOUND 分开，客户端才能分辨「没有数据」和「配错了」 */
  KEY_NOT_FOUND: 'KEY_NOT_FOUND',
  UNAUTHORIZED: 'UNAUTHORIZED',
  METHOD_NOT_ALLOWED: 'METHOD_NOT_ALLOWED',
  MALFORMED_JSON: 'MALFORMED_JSON',
  INVALID_VALUE: 'INVALID_VALUE',
  BODY_TOO_LARGE: 'BODY_TOO_LARGE',
  /** 未预期异常的兜底码，同时是唯一允许不回显原始文案的情形 */
  INTERNAL: 'INTERNAL',
}
