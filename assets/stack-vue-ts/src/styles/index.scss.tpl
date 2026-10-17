/* 全局样式入口。
 *
 * 主题分两层，职责不同，**不要合并**（清理样式时最容易把下面这层当「重复」删掉）：
 *   1) 组件库变量兜底层：element-plus/theme-chalk/dark/css-vars.css + html.dark 类，
 *      在 main.ts 引入，负责第三方组件在暗色下不出现白底白字；
 *   2) 品牌调色层：本文件里的 CSS 变量，同样限定在 html.dark 作用域，
 *      只覆盖本项目想要的品牌色，不去改组件库的变量语义。
 */

:root {
  --app-bg: #f5f7fa;
  --app-fg: #1f2933;
  --app-accent: #0ea5a4;
  --app-border: #d0d7de;
}

html.dark {
  /* 品牌调色层：只在这里改颜色，别散落到各个组件里写死 */
  --app-bg: #0b1220;
  --app-fg: #e6edf3;
  --app-accent: #22d3ee;
  --app-border: #1f2b3d;
}

body {
  background: var(--app-bg);
  color: var(--app-fg);
  font-family: system-ui, -apple-system, 'Segoe UI', 'Microsoft YaHei', sans-serif;
}

.scaffold-home {
  padding: 2rem;
}
