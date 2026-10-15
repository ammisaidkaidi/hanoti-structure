import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

// An explicit root includes this hidden folder and keeps all test artifacts together.
export default defineConfig({
  root: fileURLToPath(new URL('.', import.meta.url)),
  cacheDir: fileURLToPath(new URL('./.cache/vitest/', import.meta.url)),
  server: {
    fs: {
      allow: [
        fileURLToPath(new URL('.', import.meta.url)),
        fileURLToPath(new URL('../hanoti/', import.meta.url)),
      ],
    },
  },
  test: {
    include: ['api/**/*.test.ts', 'data/**/*.test.ts', 'packages/**/*.test.ts'],
    coverage: {
      reportsDirectory: fileURLToPath(new URL('./coverage/', import.meta.url)),
    },
  },
});
