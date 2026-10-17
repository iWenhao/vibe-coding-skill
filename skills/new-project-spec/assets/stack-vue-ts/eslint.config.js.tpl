import js from '@eslint/js'
import pluginVue from 'eslint-plugin-vue'
import tseslint from 'typescript-eslint'
import globals from 'globals'

/**
 * ESLint flat config（v9+）。
 *
 * 结构说明：.ts/.mjs 与 .vue **必须拆成两个块**——
 * 前者的 languageOptions.parser 是 TS parser，会覆盖 flat/recommended
 * 为 .vue 注入的 vue-eslint-parser，导致模板解析失败。
 *
 * 日常只对**改动文件**跑 lint：全量会被仓库既有报警（缩进、属性换行之类）淹没，
 * 真正的信号反而看不见。理由见 AGENTS.md「验证节奏」。
 */
const sharedRules = {
  // 第三方库的事件/画布对象逐个声明类型收益不大
  '@typescript-eslint/no-explicit-any': 'off',
  // TS 已由 vue-tsc 检查未定义标识符；ESLint 的 no-undef 不认识类型（如 RequestInit）会误报
  'no-undef': 'off',
  // 单测中有意构造非法输入来覆盖异常分支；_ 前缀参数视为刻意不用
  '@typescript-eslint/no-unused-vars': ['warn', { argsIgnorePattern: '^_' }],
  'vue/multi-word-component-names': 'off',
  'vue/max-attributes-per-line': 'off',
  'vue/singleline-html-element-content-newline': 'off',
}

const sharedLanguageOptions = {
  ecmaVersion: 2022,
  sourceType: 'module',
  globals: {
    ...globals.browser,
    ...globals.node,
  },
}

export default tseslint.config(
  {
    ignores: ['dist/**', 'node_modules/**'{{#BACKEND}}, 'server/data/**'{{/BACKEND}}, '*.d.ts'],
  },
  js.configs.recommended,
  ...pluginVue.configs['flat/recommended'],
  {
    files: ['**/*.{ts,mjs}'],
    plugins: {
      '@typescript-eslint': tseslint.plugin,
    },
    languageOptions: {
      parser: tseslint.parser,
      ...sharedLanguageOptions,
    },
    rules: {
      // 基础规则对 TS 语法（接口参数、类型导入）误报，统一交给 TS 感知版本
      'no-unused-vars': 'off',
      ...sharedRules,
    },
  },
  {
    files: ['**/*.vue'],
    plugins: {
      '@typescript-eslint': tseslint.plugin,
    },
    languageOptions: {
      // parser 保留 flat/recommended 注入的 vue-eslint-parser，
      // 仅指定 <script> 内容用 TS 解析
      parserOptions: {
        parser: tseslint.parser,
      },
      ...sharedLanguageOptions,
    },
    rules: {
      'no-unused-vars': 'off',
      ...sharedRules,
    },
  },
  {
    files: ['**/*.test.ts', 'src/__tests__/**'],
    languageOptions: {
      globals: { ...globals.browser, ...globals.node, vi: 'readonly' },
    },
  },
)
