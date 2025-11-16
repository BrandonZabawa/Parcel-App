import 'package:flutter/material.dart';
import '../routes.dart';

class WelcomePageRoute extends StatelessWidget {
  const WelcomePageRoute({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to P.A.R.C.E.L')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 45),
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, PageRoutes.dashboard),
              child: const Text('Dashboard'),
            ),
            // const SizedBox(height: 12),
            // ElevatedButton(
            //   onPressed: () => Navigator.pushNamed(context, PageRoutes.register),
            //   child: const Text('Register Account'),
            // ),
          ],
        ),
      ),
    );
  }
}

// import 'package:flutter/material.dart';
// import 'login_page_route.dart';
// import 'register_page_route.dart';
// // import '../widgets/glitch_robot_icon.dart';
// import '../routes.dart';
//
// class WelcomePageRoute extends StatelessWidget {
//
//   const WelcomePageRoute({super.key});
//
//   @override
//   Widget build(BuildContext context)
//   {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Welcome to P.A.R.C.E.L')), // AppBar
//       body: Center(
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             // const GlitchRobotIcon(),
//             const SizedBox(height: 45),
//             ElevatedButton(
//               onPressed: () => Navigator.pushNamed(context, PageRoutes.login),
//               child: const Text('Login Account'),
//             ), // Login Button
//             const SizedBox(height: 12),
//
//             ElevatedButton(
//               onPressed: () => Navigator.pushNamed(context, PageRoutes.register),
//               child: const Text('Register Account'),
//             ), // Create Account Button (register page)
//           ], // children
//         ),// child Column (why do we define it as child and not children)? Is this technically the parent of trhe children coded inside child: Column?
//       ), // Center
//     );
//   }
// }