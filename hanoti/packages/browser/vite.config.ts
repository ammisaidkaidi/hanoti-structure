import { defineConfig, loadEnv } from 'vite';
import vue from '@vitejs/plugin-vue';
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  return {
    plugins: [vue()],
    server: {
      host: '0.0.0.0',
      port: 5173,
      strictPort: true,
      // Trusted hosted-preview suffix; never use allowedHosts: true.
      allowedHosts: ['.e2b.app'],
      proxy: {
        '/api': { target: env.API_PROXY_TARGET || 'http://127.0.0.1:3000', changeOrigin: true },
      },
    },
    preview: { host: '0.0.0.0', allowedHosts: ['.e2b.app'] },
  };
});
