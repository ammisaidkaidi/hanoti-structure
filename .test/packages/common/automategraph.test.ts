import { describe, expect, it } from 'vitest';
import {
  GraphExecutionEngine,
  Next,
  isNext,
  type GraphDefinition,
} from '../../../hanoti/packages/common/src/index.js';

describe('automategraph re-exports', () => {
  it('exposes the routing helpers', () => {
    const next = new Next('finish', 'hello');
    expect(isNext(next)).toBe(true);
    expect(next.nextNode).toBe('finish');
    expect(next.value).toBe('hello');
  });

  it('executes a graph using the shared public API', async () => {
    const definition: GraphDefinition = {
      id: 'shared-export-smoke-test',
      version: '1.0.0',
      entryNodes: ['hello'],
      terminalNodes: ['hello'],
      nodes: {
        hello: { id: 'hello', run: () => 'Hello from Hanouti' },
      },
    };
    const engine = new GraphExecutionEngine(definition);
    await engine.run();
    expect(engine.getState()).toBe('COMPLETED');
    expect(engine.getResults()[0]?.output).toBe('Hello from Hanouti');
  });
});
