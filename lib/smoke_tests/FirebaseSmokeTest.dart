import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../firebase_options.dart';

class FirebaseSmokeTest extends StatefulWidget {
  const FirebaseSmokeTest({super.key});
  @override State<FirebaseSmokeTest> createState() => _FirebaseSmokeTestState();
}

class _FirebaseSmokeTestState extends State<FirebaseSmokeTest> {
  String log = 'Starting…';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      _append('Firebase init OK');

      // anonymous auth (or email/password if you prefer)
      final cred = await FirebaseAuth.instance.signInAnonymously();
      _append('Auth OK: ${cred.user?.uid}');

      // write + read a tiny doc
      final doc = FirebaseFirestore.instance.collection('smoke').doc('probe');
      await doc.set({'ts': DateTime.now().toIso8601String(), 'ok': true});
      final snap = await doc.get();
      _append('Firestore OK: ${snap.data()}');
    } catch (e, st) {
      _append('ERROR: $e\n$st');
    }
  }

  void _append(String s) => setState(() => log = '$log\n$s');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Firebase Smoke Test')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text(log, style: const TextStyle(fontFamily: 'monospace')),
      ),
    );
  }
}
