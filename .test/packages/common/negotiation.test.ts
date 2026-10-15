import { describe, expect, it } from 'vitest';
import * as common from '../../../hanoti/packages/common/src/index.js';
import { NegotiationClient } from '../../../hanoti/packages/common/src/negotiation/client.js';
import {
  MemoryRequestStore,
  NegotiationServer,
} from '../../../hanoti/packages/common/src/negotiation/server.js';

describe('HTTP negotiation re-exports', () => {
  it('exports the client through the shared root and dedicated client entry point', () => {
    expect(common.NegotiationClient).toBe(NegotiationClient);
    const client = new NegotiationClient();
    expect(client.use({ 'demo.hello': () => 'Hello from Hanouti' })).toBe(client);
  });

  it('keeps server-only exports out of the shared root', () => {
    expect(common).not.toHaveProperty('NegotiationServer');
    expect(common).not.toHaveProperty('PostgresRequestStore');
  });

  it('exposes a separate server API without starting a listener', async () => {
    const server = new NegotiationServer({ store: new MemoryRequestStore() });
    try {
      expect(server.use({ 'demo.hello': () => 'Hello from Hanouti' })).toBe(server);
      expect(typeof server.requestHandler()).toBe('function');
    } finally {
      await server.close();
    }
  });
});
