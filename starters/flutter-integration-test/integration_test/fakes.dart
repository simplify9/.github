// Option A: replace real services with fakes through the app's own dependency setup (GetIt shown),
// so no backend is needed at all. Order matters: startApp() in app_test.dart runs the app's real
// setup first, then registerFakes(), then runApp, so the fakes win. Adapt the types to your app;
// delete this file if you use the Mockoon option (e2e/mocks.json) instead.
//
// import 'package:get_it/get_it.dart';
// import 'package:your_app/services/auth_service.dart';
//
// class FakeAuthService implements AuthService {
//   @override
//   Future<User> signIn(String email, String password) async =>
//       const User(name: 'Test User', email: 'user@example.com');
// }
//
// void registerFakes() {
//   final getIt = GetIt.instance;
//   getIt.allowReassignment = true;
//   getIt.registerSingleton<AuthService>(FakeAuthService());
// }
