import { test, expect, FAKE_TOKEN, USER } from './fixtures';

// Journey 3: the main screen shows data from the API (mocked).
test('signed-in user sees their items', async ({ page }) => {
  await page.route('**/api/login', (route) => route.fulfill({ json: { token: FAKE_TOKEN, user: USER } }));
  await page.route('**/api/items', (route) =>
    route.fulfill({ json: [{ id: 1, name: 'First item' }, { id: 2, name: 'Second item' }] }),
  );
  // Or replay a recording made once against dev and scrubbed (verify scans e2e/**/*.har and the
  // files next to it). Record with `update: true, updateContent: 'embed'` (bodies inside the .har),
  // then drop `update`:
  // await page.routeFromHAR('e2e/recordings/items.har', { url: '**/api/**' });
  await page.goto('/');
  await page.getByLabel('Email').fill(USER.email);
  await page.getByLabel('Password').fill('not-a-real-password');
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page.getByRole('listitem')).toHaveText(['First item', 'Second item']);
});
