import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'routes.dart';
import 'pages/welcome_page_route.dart';
import 'pages/login_page_route.dart';
import 'pages/register_page_route.dart';
import 'pages/dashboard_page_route.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: PageRoutes.welcome,                // <- always starts at Welcome
      routes: {
        PageRoutes.welcome:   (_) => const WelcomePageRoute(),
        PageRoutes.login:     (_) => const LoginPage(),
        PageRoutes.register:  (_) => const RegisterPage(),
        PageRoutes.dashboard: (_) => const DashboardPageRoute(), // reached only after success
      },
    );
  }
}



// // Newest editionL Nov 10th 8pm
//
// import 'package:flutter/material.dart';
// import 'package:firebase_core/firebase_core.dart';
// import 'firebase_options.dart';
//
// // Your route/page imports
// import 'routes.dart';
// import 'FirebaseSmokeTest.dart';
// import 'pages/welcome_page_route.dart';
// import 'pages/dashboard_page_route.dart';
// import 'pages/login_page_route.dart';
// import 'pages/register_page_route.dart';
//
// Future<void> main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//
//   // Initialize Firebase for the current platform (Android emulator in your case)
//   await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
//   runApp(const MaterialApp(home: FirebaseSmokeTest()));
//   // runApp(const MobileApp());
// }
//
// class MobileApp extends StatelessWidget {
//   const MobileApp({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       debugShowCheckedModeBanner: false,
//
//       // ---- THEME ----
//       theme: ThemeData(
//         // keep your font
//         fontFamily: 'Anta',
//
//         // optional: Material 3 on/off (comment out if you prefer M2)
//         // useMaterial3: true,
//
//         // Universal ElevatedButton style
//         elevatedButtonTheme: ElevatedButtonThemeData(
//           style: ButtonStyle(
//             textStyle: MaterialStateProperty.all(
//               const TextStyle(decoration: TextDecoration.underline),
//             ),
//             backgroundColor: MaterialStateProperty.all(Colors.green),
//             foregroundColor: MaterialStateProperty.all(Colors.black),
//             side: MaterialStateProperty.all(
//               const BorderSide(color: Colors.black, width: 4),
//             ),
//             shape: MaterialStateProperty.all(
//               RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
//             ),
//           ),
//         ),
//       ),
//
//       // ---- ROUTING ----
//       initialRoute: PageRoutes.home,
//       routes: {
//         PageRoutes.home: (context) => const WelcomePageRoute(),
//         PageRoutes.login: (context) => const LoginPage(),
//         PageRoutes.register: (context) => const RegisterPage(),
//         PageRoutes.dashboard: (context) => const DashboardPageRoute(),
//       },
//     );
//   }
// }
