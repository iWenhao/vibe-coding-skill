{
  "name": "{{NAME}}",
  "version": "0.0.1",
  "type": "module",
  "description": "{{DESC}}",
  "scripts": {
    "dev": "vite",
    "build": "vue-tsc --noEmit && vite build",
    "preview": "vite preview",
    "lint": "eslint src{{#BACKEND}} server scripts{{/BACKEND}}{{^BACKEND}} scripts{{/BACKEND}}",
    "test": "vitest",
    "test:coverage": "vitest --coverage",
    "check:lines": "node scripts/check-long-files.mjs --roots src{{#BACKEND}},server{{/BACKEND}}"{{#BACKEND}},
    "server": "node server/index.mjs",
    "typecheck:server": "tsc -p tsconfig.server.json"{{/BACKEND}}
  },
  "dependencies": {
    "@element-plus/icons-vue": "^2.3.0",
    "@vueuse/core": "^10.0.0",
    "element-plus": "^2.7.0",
    "pinia": "^2.1.0",
    "vue": "^3.4.0",
    "vue-router": "^4.3.0"
  },
  "devDependencies": {
    "@eslint/js": "^9.39.5",
    "@types/node": "^24.19.2",
    "@vitejs/plugin-vue": "^5.0.0",
    "@vue/test-utils": "^2.4.0",
    "eslint": "^9.39.5",
    "eslint-plugin-vue": "^9.33.0",
    "globals": "^17.12.0",
    "jsdom": "^23.0.0",
    "sass": "^1.100.0",
    "typescript": "^5.4.0",
    "typescript-eslint": "^8.70.1",
    "unplugin-auto-import": "^0.17.0",
    "unplugin-vue-components": "^0.27.0",
    "vite": "^5.4.0",
    "vitest": "^1.0.0",
    "vue-tsc": "^2.2.12"
  }
}
