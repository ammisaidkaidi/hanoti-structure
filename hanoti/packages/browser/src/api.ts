import {
  greetingRequestSchema,
  greetingResponseSchema,
  healthResponseSchema,
  type GreetingRequest,
} from '@app/common';
async function request(path: string, init?: RequestInit): Promise<unknown> {
  const response = await fetch(path, { ...init, signal: AbortSignal.timeout(8000) });
  if (!response.ok) throw new Error(`API request failed (${response.status}). Please try again.`);
  return response.json() as Promise<unknown>;
}
export async function getHealth() {
  return healthResponseSchema.parse(await request('/api/health'));
}
export async function sendGreeting(input: GreetingRequest) {
  return greetingResponseSchema.parse(
    await request('/api/greetings', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(greetingRequestSchema.parse(input)),
    }),
  );
}
