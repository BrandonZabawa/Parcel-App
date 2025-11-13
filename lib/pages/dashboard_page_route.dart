import 'dart:convert';
import 'package:flutter/material.dart';
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

  // Signaling/control topics (kept so you can sanity-check messages)
  static const String tOffer = 'parcel/webrtc/offer';
  static const String tAnswer = 'parcel/webrtc/answer';
  static const String tCand  = 'parcel/webrtc/candidate';
  static const String tCtrl  = 'parcel/webrtc/control';

  late final MqttService mqtt;

  // UI state
  bool _connected = false;
  bool _streamRequested = false;
  final List<String> _log = <String>[];

  void _append(String s) {
    setState(() => _log.insert(0, "${DateTime.now().toIso8601String()}  $s"));
  }

  @override
  void initState() {
    super.initState();
    mqtt = MqttService(
      broker: _brokerHost,
      port: _brokerPort,
      clientId: 'parcel-mobile-${DateTime.now().millisecondsSinceEpoch}',
    );
    _connect();
  }

  Future<void> _connect() async {
    final ok = await mqtt.connect();
    setState(() => _connected = ok);
    _append(ok ? "MQTT connected -> $_brokerHost:$_brokerPort" : "MQTT connect failed");

    if (!ok) return;

    for (final t in [tAnswer, tCand]) {
      mqtt.subscribe(t);
      _append("Subscribed $t");
    }

    mqtt.rawStream.listen((evt) {
      final msg = evt.payload as mqc.MqttPublishMessage;
      final body = mqc.MqttPublishPayload.bytesToStringAsString(msg.payload.message);
      _append("RX ${evt.topic}: $body");
    });
  }

  // Request start/stop of remote stream without WebRTC on the client
  Future<void> _start() async {
    if (!_connected) { _append("Not connected; ignoring START"); return; }
    setState(() => _streamRequested = true);
    // You can still publish a “dummy offer” or just a control message.
    mqtt.publishString(tCtrl, jsonEncode({'action': 'start_stream'}));
    _append("TX $tCtrl: start_stream");
  }

  Future<void> _stop() async {
    if (!_connected) { _append("Not connected; ignoring STOP"); return; }
    setState(() => _streamRequested = false);
    mqtt.publishString(tCtrl, jsonEncode({'action': 'stop_stream'}));
    _append("TX $tCtrl: stop_stream");
  }

  @override
  void dispose() {
    mqtt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = [
      "MQTT: ${_connected ? 'Connected' : 'Disconnected'}",
      "Stream requested: ${_streamRequested ? 'Yes' : 'No'}",
    ].join("   |   ");

    return Scaffold(
      appBar: AppBar(title: const Text('PARCEL Controls (No WebRTC)')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(status, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(onPressed: _start, child: const Text('Request Start')),
              const SizedBox(width: 12),
              ElevatedButton(onPressed: _stop, child: const Text('Request Stop')),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: Colors.black45)),
              // Placeholder “video” pane
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_streamRequested ? Icons.ondemand_video : Icons.videocam_off, size: 64),
                    const SizedBox(height: 8),
                    Text(_streamRequested ? 'Streaming requested (no WebRTC client)' : 'No stream requested'),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              reverse: true,
              padding: const EdgeInsets.all(12),
              itemCount: _log.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) => Text(_log[i], style: const TextStyle(fontFamily: 'monospace')),
            ),
          ),
        ],
      ),
    );
  }
}