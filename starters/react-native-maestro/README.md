# React Native Maestro starter (verify `maestro`)

A starting point for the 3–5 critical-journey flows that `verify` runs for `stack: react-native`, on
an Android emulator (API 34, x86_64 debug build). Copy it into your repo, then replace `appId`, the
texts and the IDs with your app's.

## Set up
1. Copy `.maestro/` (at least 3 flows; keep `smoke.yaml`: app launches, first screen visible) and
   `e2e/` to the project root.
2. **Fake API:** `e2e/mocks.json` is a Mockoon environment file (open it in the Mockoon desktop app
   to design or record routes). CI serves it on `127.0.0.1:3901` and forwards it into the
   emulator.
3. **App wiring:** CI starts Metro with `VERIFY_E2E=1` and `E2E_API_URL=http://localhost:3901`,
   plus the same values as `EXPO_PUBLIC_VERIFY_E2E` and `EXPO_PUBLIC_E2E_API_URL`.
   - **They exist only in Metro's environment, at bundle time.** Something that reads
     `process.env` while bundling sees them: a Babel inline-env transform (add
     `babel-plugin-transform-inline-environment-variables`, see `babel.config.js`) or, in Expo
     apps, `process.env.EXPO_PUBLIC_E2E_API_URL`. react-native-config `.env` files, Gradle
     `buildConfigField` values and Expo variables without the `EXPO_PUBLIC_` prefix do **not** see
     them, because the APK is built before Metro starts.
   - Pick the API host in one place, like `src/api-base-url.ts`.
4. Give the inputs a `testID` so flows can use `id:` selectors.

## The rules `verify` enforces
- **Offline:** during the run the emulator, Metro and Maestro have no internet except
  `localhost` (Metro, Mockoon) and the hosts in `e2e/allowed-hosts.txt`. List only third-party
  SDKs the app cannot work without, one host per line with the reason; never our own APIs.
- **Write journeys (sign-up, forms, payments) must only ever call mocks,** never a real API, not
  even a test environment.
- **No real credentials:** `e2e/mocks.json` is scanned; use `example.com` addresses and an unsigned
  token (header `{"alg":"none"}`, empty signature), like the one in the mocks here.
- Every file directly in `.maestro/` is a flow (`config.yaml` and subfolders are not). A failed
  flow is re-run once; one that then passes is reported as flaky: fix it.
- On failure, screenshots, Maestro logs and the Metro and emulator logs are uploaded as the
  artifact `maestro-report`.

## Run it locally
Start an Android emulator, then:
```bash
VERIFY_E2E=1 E2E_API_URL=http://localhost:3901 npx react-native start --reset-cache   # terminal 1
npx @mockoon/cli@9.9.0 start -d e2e/mocks.json -p 3901                               # terminal 2
adb reverse tcp:3901 tcp:3901 && yarn android && maestro test .maestro/               # terminal 3
```
