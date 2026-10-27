import { test as base, expect } from '@playwright/test';

const LOCAL_HOSTS = new Set(['localhost', '127.0.0.1', '[::1]']);

// Import `test` and `expect` from this file in every spec. The guard fails a test that lets the
// browser call any host other than localhost without a mock, so a test can never silently hit a
// real API. (In verify, the network is also blocked outside the browser.)
export const test = base.extend<{ externalRequestGuard: void }>({
  externalRequestGuard: [
    async ({ context }, use) => {
      const unmocked: string[] = [];
      // Registered before the test's own routes, so it only sees what no page.route or
      // context.route in the test handled.
      await context.route('**/*', (route) => {
        const url = route.request().url();
        if (LOCAL_HOSTS.has(new URL(url).hostname)) return route.fallback();
        unmocked.push(url);
        return route.abort('blockedbyclient');
      });
      await use();
      expect(unmocked, 'requests to hosts other than localhost that no route mocked').toEqual([]);
    },
    { auto: true },
  ],
});

export { expect };

// An unsigned token (header {"alg":"none"}, empty signature): looks like a JWT to the app,
// can never be a real one, and passes verify's secret scan. Never paste a real token here.
export const FAKE_TOKEN = 'eyJhbGciOiJub25lIn0.eyJzdWIiOiJ1c2VyLTEiLCJlbWFpbCI6InVzZXJAZXhhbXBsZS5jb20ifQ.';
export const USER = { name: 'Test User', email: 'user@example.com' };
