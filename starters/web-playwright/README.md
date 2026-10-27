# Web Playwright starter (verify `e2e`)

A starting point for the 3–5 critical-journey tests that `verify` runs for `stack: web`. Copy it into
your repo, then replace the selectors and routes with your app's.

## Set up
1. Copy `playwright.config.ts` and `e2e/` to the project directory.
2. `npm i -D @playwright/test @types/node` (pin `@playwright/test` like any dependency; `@types/node`
   lets `tsc` read `process.env` in the config).
3. Add the script: `"test:e2e": "playwright test"`.
4. Point `webServer.command` at your **production build**: `vite preview` (as here) or
   `next start -p 4173`. `verify` runs `build` first; locally run `npm run build && npm run test:e2e`.
5. `npx playwright install chromium` once on your machine.

## The rules `verify` enforces
- **No real environment.** During `test:e2e` the CI machine blocks all outbound traffic except
  localhost. Mock every API call:
  - browser calls: `page.route(...)` (see `sign-in.spec.ts`), or replay a recording with
    `page.routeFromHAR('e2e/recordings/x.har')`. Record once against dev with a test account using
    `{ update: true, updateContent: 'embed' }` (zipped or `attach` recordings put bodies where they
    are harder to scrub; `verify` refuses `.zip`), then scrub tokens, cookies, passwords and
    personal data;
  - server-side calls (Next.js server components, route handlers, `getServerSideProps`): put a
    Mockoon environment in `e2e/mocks.json` (design or record it in the Mockoon desktop app).
    `verify` serves it and sets `E2E_API_URL` (and `VERIFY_E2E=1`); read the API base URL from
    `process.env.E2E_API_URL` when it is set.
- **Guard.** Import `test` and `expect` from `e2e/fixtures.ts` in every spec. A browser request to
  any other host that no route mocked fails the test and lists the URL.
- **Allowed hosts.** Only third-party SDKs the app cannot work without (crash reporting, maps) go in
  `e2e/allowed-hosts.txt`, one host per line with the reason. Never our own APIs.
- **No real credentials.** `verify` scans `e2e/**/*.har` and `e2e/mocks.json` and refuses real
  emails, signed JWTs, tokens, credential headers and passwords. Use `example.com` addresses and an
  unsigned token like `FAKE_TOKEN` in `fixtures.ts`.
- **Flaky tests** get one retry in CI and are named in the job summary; fix them. On failure the
  HTML report, traces and videos are uploaded as the artifact `e2e-report`.

## Run it the way CI does
```bash
npm run build && CI=true npm run test:e2e
gh workflow run verify.yml --ref <your-branch>   # the full check on GitHub
```
