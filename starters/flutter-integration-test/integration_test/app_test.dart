// Three critical journeys, run by verify on an Android emulator (API 34) with the network blocked.
// Replace `your_app`, the keys and the texts with your app's.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:your_app/main.dart' as app;

// import 'fakes.dart'; // Option A: fakes through the app's dependency setup (see fakes.dart)

// Starts the app the way main() does, in three steps so fakes can go in between:
// 1. the app's own dependency setup, 2. (Option A) the fake overrides, 3. runApp.
// Split your main() into `setupDependencies()` + `runApp(const App())` for this; calling app.main()
// after registering fakes would run the real setup again and overwrite them.
Future<void> startApp(WidgetTester tester) async {
  await app.setupDependencies();
  // registerFakes(); // Option A
  await tester.pumpWidget(const app.App());
}

// Real (mocked) HTTP is async: pump until the widget appears or the timeout passes.
Future<void> pumpUntilFound(WidgetTester tester, Finder finder,
    {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets);
}

Future<void> signIn(WidgetTester tester) async {
  await startApp(tester);
  await pumpUntilFound(tester, find.byKey(const Key('email')));
  await tester.enterText(find.byKey(const Key('email')), 'user@example.com');
  await tester.enterText(find.byKey(const Key('password')), 'not-a-real-password');
  await tester.tap(find.text('Sign in'));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app starts on its first screen', (tester) async {
    await startApp(tester);
    await pumpUntilFound(tester, find.text('Sign in'));
  });

  testWidgets('user signs in', (tester) async {
    await signIn(tester);
    await pumpUntilFound(tester, find.text('Welcome, Test User'));
  });

  testWidgets('signed-in user sees their items', (tester) async {
    await signIn(tester);
    await pumpUntilFound(tester, find.text('First item'));
    expect(find.text('Second item'), findsOneWidget);
  });
}
