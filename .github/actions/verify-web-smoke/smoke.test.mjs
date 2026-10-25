// Run: node --test .github/actions/verify-web-smoke/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chooseServer } from './smoke.mjs';

const has = (...dirs) => (d) => dirs.includes(d);

test('next in dependencies -> next start', () => {
  const s = chooseServer({ dependencies: { next: '15' } }, has('dist'));
  assert.deepEqual(s.args, ['next', 'start', '-p', '3000']);
  assert.equal(s.port, 3000);
});
test('first existing of dist, build, out', () => {
  assert.ok(chooseServer({}, has('build', 'out')).args.includes('build'));
  assert.ok(chooseServer({}, has('out')).args.includes('out'));
  assert.ok(chooseServer({}, has('dist', 'out')).args.includes('dist'));
  assert.equal(chooseServer({}, has('dist')).port, 4173);
});
test('next only in devDependencies is not next', () => {
  assert.ok(chooseServer({ devDependencies: { next: '15' } }, has('dist')).args.includes('dist'));
});
test('nothing to serve -> clear error', () => {
  assert.throws(() => chooseServer({}, has()), /no dist, build or out directory/);
});
