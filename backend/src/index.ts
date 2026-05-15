import { loadEnv } from './config/env.js';
import { buildApp } from './server.js';

async function main(): Promise<void> {
  const env = loadEnv();
  const app = await buildApp({ env });
  await app.listen({ host: env.HOST, port: env.PORT });
}

main().catch((err: unknown) => {
  // eslint-disable-next-line no-console
  console.error('Failed to start server', err);
  process.exit(1);
});
