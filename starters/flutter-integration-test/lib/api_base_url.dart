// Option B: the one place the app picks its API host. In verify, the app is built with
// --dart-define=VERIFY_E2E=true --dart-define=E2E_API_URL=http://localhost:3901 (Mockoon serving
// e2e/mocks.json, forwarded into the emulator). Use your real host otherwise.
const bool verifyE2e = bool.fromEnvironment('VERIFY_E2E');
const String apiBaseUrl = verifyE2e
    ? String.fromEnvironment('E2E_API_URL')
    : 'https://api.example.com';
