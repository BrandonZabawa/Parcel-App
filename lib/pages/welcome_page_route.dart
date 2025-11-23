import 'package:flutter/material.dart';
import '../routes.dart';

class WelcomePageRoute extends StatelessWidget {
  const WelcomePageRoute({super.key});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.black45,
      body: Stack(
        children: [
          // Background image
          Positioned.fill(
            child: Opacity(
              opacity: 0.5,
              child: Image.asset(
                'assets/imgs/background.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Logo container and text at top
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.only(top: screenHeight * 0.15), // 15% from top
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: screenWidth * 10.5,
                    height: screenWidth * 10.4, // Square container
                    constraints: const BoxConstraints(
                      minWidth: 210,
                      maxWidth: 210,
                      minHeight: 210,
                      maxHeight: 210,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Image.asset(
                        'assets/imgs/logo.png',
                        width: screenWidth * 3.50,
                        height: screenWidth * 3.50,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.10), // 5% spacing
                  Text(
                    'P.A.R.C.E.L.',
                    style: TextStyle(
                      fontSize: screenWidth * 0.08, // Responsive font size
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.015),
                  // Text(
                  //   'Welcome to the PARCEL App',
                  //   style: TextStyle(
                  //     fontSize: screenWidth * 0.045, // Responsive font size
                  //     color: Colors.black,
                  //   ),
                  // ),
                ],
              ),
            ),
          ),
          // Button moved down from center
          Center(
            child: Padding(
              padding: EdgeInsets.only(top: screenHeight * 0.25), // 25% from center
              child: ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, PageRoutes.dashboard),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.black,
                  padding: EdgeInsets.symmetric(
                    horizontal: screenWidth * 0.1,
                    vertical: screenHeight * 0.02,
                  ),
                ),
                child: Text(
                  'Get Started',
                  style: TextStyle(fontSize: screenWidth * 0.045),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}