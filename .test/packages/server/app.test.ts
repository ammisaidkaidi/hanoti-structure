import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { greetingResponseSchema, healthResponseSchema } from '@app/common';
import { createApp } from '../../../hanoti/packages/server/src/app.js';
const app = createApp();
describe('API', () => {
  it('returns a typed health response and security headers', async () => {
    const res = await request(app).get('/api/health').expect(200);
    expect(healthResponseSchema.safeParse(res.body).success).toBe(true);
    expect(res.headers['x-request-id']).toBeTruthy();
    expect(res.headers['x-content-type-options']).toBe('nosniff');
  });
  it('reads a server-side data asset and returns a greeting', async () => {
    const res = await request(app).post('/api/greetings').send({ name: ' Ada ' }).expect(200);
    expect(greetingResponseSchema.parse(res.body).message).toBe(
      'Welcome aboard, Ada. Your workspace is ready.',
    );
  });
  it('rejects invalid input', async () => {
    await request(app).post('/api/greetings').send({ name: ' ' }).expect(400);
  });
  it('handles malformed JSON', async () => {
    await request(app)
      .post('/api/greetings')
      .set('Content-Type', 'application/json')
      .send('{')
      .expect(400);
  });
  it('limits JSON payloads', async () => {
    await request(app)
      .post('/api/greetings')
      .send({ name: 'x'.repeat(40000) })
      .expect(413);
  });
  it('does not expose database assets', async () => {
    await request(app).get('/data/assets/welcome.json').expect(404);
  });
  it('allows only configured browser origins', async () => {
    const allowed = await request(app).get('/api/health').set('Origin', 'http://localhost:5173');
    const denied = await request(app).get('/api/health').set('Origin', 'https://untrusted.example');
    expect(allowed.headers['access-control-allow-origin']).toBe('http://localhost:5173');
    expect(denied.headers['access-control-allow-origin']).toBeUndefined();
  });
});
