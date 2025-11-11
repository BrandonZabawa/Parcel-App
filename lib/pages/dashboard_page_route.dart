import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mqtt_client/mqtt_client.dart' as mqc;
import '../services/mqtt_service.dart';

class DashboardPageRoute extends StatefulWidget {
  const DashboardPageRoute({super.key});
  @override
  State<DashboardPageRoute> createState() => _DashboardPageRouteState();
}

class _DashboardPageRouteState extends State<DashboardPageRoute> {
  // MQTT
  static const String _brokerHost = 'broker.emqx.io';
  static const int _brokerPort = 1883;
  static const String tOffer = 'parcel/webrtc/offer';
  static const String tAnswer = 'parcel/webrtc/answer';
  static const String tCand  = 'parcel/webrtc/candidate';
  static const String tCtrl  = 'parcel/webrtc/control';

  late final MqttService mqtt;

  // WebRTC
  RTCPeerConnection? _pc;
  final _remote = RTCVideoRenderer();

  @override
  void initState() {
    super.initState();
    _remote.initialize();
    mqtt = MqttService(
      broker: _brokerHost, port: _brokerPort,
      clientId: 'parcel-mobile-${DateTime.now().millisecondsSinceEpoch}',
    );
    _connect();
  }

  Future<void> _connect() async {
    if (await mqtt.connect()) {
      mqtt.subscribe(tAnswer);
      mqtt.subscribe(tCand);
      mqtt.rawStream.listen((evt) async {
        final msg = evt.payload as mqc.MqttPublishMessage;
        final body = mqc.MqttPublishPayload.bytesToStringAsString(msg.payload.message);
        if (evt.topic == tAnswer && _pc != null) {
          final m = jsonDecode(body);
          final sdp = RTCSessionDescription(m['sdp'] as String, 'answer');
          await _pc!.setRemoteDescription(sdp);
        } else if (evt.topic == tCand && _pc != null) {
          final m = jsonDecode(body);
          if (m['role'] == 'pi') {
            final c = m['candidate'];
            await _pc!.addCandidate(RTCIceCandidate(
              c['candidate'] as String, c['sdpMid'] as String?, c['sdpMLineIndex'] as int?,
            ));
          }
        }
      });
    }
  }

  Future<void> _start() async {
    // 1) create RTCPeerConnection (no local camera/mic needed to receive video)
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'}
      ]
    };
    _pc = await createPeerConnection(config);

    // 2) Handle remote tracks
    _pc!.onTrack = (RTCTrackEvent e) async {
      if (e.track.kind == 'video' && e.streams.isNotEmpty) {
        _remote.srcObject = e.streams.first;
        setState(() {});
      }
    };

    // 3) Publish ICE candidates to Pi via MQTT
    _pc!.onIceCandidate = (RTCIceCandidate c) {
      if (c.candidate == null) return;
      mqtt.publishString(tCand, jsonEncode({
        'role': 'phone',
        'candidate': {
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        }
      }));
    };

    // 4) Create & publish offer
    final offer = await _pc!.createOffer({'offerToReceiveVideo': true, 'offerToReceiveAudio': false});
    await _pc!.setLocalDescription(offer);
    mqtt.publishString(tOffer, jsonEncode({'type': 'offer', 'sdp': offer.sdp}));

    // (optional) tell Pi to start stream
    mqtt.publishString(tCtrl, jsonEncode({'action': 'start_stream'}));
  }

  Future<void> _stop() async {
    mqtt.publishString(tCtrl, jsonEncode({'action': 'stop_stream'}));
    try { await _pc?.close(); } catch (_) {}
    _pc = null;
    _remote.srcObject = null;
    setState(() {});
  }

  @override
  void dispose() {
    _stop();
    _remote.dispose();
    mqtt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PARCEL Controls')),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(onPressed: _start, child: const Text('Start Livestream')),
              const SizedBox(width: 12),
              ElevatedButton(onPressed: _stop, child: const Text('Stop')),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: Colors.black45)),
              child: _remote.srcObject == null
                  ? const Center(child: Text('Waiting for video…'))
                  : RTCVideoView(_remote, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain),
            ),
          ),
        ],
      ),
    );
  }
}

// import 'dart:async';
// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:mqtt_client/mqtt_client.dart' as mqc;
// import '../services/mqtt_service.dart';
//
// class DashboardPageRoute extends StatefulWidget {
//   const DashboardPageRoute({super.key});
//   @override
//   State<DashboardPageRoute> createState() => _DashboardPageRouteState();
// }
//
// class _DashboardPageRouteState extends State<DashboardPageRoute> {
//   // ---------- DIMENSIONS ----------
//   static const double kLiveW = 720;
//   static const double kLiveH = 420;
//   static const double kBannerW = 560;
//   static const double kBannerGap = 12;
//   static const double kBannerBorder = 4;
//   static const double kBannerRadius = 14;
//
//   // ---- MQTT config ----
//   static const String _brokerHost = 'broker.emqx.io';
//   static const int _brokerPort = 1883;
//   static const String _mqttUser = '';
//   static const String _mqttPass = '';
//
//   // Topics (no WebRTC)
//   static const String tCmd = 'parcel/robot/cmd';
//   static const String tUiNotify = 'parcel/ui/notify';
//
//   late final MqttService mqtt;
//
//   String statusText = 'MQTT: disconnected';
//
//   // ---- Async notifications ----
//   final _notifCtrl = StreamController<Map<String, dynamic>>.broadcast();
//   _BannerData? _banner;
//   Timer? _bannerTimer;
//   bool _bannerVisible = false;
//
//   @override
//   void initState() {
//     super.initState();
//
//     mqtt = MqttService(
//       broker: _brokerHost,
//       port: _brokerPort,
//       clientId: 'parcel-mobile-${DateTime.now().millisecondsSinceEpoch}',
//       username: _mqttUser,
//       password: _mqttPass,
//     );
//
//     _notifCtrl.stream.listen(_handleNotif);
//     _connectMqtt();
//     _bindMqttListeners();
//   }
//
//   Future<void> _connectMqtt() async {
//     setState(() => statusText = 'MQTT: connecting...');
//     final ok = await mqtt.connect();
//     setState(() => statusText = ok ? 'MQTT: connected' : 'MQTT: error');
//     if (ok) {
//       mqtt.subscribe(tUiNotify);
//     }
//   }
//
//   void _bindMqttListeners() {
//     mqtt.rawStream.listen((evt) {
//       try {
//         // Works if your MqttService forwards mqtt_client events
//         final topic = evt.topic;
//         final rec = evt.payload as mqc.MqttPublishMessage;
//         final payloadStr =
//         mqc.MqttPublishPayload.bytesToStringAsString(rec.payload.message);
//
//         if (topic == tUiNotify) {
//           final Map<String, dynamic> msg = jsonDecode(payloadStr);
//           _notifCtrl.add(msg);
//         }
//       } catch (_) {
//         // If your MqttService exposes a different shape, adapt here.
//       }
//     });
//   }
//
//   // ---- Notifications ----
//   void _handleNotif(Map<String, dynamic> json) {
//     final type = (json['type'] as String?)?.toLowerCase() ?? 'info';
//     final title = (json['title'] as String?) ?? _defaultTitle(type);
//     final message = (json['message'] as String?) ?? '';
//     final data = _BannerData.from(type: type, title: title, message: message);
//
//     _bannerTimer?.cancel();
//     setState(() {
//       _banner = data;
//       _bannerVisible = true;
//     });
//
//     _bannerTimer = Timer(data.duration, () {
//       if (!mounted) return;
//       setState(() => _bannerVisible = false);
//       Future.delayed(const Duration(milliseconds: 250), () {
//         if (mounted && !_bannerVisible) setState(() => _banner = null);
//       });
//     });
//   }
//
//   String _defaultTitle(String type) {
//     switch (type) {
//       case 'success':
//         return 'Success';
//       case 'warn':
//         return 'Warning';
//       case 'error':
//         return 'Error';
//       default:
//         return 'Notice';
//     }
//   }
//
//   // ---- Commands (no WebRTC side effects) ----
//   Future<void> _sendStart() async {
//     await mqtt.publishJson(tCmd, {
//       'cmd': 'start',
//       'ts': DateTime.now().toIso8601String(),
//       'source': 'mobile',
//     });
//     _notifCtrl.add({
//       "type": "info",
//       "title": "Starting",
//       "message": "Robot start command sent."
//     });
//   }
//
//   Future<void> _sendStop() async {
//     await mqtt.publishJson(tCmd, {
//       'cmd': 'stop',
//       'ts': DateTime.now().toIso8601String(),
//       'source': 'mobile',
//     });
//     _notifCtrl.add({
//       "type": "warn",
//       "title": "Stopped",
//       "message": "Robot stop command sent."
//     });
//   }
//
//   @override
//   void dispose() {
//     _bannerTimer?.cancel();
//     _notifCtrl.close();
//     mqtt.dispose();
//     super.dispose();
//   }
//
//   // ---------- UI ----------
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('PARCEL Controls')),
//       backgroundColor: const Color(0xFFF7F0F5),
//       body: Stack(
//         children: [
//           // Top-left MQTT text
//           Padding(
//             padding: const EdgeInsets.all(16),
//             child: Text(statusText, style: Theme.of(context).textTheme.bodyMedium),
//           ),
//
//           // Top-right status bubble
//           Positioned(top: 12, right: 12, child: _statusBubble()),
//
//           // Center column: [Banner] + [Placeholder livestream box]
//           Center(
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 AnimatedSlide(
//                   duration: const Duration(milliseconds: 200),
//                   curve: Curves.easeOut,
//                   offset: _bannerVisible ? Offset.zero : const Offset(0, -0.15),
//                   child: AnimatedOpacity(
//                     duration: const Duration(milliseconds: 180),
//                     opacity: _bannerVisible ? 1.0 : 0.0,
//                     child: ConstrainedBox(
//                       constraints: BoxConstraints.tightFor(width: kBannerW),
//                       child: _notificationBanner(),
//                     ),
//                   ),
//                 ),
//                 SizedBox(height: kBannerGap),
//                 _liveViewBox(),
//               ],
//             ),
//           ),
//
//           // Bottom connection chip
//           Align(
//             alignment: Alignment.bottomCenter,
//             child: SafeArea(
//               minimum: const EdgeInsets.only(bottom: 110),
//               child: DecoratedBox(
//                 decoration: BoxDecoration(
//                   color: Colors.black.withOpacity(.7),
//                   borderRadius: BorderRadius.circular(24),
//                 ),
//                 child: Padding(
//                   padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
//                   child: Row(mainAxisSize: MainAxisSize.min, children: [
//                     const Icon(Icons.cloud, size: 16, color: Colors.white70),
//                     const SizedBox(width: 6),
//                     Text(
//                       mqtt.isConnected
//                           ? 'Connected • $_brokerHost:$_brokerPort'
//                           : 'Disconnected',
//                       style: const TextStyle(color: Colors.white),
//                     ),
//                   ]),
//                 ),
//               ),
//             ),
//           ),
//
//           // Bottom buttons
//           Align(
//             alignment: Alignment.bottomCenter,
//             child: SafeArea(
//               minimum: const EdgeInsets.only(bottom: 24),
//               child: Padding(
//                 padding: const EdgeInsets.symmetric(horizontal: 16),
//                 child: Wrap(
//                   alignment: WrapAlignment.center,
//                   spacing: 20,
//                   runSpacing: 12,
//                   children: [
//                     ElevatedButton(
//                       onPressed: _sendStart,
//                       style: ElevatedButton.styleFrom(
//                         minimumSize: const Size(220, 72),
//                         padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
//                         backgroundColor: Colors.green,
//                         foregroundColor: Colors.black,
//                         side: const BorderSide(color: Colors.black, width: 4),
//                         shape: RoundedRectangleBorder(
//                             borderRadius: BorderRadius.circular(12)),
//                       ),
//                       child: const Text('Start', style: TextStyle(fontSize: 22)),
//                     ),
//                     ElevatedButton(
//                       onPressed: _sendStop,
//                       style: ElevatedButton.styleFrom(
//                         minimumSize: const Size(220, 72),
//                         padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
//                         backgroundColor: Colors.red,
//                         foregroundColor: Colors.white,
//                         side: const BorderSide(color: Colors.black, width: 4),
//                         shape: RoundedRectangleBorder(
//                             borderRadius: BorderRadius.circular(12)),
//                       ),
//                       child: const Text('Stop', style: TextStyle(fontSize: 22)),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   // ---- Helpers ----
//   Widget _statusBubble() {
//     final connected = mqtt.isConnected;
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(22),
//         border: Border.all(color: Colors.black87, width: 3),
//       ),
//       child: Text(
//         connected ? 'Status:\nConnected' : 'Status:\nDisconnected',
//         textAlign: TextAlign.center,
//         style: const TextStyle(fontSize: 16),
//       ),
//     );
//   }
//
//   Widget _liveViewBox() {
//     // Placeholder box (WebRTC removed)
//     return Container(
//       width: kLiveW,
//       height: kLiveH,
//       decoration: BoxDecoration(
//         color: Colors.black,
//         borderRadius: BorderRadius.circular(28),
//         border: Border.all(color: Colors.black, width: 3),
//       ),
//       clipBehavior: Clip.antiAlias,
//       child: const Center(
//         child: Text(
//           'Livestream disabled',
//           style: TextStyle(color: Colors.white70),
//         ),
//       ),
//     );
//   }
//
//   Widget _notificationBanner() {
//     if (_banner == null) return const SizedBox.shrink();
//     final b = _banner!;
//     return Material(
//       color: Colors.transparent,
//       child: InkWell(
//         onTap: () {
//           _bannerTimer?.cancel();
//           setState(() => _bannerVisible = false);
//           Future.delayed(const Duration(milliseconds: 250), () {
//             if (mounted && !_bannerVisible) setState(() => _banner = null);
//           });
//         },
//         borderRadius: BorderRadius.circular(kBannerRadius),
//         child: Container(
//           padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
//           decoration: BoxDecoration(
//             color: b.bgColor,
//             borderRadius: BorderRadius.circular(kBannerRadius),
//             border: Border.all(color: Colors.black, width: kBannerBorder),
//             boxShadow: const [
//               BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 4)),
//             ],
//           ),
//           child: Row(
//             mainAxisSize: MainAxisSize.max,
//             children: [
//               Icon(b.icon, size: 28, color: b.fgColor),
//               const SizedBox(width: 14),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(b.title,
//                         style: TextStyle(
//                             fontSize: 18, fontWeight: FontWeight.w700, color: b.fgColor)),
//                     if (b.message.isNotEmpty) ...[
//                       const SizedBox(height: 2),
//                       Text(b.message, style: TextStyle(fontSize: 15, color: b.fgColor)),
//                     ],
//                   ],
//                 ),
//               ),
//               const SizedBox(width: 6),
//               Icon(Icons.close, size: 20, color: b.fgColor.withOpacity(0.9)),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
//
// // ---- Color mapping (“color wheels”) ----
// class _BannerData {
//   final String type;
//   final String title;
//   final String message;
//   final Color bgColor;
//   final Color fgColor;
//   final IconData icon;
//   final Duration duration;
//
//   _BannerData({
//     required this.type,
//     required this.title,
//     required this.message,
//     required this.bgColor,
//     required this.fgColor,
//     required this.icon,
//     this.duration = const Duration(seconds: 3),
//   });
//
//   factory _BannerData.from({
//     required String type,
//     required String title,
//     required String message,
//   }) {
//     switch (type) {
//       case 'success':
//         return _BannerData(
//           type: type,
//           title: title,
//           message: message,
//           bgColor: const Color(0xFF79E27D),
//           fgColor: const Color(0xFF0B2A10),
//           icon: Icons.check_circle,
//           duration: const Duration(seconds: 3),
//         );
//       case 'warn':
//         return _BannerData(
//           type: type,
//           title: title,
//           message: message,
//           bgColor: const Color(0xFFFFE082),
//           fgColor: const Color(0xFF3A2A00),
//           icon: Icons.warning_amber_rounded,
//           duration: const Duration(seconds: 4),
//         );
//       case 'error':
//         return _BannerData(
//           type: type,
//           title: title,
//           message: message,
//           bgColor: const Color(0xFFFF8A80),
//           fgColor: const Color(0xFF3A0000),
//           icon: Icons.error_rounded,
//           duration: const Duration(seconds: 4),
//         );
//       default:
//         return _BannerData(
//           type: 'info',
//           title: title,
//           message: message,
//           bgColor: const Color(0xFFB3E5FC),
//           fgColor: const Color(0xFF083246),
//           icon: Icons.info_rounded,
//           duration: const Duration(seconds: 3),
//         );
//     }
//   }
// }

// import 'dart:async';
// import 'dart:convert';
// import 'package:flutter/material.dart';
// // import 'package:flutter_webrtc/flutter_webrtc.dart';
// import 'package:mqtt_client/mqtt_client.dart' as mqc;
// import '../services/mqtt_service.dart';
//
// class DashboardPageRoute extends StatefulWidget {
//   const DashboardPageRoute({super.key});
//   @override
//   State<DashboardPageRoute> createState() => _DashboardPageRouteState();
// }
//
// class _DashboardPageRouteState extends State<DashboardPageRoute> {
//   // ---------- DIMENSIONS (match your mock) ----------
//   static const double kLiveW = 720;
//   static const double kLiveH = 420;
//   static const double kBannerW = 560;     // notification bar width
//   static const double kBannerGap = 12;    // space between banner and livestream
//   static const double kBannerBorder = 4;  // thick border like buttons
//   static const double kBannerRadius = 14; // rounded corners
//
//   // ---- MQTT config ----
//   static const String _brokerHost = 'broker.emqx.io';
//   static const int _brokerPort = 1883;
//   static const String _mqttUser = '';
//   static const String _mqttPass = '';
//
//   // Topics
//   static const String tCmd = 'parcel/robot/cmd';
//   static const String tSigOffer = 'parcel/webrtc/offer';
//   static const String tSigAnswer = 'parcel/webrtc/answer';
//   static const String tSigCandidate = 'parcel/webrtc/candidate';
//   static const String tSigControl = 'parcel/webrtc/control';
//   static const String tUiNotify = 'parcel/ui/notify'; // optional
//
//   late final MqttService mqtt;
//
//   // ---- WebRTC ----
//   RTCPeerConnection? _pc;
//   final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
//   MediaStream? _remoteStream;
//   bool _webrtcActive = false;
//
//   String statusText = 'MQTT: disconnected';
//
//   // ---- Async notifications ----
//   final _notifCtrl = StreamController<Map<String, dynamic>>.broadcast();
//   _BannerData? _banner;
//   Timer? _bannerTimer;
//   bool _bannerVisible = false;
//
//   @override
//   void initState() {
//     super.initState();
//     _remoteRenderer.initialize();
//
//     mqtt = MqttService(
//       broker: _brokerHost,
//       port: _brokerPort,
//       clientId: 'parcel-mobile-${DateTime.now().millisecondsSinceEpoch}',
//       username: _mqttUser,
//       password: _mqttPass,
//     );
//
//     _notifCtrl.stream.listen(_handleNotif);
//
//     _connectMqtt();
//     _bindMqttListeners();
//   }
//
//   Future<void> _connectMqtt() async {
//     setState(() => statusText = 'MQTT: connecting...');
//     final ok = await mqtt.connect();
//     setState(() => statusText = ok ? 'MQTT: connected' : 'MQTT: error');
//     if (ok) {
//       mqtt.subscribe(tSigAnswer);
//       mqtt.subscribe(tSigCandidate);
//       mqtt.subscribe(tUiNotify);
//     }
//   }
//
//   void _bindMqttListeners() {
//     mqtt.rawStream.listen((evt) async {
//       final topic = evt.topic;
//       final rec = evt.payload as mqc.MqttPublishMessage;
//       final payloadStr =
//       mqc.MqttPublishPayload.bytesToStringAsString(rec.payload.message);
//
//       if (topic == tUiNotify) {
//         try {
//           final Map<String, dynamic> msg = jsonDecode(payloadStr);
//           _notifCtrl.add(msg);
//         } catch (_) {}
//         return;
//       }
//
//       if (topic == tSigAnswer) {
//         final msg = jsonDecode(payloadStr);
//         if (msg['type'] == 'answer' && _pc != null) {
//           final sdp = RTCSessionDescription(msg['sdp'] as String, 'answer');
//           await _pc!.setRemoteDescription(sdp);
//         }
//       } else if (topic == tSigCandidate) {
//         final msg = jsonDecode(payloadStr);
//         if (msg['role'] == 'pi' && _pc != null && msg['candidate'] != null) {
//           final c = msg['candidate'];
//           final ice = RTCIceCandidate(
//             c['candidate'] as String,
//             c['sdpMid'] as String?,
//             c['sdpMLineIndex'] as int?,
//           );
//           await _pc!.addCandidate(ice);
//         }
//       }
//     });
//   }
//
//   // ---- Notifications
//   void _handleNotif(Map<String, dynamic> json) {
//     final type = (json['type'] as String?)?.toLowerCase() ?? 'info';
//     final title = (json['title'] as String?) ?? _defaultTitle(type);
//     final message = (json['message'] as String?) ?? '';
//     final data = _BannerData.from(type: type, title: title, message: message);
//
//     _bannerTimer?.cancel();
//     setState(() {
//       _banner = data;
//       _bannerVisible = true;
//     });
//
//     _bannerTimer = Timer(data.duration, () {
//       if (!mounted) return;
//       setState(() => _bannerVisible = false);
//       Future.delayed(const Duration(milliseconds: 250), () {
//         if (mounted && !_bannerVisible) setState(() => _banner = null);
//       });
//     });
//   }
//
//   String _defaultTitle(String type) {
//     switch (type) {
//       case 'success':
//         return 'Success';
//       case 'warn':
//         return 'Warning';
//       case 'error':
//         return 'Error';
//       default:
//         return 'Notice';
//     }
//   }
//
//   // ---- Commands
//   Future<void> _sendStart() async {
//     await mqtt.publishJson(tCmd, {
//       'cmd': 'start',
//       'ts': DateTime.now().toIso8601String(),
//       'source': 'mobile',
//     });
//     await mqtt.publishJson(tSigControl, {'action': 'start_stream'});
//     _notifCtrl.add({"type": "info", "title": "Starting", "message": "Preparing livestream…"});
//     await _startWebRTC();
//   }
//
//   Future<void> _sendStop() async {
//     await mqtt.publishJson(tCmd, {
//       'cmd': 'stop',
//       'ts': DateTime.now().toIso8601String(),
//       'source': 'mobile',
//     });
//     await mqtt.publishJson(tSigControl, {'action': 'stop_stream'});
//     _notifCtrl.add({"type": "warn", "title": "Stopped", "message": "Robot stopping procedure engage."});
//     await _stopWebRTC();
//   }
//
//   Future<void> _startWebRTC() async {
//     if (_webrtcActive) return;
//     final config = {
//       'iceServers': [
//         {'urls': 'stun:stun.l.google.com:19302'},
//       ]
//     };
//     final constraints = {
//       'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true},
//       'optional': [],
//     };
//
//     _pc = await createPeerConnection(config);
//
//     _pc!.onIceCandidate = (cand) async {
//       if (cand == null) return;
//       await mqtt.publishJson(tSigCandidate, {
//         'role': 'phone',
//         'candidate': {
//           'candidate': cand.candidate,
//           'sdpMid': cand.sdpMid,
//           'sdpMLineIndex': cand.sdpMLineIndex,
//         }
//       });
//     };
//
//     _pc!.onTrack = (RTCTrackEvent ev) async {
//       if (ev.track.kind == 'video') {
//         _remoteStream ??= await createLocalMediaStream('remote');
//         _remoteStream!.addTrack(ev.track);
//         _remoteRenderer.srcObject = ev.streams.first;
//         setState(() {});
//       }
//     };
//
//     final offer = await _pc!.createOffer(constraints);
//     await _pc!.setLocalDescription(offer);
//
//     await mqtt.publishJson(tSigOffer, {'type': 'offer', 'sdp': offer.sdp});
//     _webrtcActive = true;
//   }
//
//   Future<void> _stopWebRTC() async {
//     _webrtcActive = false;
//     try {
//       await _pc?.close();
//       _pc?.dispose();
//     } catch (_) {}
//     _pc = null;
//     _remoteRenderer.srcObject = null;
//     _remoteStream = null;
//     setState(() {});
//   }
//
//   @override
//   void dispose() {
//     _bannerTimer?.cancel();
//     _notifCtrl.close();
//     _stopWebRTC();
//     mqtt.dispose();
//     _remoteRenderer.dispose();
//     super.dispose();
//   }
//
//   // ---------- UI ----------
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('PARCEL Controls')),
//       backgroundColor: const Color(0xFFF7F0F5),
//       body: Stack(
//         children: [
//           // Top-left MQTT text
//           Padding(
//             padding: const EdgeInsets.all(16),
//             child: Text(statusText, style: Theme.of(context).textTheme.bodyMedium),
//           ),
//
//           // Top-right status bubble
//           Positioned(top: 12, right: 12, child: _statusBubble()),
//
//           // Centered column: [Banner] above [Livestream] with fixed sizes
//           Center(
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 AnimatedSlide(
//                   duration: const Duration(milliseconds: 200),
//                   curve: Curves.easeOut,
//                   offset: _bannerVisible ? Offset.zero : const Offset(0, -0.15),
//                   child: AnimatedOpacity(
//                     duration: const Duration(milliseconds: 180),
//                     opacity: _bannerVisible ? 1.0 : 0.0,
//                     child: ConstrainedBox(
//                       constraints: BoxConstraints.tightFor(width: kBannerW),
//                       child: _notificationBanner(),
//                     ),
//                   ),
//                 ),
//                 SizedBox(height: kBannerGap),
//                 _liveViewBox(),
//               ],
//             ),
//           ),
//
//           // Bottom connection chip
//           Align(
//             alignment: Alignment.bottomCenter,
//             child: SafeArea(
//               minimum: const EdgeInsets.only(bottom: 110),
//               child: DecoratedBox(
//                 decoration: BoxDecoration(
//                   color: Colors.black.withOpacity(.7),
//                   borderRadius: BorderRadius.circular(24),
//                 ),
//                 child: Padding(
//                   padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
//                   child: Row(mainAxisSize: MainAxisSize.min, children: [
//                     const Icon(Icons.cloud, size: 16, color: Colors.white70),
//                     const SizedBox(width: 6),
//                     Text(
//                       mqtt.isConnected
//                           ? 'Connected • $_brokerHost:$_brokerPort'
//                           : 'Disconnected',
//                       style: const TextStyle(color: Colors.white),
//                     ),
//                   ]),
//                 ),
//               ),
//             ),
//           ),
//
//           // Bottom buttons
//           Align(
//             alignment: Alignment.bottomCenter,
//             child: SafeArea(
//               minimum: const EdgeInsets.only(bottom: 24),
//               child: Padding(
//                 padding: const EdgeInsets.symmetric(horizontal: 16),
//                 child: Wrap(
//                   alignment: WrapAlignment.center,
//                   spacing: 20,
//                   runSpacing: 12,
//                   children: [
//                     ElevatedButton(
//                       onPressed: _sendStart,
//                       style: ElevatedButton.styleFrom(
//                         minimumSize: const Size(220, 72),
//                         padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
//                         backgroundColor: Colors.green,
//                         foregroundColor: Colors.black,
//                         side: const BorderSide(color: Colors.black, width: 4),
//                         shape: RoundedRectangleBorder(
//                             borderRadius: BorderRadius.circular(12)),
//                       ),
//                       child: const Text('Start Livestream', style: TextStyle(fontSize: 22)),
//                     ),
//                     ElevatedButton(
//                       onPressed: _sendStop,
//                       style: ElevatedButton.styleFrom(
//                         minimumSize: const Size(220, 72),
//                         padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
//                         backgroundColor: Colors.red,
//                         foregroundColor: Colors.white,
//                         side: const BorderSide(color: Colors.black, width: 4),
//                         shape: RoundedRectangleBorder(
//                             borderRadius: BorderRadius.circular(12)),
//                       ),
//                       child: const Text('Stop Moving', style: TextStyle(fontSize: 22)),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   // ---- Helpers ----
//   Widget _statusBubble() {
//     final connected = mqtt.isConnected;
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(22),
//         border: Border.all(color: Colors.black87, width: 3),
//       ),
//       child: Text(
//         connected ? 'Status:\nConnected' : 'Status:\nDisconnected',
//         textAlign: TextAlign.center,
//         style: const TextStyle(fontSize: 16),
//       ),
//     );
//   }
//
//   Widget _liveViewBox() {
//     return Container(
//       width: kLiveW,
//       height: kLiveH,
//       decoration: BoxDecoration(
//         color: Colors.black,
//         borderRadius: BorderRadius.circular(28),
//         border: Border.all(color: Colors.black, width: 3),
//       ),
//       clipBehavior: Clip.antiAlias,
//       child: _remoteRenderer.srcObject == null
//           ? const Center(
//           child: Text('Waiting for livestream...',
//               style: TextStyle(color: Colors.white70)))
//           : RTCVideoView(
//         _remoteRenderer,
//         objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
//       ),
//     );
//   }
//
//   Widget _notificationBanner() {
//     if (_banner == null) return const SizedBox.shrink();
//     final b = _banner!;
//     return Material(
//       color: Colors.transparent,
//       child: InkWell(
//         onTap: () {
//           _bannerTimer?.cancel();
//           setState(() => _bannerVisible = false);
//           Future.delayed(const Duration(milliseconds: 250), () {
//             if (mounted && !_bannerVisible) setState(() => _banner = null);
//           });
//         },
//         borderRadius: BorderRadius.circular(kBannerRadius),
//         child: Container(
//           padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
//           decoration: BoxDecoration(
//             color: b.bgColor,
//             borderRadius: BorderRadius.circular(kBannerRadius),
//             border: Border.all(color: Colors.black, width: kBannerBorder),
//             boxShadow: const [
//               BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 4)),
//             ],
//           ),
//           child: Row(
//             mainAxisSize: MainAxisSize.max,
//             children: [
//               Icon(b.icon, size: 28, color: b.fgColor),
//               const SizedBox(width: 14),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(b.title,
//                         style: TextStyle(
//                             fontSize: 18, fontWeight: FontWeight.w700, color: b.fgColor)),
//                     if (b.message.isNotEmpty) ...[
//                       const SizedBox(height: 2),
//                       Text(b.message, style: TextStyle(fontSize: 15, color: b.fgColor)),
//                     ],
//                   ],
//                 ),
//               ),
//               const SizedBox(width: 6),
//               Icon(Icons.close, size: 20, color: b.fgColor.withOpacity(0.9)),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
//
// // ---- Color mapping (unchanged “color wheels”) ----
// class _BannerData {
//   final String type;
//   final String title;
//   final String message;
//   final Color bgColor;
//   final Color fgColor;
//   final IconData icon;
//   final Duration duration;
//
//   _BannerData({
//     required this.type,
//     required this.title,
//     required this.message,
//     required this.bgColor,
//     required this.fgColor,
//     required this.icon,
//     this.duration = const Duration(seconds: 3),
//   });
//
//   factory _BannerData.from({
//     required String type,
//     required String title,
//     required String message,
//   }) {
//     switch (type) {
//       case 'success':
//         return _BannerData(
//           type: type,
//           title: title,
//           message: message,
//           bgColor: const Color(0xFF79E27D),
//           fgColor: const Color(0xFF0B2A10),
//           icon: Icons.check_circle,
//           duration: const Duration(seconds: 3),
//         );
//       case 'warn':
//         return _BannerData(
//           type: type,
//           title: title,
//           message: message,
//           bgColor: const Color(0xFFFFE082),
//           fgColor: const Color(0xFF3A2A00),
//           icon: Icons.warning_amber_rounded,
//           duration: const Duration(seconds: 4),
//         );
//       case 'error':
//         return _BannerData(
//           type: type,
//           title: title,
//           message: message,
//           bgColor: const Color(0xFFFF8A80),
//           fgColor: const Color(0xFF3A0000),
//           icon: Icons.error_rounded,
//           duration: const Duration(seconds: 4),
//         );
//       default:
//         return _BannerData(
//           type: 'info',
//           title: title,
//           message: message,
//           bgColor: const Color(0xFFB3E5FC),
//           fgColor: const Color(0xFF083246),
//           icon: Icons.info_rounded,
//           duration: const Duration(seconds: 3),
//         );
//     }
//   }
// }