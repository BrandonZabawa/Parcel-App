
// lib/services/stream_http_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;

/// Thin HTTP client for talking to the Pi's Flask streaming service.
/// Expects endpoints:
///   POST /stream/start
///   POST /stream/stop
///   GET  /stream/status  → { "state": "running" | "stopped" | ... }
class StreamHttpService {
  final String base;   // e.g., http://192.168.1.50:8080
  final String token;  // must match STREAM_TOKEN on the Pi

  const StreamHttpService({required this.base, required this.token});

  Map<String, String> get _h => {
    'X-Stream-Token': token,
    'Content-Type': 'application/json',
  };

  Future<void> ensureRunning() async {
    await http.post(Uri.parse('$base/stream/start'), headers: _h);
  }

  Future<void> stop() async {
    await http.post(Uri.parse('$base/stream/stop'), headers: _h);
  }

  Future<String> status() async {
    final r = await http.get(Uri.parse('$base/stream/status'));
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    return (body['state'] as String?) ?? 'unknown';
  }
}
