import { createApp } from './app.js';
import { config } from './config.js';
const server = createApp().listen(config.PORT, config.HOST, () => {
  console.info(
    JSON.stringify({
      level: 'info',
      message: 'Hanouti API listening',
      host: config.HOST,
      port: config.PORT,
    }),
  );
});
server.on('error', (error) => {
  console.error(error);
  process.exitCode = 1;
});
let shuttingDown = false;
function shutdown(signal: string) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.info(JSON.stringify({ level: 'info', message: 'Shutting down', signal }));
  const timeout = setTimeout(() => process.exit(1), 10_000);
  timeout.unref();
  server.close((error) => {
    clearTimeout(timeout);
    process.exit(error ? 1 : 0);
  });
}
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
