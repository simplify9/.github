# Flutter integration-test starter (verify `flutter-e2e`)

A starting point for the 3–5 critical-journey tests that `verify` runs for `stack: flutter`, on an
Android emulator (API 34). Copy it into your repo and adapt the names, keys and texts.

## Set up
1. Add the dependency to `pubspec.yaml`:
   ```yaml
   dev_dependencies:
     integration_test:
       sdk: flutter
   ```
2. Copy `integration_test/app_test.dart` and write at least 3 `testWidgets(` journeys across
   `integration_test/*_test.dart`: the app starts, sign in, and the one or two core tasks.
3. Give the backend a fake, one of:
   - **Option A, fakes through dependency setup:** register fakes instead of real services before
     the tests run (`integration_test/fakes.dart`, GetIt shown). No server needed.
   - **Option B, Mockoon:** read the API host from `lib/api_base_url.dart` and put the fake
     responses in `e2e/mocks.json` (a Mockoon environment file; design or record it in the Mockoon
     desktop app). CI serves it and passes
     `--dart-define=VERIFY_E2E=true --dart-define=E2E_API_URL=http://localhost:3901`.
4. Give fields a `Key` so tests can find them.

## The rules `verify` enforces
- **Offline:** during the run the emulator and the Flutter tool have no internet except
  `localhost` and the hosts in `e2e/allowed-hosts.txt`. List only third-party SDKs the app cannot
  work without, one host per line with the reason; never our own APIs.
- **No real credentials:** `e2e/mocks.json` is scanned; use `example.com` addresses and an unsigned
  token (header `{"alg":"none"}`, empty signature), like the one in the mocks here.
- **Real HTTP is async:** use a pump-until helper (as in `app_test.dart`), not only `pumpAndSettle`.
- **On failure,** the test log, `adb logcat` and the emulator logs are uploaded as the artifact
  `flutter-e2e-report`.
- If a journey hits a system dialog (location, notifications), tell DevOps: Patrol support is
  added on request.

## Run it locally
Start an Android emulator, then:
```bash
npx @mockoon/cli@9.9.0 start -d e2e/mocks.json -p 3901 &   # Option B only
adb reverse tcp:3901 tcp:3901
flutter test integration_test --dart-define=VERIFY_E2E=true --dart-define=E2E_API_URL=http://localhost:3901
```
