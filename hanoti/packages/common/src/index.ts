import { z } from 'zod';

// Isomorphic engine API and types; intentionally exclude Node-only script loaders.
export * from 'automategraph';

// Framework-agnostic search API and types for both applications.
export * from 'smart-hybrid-search';

// Only the browser-safe half belongs in the shared root entry point.
export * from './negotiation/client.js';

// Runtime schemas and inferred types: one contract for both applications.
export const greetingRequestSchema = z
  .object({
    name: z
      .string()
      .trim()
      .min(1, 'Please enter your name.')
      .max(80, 'Use 80 characters or fewer.'),
  })
  .strict();
export const greetingResponseSchema = z.object({ message: z.string() });
export const healthResponseSchema = z.object({
  status: z.literal('ok'),
  service: z.literal('hanouti-server'),
  timestamp: z.iso.datetime(),
});
export type GreetingRequest = z.infer<typeof greetingRequestSchema>;
export type GreetingResponse = z.infer<typeof greetingResponseSchema>;
export type HealthResponse = z.infer<typeof healthResponseSchema>;
