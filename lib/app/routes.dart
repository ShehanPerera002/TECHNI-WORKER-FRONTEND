import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../screens/worker_signin_screen.dart';
import '../screens/otp_verification_screen.dart';
import '../screens/verified_screen.dart';
import '../screens/create_profile_screen.dart';
import '../screens/select_category_screen.dart';
import '../screens/worker_home_screen.dart';
import '../screens/pending_verification_screen.dart';

final Map<String, WidgetBuilder> appRoutes = {
  '/signin': (context) => const WorkerSignInScreen(),
  '/otp': (context) => const OtpVerificationScreen(),
  '/verified': (context) => const VerifiedScreen(),
  '/profile': (context) => const CreateProfileScreen(),
  
  '/category': (context) {
    // Extracting the arguments passed from CreateProfileScreen
    final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;

    if (args != null) {
      return SelectCategoryScreen(
        name: args['name'] as String,
        phone: args['phone'] as String,
        birthDate: args['birthDate'] as String, // Added Birth Date
        language: args['language'] as String,   // Language included
        profilePhoto: args['profilePhoto'] as PlatformFile,
        nicFront: args['nicFront'] as PlatformFile,
        nicBack: args['nicBack'] as PlatformFile,
        policeReport: args['policeReport'] as PlatformFile,
      );
    }
    // Safety fallback: Redirect back to profile creation if no args found
    return const CreateProfileScreen();
  },

  '/pending': (context) => const PendingVerificationScreen(),
  '/home': (context) => const WorkerHomeScreen(),
};