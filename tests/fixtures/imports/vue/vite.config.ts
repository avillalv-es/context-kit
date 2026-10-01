import { fileURLToPath, URL } from 'node:url'
import path from 'node:path'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

const apiDir = path.resolve(__dirname, 'src/api')

// https://vite.dev/config/
export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
      // The next two exist ONLY here. No tsconfig declares them, so an import
      // through either resolves through this file or not at all.
      '~lib': path.resolve(__dirname, 'src/lib'),
      '~': '/src',
      // Not literals, so there is nothing to read and nothing is guessed.
      '@api': apiDir,
      vue: 'vue/dist/vue.esm-bundler.js',
      // '@legacy': path.resolve(__dirname, 'src/old'),
    },
  },
})
