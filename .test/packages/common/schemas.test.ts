import { describe, expect, it } from 'vitest';
import {
  greetingRequestSchema,
  healthResponseSchema,
} from '../../../hanoti/packages/common/src/index.js';
describe('shared contracts', () => {
  it('trims valid names', () => {
    expect(greetingRequestSchema.parse({ name: '  Hanouti  ' })).toEqual({ name: 'Hanouti' });
  });
  it.each(['', '   ', 'x'.repeat(81)])('rejects invalid names', (name) => {
    expect(greetingRequestSchema.safeParse({ name }).success).toBe(false);
  });
  it('rejects unknown request fields', () => {
    expect(greetingRequestSchema.safeParse({ name: 'Ada', admin: true }).success).toBe(false);
  });
  it('validates the health contract', () => {
    expect(
      healthResponseSchema.safeParse({
        status: 'ok',
        service: 'hanouti-server',
        timestamp: new Date().toISOString(),
      }).success,
    ).toBe(true);
  });
});
