// lib/controllers/stream_controller.dart

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../services/stream_http_service.dart';
import '../services/rtsp_service.dart';

/// Rough state reported by the Pi via the HTTP API.
enum StreamReported { running, stopped, unknown }

/// UI-level state of the video widget.
enum StreamUiState { idle, attaching, playing, error }

/// Small controller that:
/// - ensures the Pi HTTP service is running
/// - attaches to RTSP
/// - exposes status + error information to the UI
class StreamControllerX with ChangeNotifier {
  // NOTE: http is mutable so we can swap base URL at runtime.
  StreamHttpService http;
  final RtspService rtsp;
  final String rtspUrl;

  StreamControllerX({
    required this.http,
    required this.rtsp,
    required this.rtspUrl,
  });

  StreamReported reported = StreamReported.unknown;
  StreamUiState ui = StreamUiState.idle;
  String? lastError;

  /// Update the HTTP base URL (e.g., different Pi IP) and token.
  void updateBase(String newBaseUrl, String token) {
    http = StreamHttpService(base: newBaseUrl, token: token);
    notifyListeners();
  }

  /// Start the stream:
  /// - tell Pi to ensure streaming service is running
  /// - try to attach RTSP with limited retries
  /// - poll status once
  Future<void> initAndAttach() async {
    // Fire-and-forget: ask Pi to ensure service is running
    unawaited(http.ensureRunning().catchError((_) {}));

    ui = StreamUiState.attaching;
    lastError = null;
    notifyListeners();

    var delay = const Duration(milliseconds: 300);

    // Try a few times; backoff slightly on failure.
    for (var i = 0; i < 8; i++) {
      try {
        await rtsp.attach(rtspUrl);
        ui = StreamUiState.playing;
        notifyListeners();
        break;
      } catch (e) {
        lastError = e.toString();
        await Future.delayed(delay);
        delay = Duration(
          milliseconds: (delay.inMilliseconds * 1.6)
              .clamp(300, 3000)
              .toInt(),
        );
      }
    }

    if (ui != StreamUiState.playing) {
      ui = StreamUiState.error;
      notifyListeners();
    }

    // Optional: poll once for the Pi's own status.
    try {
      final s = await http.status();
      reported = (s == 'running')
          ? StreamReported.running
          : (s == 'stopped')
          ? StreamReported.stopped
          : StreamReported.unknown;
      notifyListeners();
    } catch (_) {
      // ignore HTTP failure; UI state already reflects error.
    }
  }

  /// Stop everything: ask Pi to stop and detach RTSP.
  Future<void> stopAll() async {
    await http.stop().catchError((_) {});
    await rtsp.stop().catchError((_) {});
    ui = StreamUiState.idle;
    reported = StreamReported.stopped;
    notifyListeners();
  }

  /// Clean up RTSP resources.
  Future<void> disposeAll() async {
    await rtsp.dispose();
  }
}
