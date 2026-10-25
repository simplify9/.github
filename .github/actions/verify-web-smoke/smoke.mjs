// Fallback smoke test: serve the built app, load "/" in Chromium, fail on any
// page error or console error. Run from the project dir; playwright is
// resolved from the directory this file was copied into (see action.yml).
import { existsSync, readFileSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { pathToFileURL } from 'node:url';

// Pure: `next` in deps -> next start; else first existing of dist/build/out.
export function chooseServer(pkg, exists) {
  const deps = { ...pkg.dependencies };
  if ('next' in deps) return { cmd: 'npx', args: ['next', 'start', '-p', '3000'], port: 3000 };
  const dir = ['dist', 'build', 'out'].find((d) => exists(d));
  if (!dir) throw new Error('no dist, build or out directory to serve; did the build step run?');
  return { cmd: 'python3', args: ['-m', 'http.server', '4173', '--directory', dir], port: 4173 };
}

async function waitFor(url, ms) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    try { if ((await fetch(url)).status === 200) return; } catch { /* not up yet */ }
    await new Promise((r) => setTimeout(r, 1000));
  }
  throw new Error(`no HTTP 200 from ${url} within ${ms / 1000}s`);
}

async function main() {
  const pkg = JSON.parse(readFileSync('package.json', 'utf8'));
  const srv = chooseServer(pkg, existsSync);
  const child = spawn(srv.cmd, srv.args, { stdio: 'inherit' });
  const url = `http://127.0.0.1:${srv.port}/`;
  const errors = [];
  let browser;
  try {
    await waitFor(url, 60000);
    const { chromium } = await import('playwright');
    browser = await chromium.launch();
    const page = await browser.newPage();
    page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}`));
    page.on('console', (m) => { if (m.type() === 'error') errors.push(`console: ${m.text()}`); });
    await page.goto(url, { waitUntil: 'networkidle' });
  } catch (e) {
    errors.push(`smoke: ${e.message}`);
  } finally {
    if (browser) await browser.close();
    child.kill();
  }
  errors.forEach((e) => console.log(`::error title=[VERIFY] smoke::${e.replace(/\r?\n/g, ' ')}`));
  console.log(`[VERIFY] smoke: ${errors.length} errors`);
  process.exit(errors.length > 0 ? 1 : 0);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
