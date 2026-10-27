// The one place the app picks its API host. In verify's Maestro run, Metro starts with
// VERIFY_E2E=1 and E2E_API_URL=http://localhost:3901 (Mockoon, forwarded into the emulator);
// babel.config.js inlines them at bundle time. Use your real host otherwise.
export const API_BASE_URL =
  process.env.VERIFY_E2E && process.env.E2E_API_URL
    ? process.env.E2E_API_URL
    : 'https://api.example.com';
