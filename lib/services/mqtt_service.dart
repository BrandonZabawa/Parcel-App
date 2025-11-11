import 'dart:async';
import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart' as mqtt;          // aliased types
import 'package:mqtt_client/mqtt_server_client.dart';           // server client (no alias)

enum MqttConnState { disconnected, connecting, connected, error }

class MqttService {
  final String broker;
  final int port;
  final String clientId;
  final String username;
  final String password;

  late final MqttServerClient _client; // NOTE: no alias here

  // Stream of individual messages:
  final _msgCtrl =
  StreamController<mqtt.MqttReceivedMessage<mqtt.MqttMessage>>.broadcast();
  Stream<mqtt.MqttReceivedMessage<mqtt.MqttMessage>> get rawStream =>
      _msgCtrl.stream;

  MqttConnState state = MqttConnState.disconnected;
  String lastError = '';
  int lastPingMs = -1;

  StreamSubscription? _updatesSub;

  MqttService({
    required this.broker,
    this.port = 1883,
    required this.clientId,
    this.username = '',
    this.password = '',
  }) {
    _client = MqttServerClient(broker, clientId)
      ..port = port
      ..logging(on: false)
      ..keepAlivePeriod = 20
      ..onConnected = _onConnected
      ..onDisconnected = _onDisconnected
      ..pongCallback = _onPong;

    _client.connectionMessage = mqtt.MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillQos(mqtt.MqttQos.atMostOnce);
  }

  Future<bool> connect() async {
    if (state == MqttConnState.connected) return true;
    state = MqttConnState.connecting;
    try {
      if (username.isNotEmpty) {
        await _client.connect(username, password);
      } else {
        await _client.connect();
      }

      // Fan out List<...> from updates into single events
      _updatesSub ??= _client.updates?.listen(
            (List<mqtt.MqttReceivedMessage<mqtt.MqttMessage>> events) {
          for (final e in events) {
            _msgCtrl.add(e);
          }
        },
      );

      return _client.connectionStatus?.state ==
          mqtt.MqttConnectionState.connected;
    } catch (e) {
      lastError = e.toString();
      _client.disconnect();
      state = MqttConnState.error;
      return false;
    }
  }

  void _onConnected() => state = MqttConnState.connected;
  void _onDisconnected() {
    if (state != MqttConnState.error) state = MqttConnState.disconnected;
  }

  void _onPong() => lastPingMs = -1;

  bool get isConnected => state == MqttConnState.connected;

  void subscribe(String topic, {mqtt.MqttQos qos = mqtt.MqttQos.atLeastOnce}) {
    if (!isConnected) return;
    _client.subscribe(topic, qos);
  }

  Future<void> publishString(String topic, String payload,
      {mqtt.MqttQos qos = mqtt.MqttQos.atLeastOnce}) async {
    if (!isConnected) {
      final ok = await connect();
      if (!ok) throw StateError('MQTT not connected: $lastError');
    }
    final b = mqtt.MqttClientPayloadBuilder()..addString(payload);
    _client.publishMessage(topic, qos, b.payload!);
  }

  Future<void> publishJson(String topic, Map<String, dynamic> jsonMap,
      {mqtt.MqttQos qos = mqtt.MqttQos.atLeastOnce}) async =>
      publishString(topic, jsonEncode(jsonMap), qos: qos);

  void dispose() {
    _updatesSub?.cancel();
    _msgCtrl.close();
    _client.disconnect();
  }
}