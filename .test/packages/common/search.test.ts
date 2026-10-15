import { describe, expect, it } from 'vitest';
import {
  SearchService,
  detectScript,
  normalizeForIndex,
  type Product,
} from '../../../hanoti/packages/common/src/index.js';

const products: Product[] = [
  {
    id: 'coffee-1',
    title: 'Coffee beans',
    brand: 'Hanouti',
    category: 'grocery',
    categoryLabels: ['Grocery'],
    description: 'Roasted coffee beans',
    price: 12,
    rating: 4.5,
    sales: 10,
    stock: 20,
    tags: ['coffee'],
  },
];

describe('smart-hybrid-search re-exports', () => {
  it('searches products through the shared public API', () => {
    const service = new SearchService(products);
    const result = service.search('coffee');
    expect(service.stats.totalDocs).toBe(1);
    expect(result.total).toBe(1);
    expect(result.results[0]?.product.id).toBe('coffee-1');
  });

  it('exports normalization and script detection helpers', () => {
    expect(normalizeForIndex('COFFEE')).toBe('coffee');
    expect(detectScript('قهوة')).toBe('ar');
    expect(detectScript('coffee')).toBe('latin');
  });
});
