import { test, expect, FAKE_TOKEN, USER } from './fixtures';

// Journey 2: sign-in goes through a mocked auth response, never a real identity provider.
test('user signs in', async ({ page }) => {
  await page.route('**/api/login', (route) => route.fulfill({ json: { token: FAKE_TOKEN, user: USER } }));
  await page.route('**/api/items', (route) => route.fulfill({ json: [] }));
  await page.goto('/');
  await page.getByLabel('Email').fill(USER.email);
  await page.getByLabel('Password').fill('not-a-real-password');
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page.getByText(`Welcome, ${USER.name}`)).toBeVisible();
});
