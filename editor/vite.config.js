import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { fileURLToPath, URL } from 'node:url'

export default defineConfig({
  base: './',
  plugins: [vue()],
  resolve: {
    alias: [
      { find: '@', replacement: fileURLToPath(new URL('./components-nimtech', import.meta.url)) }
    ],
    dedupe: ['vue', '@codemirror/state', '@codemirror/view', '@codemirror/language', '@codemirror/autocomplete', '@codemirror/lint', '@lezer/common', '@lezer/highlight']
  },
  build: { outDir: 'dist', emptyOutDir: true, chunkSizeWarningLimit: 4000 }
})
