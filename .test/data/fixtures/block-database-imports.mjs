// Reject heavyweight imports in a fresh Node process: loading the policy must stand alone.
import { register } from 'node:module';
const loader = `
export async function resolve(specifier, context, nextResolve) {
  if (['typeorm', 'pg', 'reflect-metadata'].some(name => specifier === name || specifier.startsWith(name + '/'))) {
    throw new Error('Database runtime loaded by the lightweight policy: ' + specifier);
  }
  const result = await nextResolve(specifier, context);
  if (result.url.includes('/entities/') || result.url.endsWith('/entity-registry.js')) {
    throw new Error('Entities loaded by the lightweight policy: ' + result.url);
  }
  return result;
}
`;
register(new URL(`data:text/javascript,${encodeURIComponent(loader)}`));
