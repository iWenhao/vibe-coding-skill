import { defineConfig } from 'vitest/config'
import vue from '@vitejs/plugin-vue'
import { resolve } from 'path'

export default defineConfig({
  plugins: [vue()],
  test: {
    environment: 'jsdom',
    globals: true,
    // include 必须显式列出所有被测目录：默认只扫 src，
    // 工具脚本（scripts/）与前后端共用的纯逻辑（shared/）会被静默漏掉，
    // 表现为「测试全绿但脚本根本没跑过」。单测放被测文件同目录。
    include: [
      'src/**/*.{test,spec}.{js,ts}',
      'scripts/**/*.{test,spec}.ts',
      'shared/**/*.{test,spec}.{js,ts}',
    ],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      include: ['src/**/*.{ts,vue}'],
      exclude: ['src/**/*.d.ts', 'src/**/*.test.ts', 'src/**/*.spec.ts'],
    },
  },
  resolve: {
    alias: {
      '@': resolve(__dirname, 'src'),
    },
  },
})
