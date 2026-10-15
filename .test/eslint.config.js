import appConfig from '../hanoti/eslint.config.js';

export default [
  ...appConfig,
  {
    ignores: [
      'node_modules/**',
      'dist/**',
      'coverage/**',
      'logs/**',
      'archive/**',
      'artifacts/**',
      '.tmp/**',
      '.cache/**',
    ],
  },
];
