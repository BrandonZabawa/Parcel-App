import 'package:flutter/material.dart';

import 'routes.dart';
import 'pages/welcome_page_route.dart';
import 'pages/dashboard_page_route.dart';

/// Entry point of the app. No Firebase initialization anymore.
void main() => runApp(const App());

/// Root widget that sets up navigation and global app configuration.
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      /// Always start at the Welcome page.
      initialRoute: PageRoutes.welcome,

      /// Simple named routes for navigation.
      routes: {
        PageRoutes.welcome:   (_) => const WelcomePageRoute(),
        PageRoutes.dashboard: (_) => const DashboardPageRoute(),
      },
    );
  }
}
