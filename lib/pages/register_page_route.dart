// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import '../routes.dart';
//
// class RegisterPage extends StatefulWidget {
//   const RegisterPage({super.key});
//   @override
//   State<RegisterPage> createState() => _RegisterPageState();
// }
//
// class _RegisterPageState extends State<RegisterPage> {
//   final _formKey = GlobalKey<FormState>();
//   final _email = TextEditingController();
//   final _password = TextEditingController();
//   bool _obscure = true;
//   bool _loading = false;
//   String? _error;
//
//   @override
//   void dispose() {
//     _email.dispose();
//     _password.dispose();
//     super.dispose();
//   }
//
//   Future<void> _register() async {
//     if (!_formKey.currentState!.validate()) return;
//     if (_loading) return; // debounce
//     setState(() { _loading = true; _error = null; });
//
//     try {
//       final email = _email.text.trim();
//       final pass  = _password.text.trim();
//
//       final cred = await FirebaseAuth.instance
//           .createUserWithEmailAndPassword(email: email, password: pass)
//           .timeout(const Duration(seconds: 8));
//
//       if (!mounted) return;
//
//       // Navigate immediately
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         if (!mounted) return;
//         Navigator.of(context, rootNavigator: true)
//             .pushNamedAndRemoveUntil(PageRoutes.dashboard, (_) => false);
//       });
//
//       // Fire-and-forget profile create
//       FirebaseFirestore.instance
//           .collection('users')
//           .doc(cred.user!.uid)
//           .set({
//         'email': email,
//         'createdAt': FieldValue.serverTimestamp(),
//       }, SetOptions(merge: true))
//           .catchError((_) {});
//
//     } on TimeoutException {
//       setState(() => _error = 'Sign-up timed out. Check network and try again.');
//     } on FirebaseAuthException catch (e) {
//       setState(() => _error = switch (e.code) {
//         'email-already-in-use' => 'That email is already registered.',
//         'invalid-email'        => 'Please enter a valid email.',
//         'weak-password'        => 'Password too weak (min 6).',
//         'operation-not-allowed'=> 'Enable Email/Password in Firebase Console.',
//         _ => 'Auth error (${e.code}).',
//       });
//     } catch (e) {
//       setState(() => _error = 'Unexpected error: $e');
//     } finally {
//       if (mounted) setState(() => _loading = false);
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Create Account')),
//       body: Center(
//         child: ConstrainedBox(
//           constraints: const BoxConstraints(maxWidth: 420),
//           child: Padding(
//             padding: const EdgeInsets.all(16),
//             child: Form(
//               key: _formKey,
//               child: Column(mainAxisSize: MainAxisSize.min, children: [
//                 TextFormField(
//                   controller: _email,
//                   keyboardType: TextInputType.emailAddress,
//                   autofillHints: const [AutofillHints.email],
//                   decoration: const InputDecoration(labelText: 'Email'),
//                   validator: (v) {
//                     final t = (v ?? '').trim();
//                     if (t.isEmpty) return 'Email required';
//                     if (!t.contains('@') || !t.contains('.')) return 'Invalid email';
//                     return null;
//                   },
//                 ),
//                 const SizedBox(height: 12),
//                 TextFormField(
//                   controller: _password,
//                   obscureText: _obscure,
//                   decoration: InputDecoration(
//                     labelText: 'Password (min 6)',
//                     suffixIcon: IconButton(
//                       icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
//                       onPressed: () => setState(() => _obscure = !_obscure),
//                     ),
//                   ),
//                   validator: (v) => (v ?? '').trim().length < 6 ? 'Use at least 6 characters' : null,
//                 ),
//                 const SizedBox(height: 16),
//                 if (_error != null)
//                   Padding(
//                     padding: const EdgeInsets.only(bottom: 8),
//                     child: Text(_error!, style: const TextStyle(color: Colors.red)),
//                   ),
//                 SizedBox(
//                   width: double.infinity,
//                   child: ElevatedButton(
//                     onPressed: _loading ? null : _register,
//                     child: _loading
//                         ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
//                         : const Text('Create account'),
//                   ),
//                 ),
//                 TextButton(
//                   onPressed: _loading
//                       ? null
//                       : () => Navigator.pushReplacementNamed(context, PageRoutes.login),
//                   child: const Text('I already have an account'),
//                 ),
//               ]),
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }
