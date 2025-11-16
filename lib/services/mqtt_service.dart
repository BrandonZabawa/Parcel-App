// import 'dart:async';
// import 'dart:convert';

// import 'package:mqtt_client/mqtt_client.dart' as mqtt;
// import 'package:mqtt_client/mqtt_server_client.dart';

// /// High-level MQTT helper that:
// /// - connects to a broker
// /// - exposes a raw stream of MQTT messages
// /// - provides helper methods to publish string/JSON payloads.
// enum MqttConnState { disconnected, connecting, connected, error }

// class MqttService {
//   final String broker;
//   final int port;
//   final String clientId;
//   final String username;
//   final String password;

//   late final MqttServerClient _client;

//   // Fan out MQTT's List<...> updates into individual messages.
//   final _msgCtrl =
//   StreamController<mqtt.MqttReceivedMessage<mqtt.MqttMessage>>.broadcast();
//   Stream<mqtt.MqttReceivedMessage<mqtt.MqttMessage>> get rawStream =>
//       _msgCtrl.stream;

//   MqttConnState state = MqttConnState.disconnected;
//   String lastError = '';
//   int lastPingMs = -1;

//   StreamSubscription? _updatesSub;

//   MqttService({
//     required this.broker,
//     this.port = 8883,
//     required this.clientId,
//     this.username = 'parcel2',
//     this.password = 'password',
//   }) {
//     _client = MqttServerClient(broker, clientId)
//       ..port = port
//       ..logging(on: false)
//       ..keepAlivePeriod = 20
//       ..onConnected = _onConnected
//       ..onDisconnected = _onDisconnected
//       ..pongCallback = _onPong;

//     _client.connectionMessage = mqtt.MqttConnectMessage()
//         .withClientIdentifier(clientId)
//         .startClean()
//         .withWillQos(mqtt.MqttQos.atMostOnce);
//   }

//   /// Connect to the broker (idempotent).
//   Future<bool> connect() async {
//     if (state == MqttConnState.connected) return true;
//     state = MqttConnState.connecting;

//     try {
//       if (username.isNotEmpty) {
//         await _client.connect(username, password);
//       } else {
//         await _client.connect();
//       }

//       // Listen to updates from the broker and fan them out one by one.
//       _updatesSub ??= _client.updates?.listen(
//             (List<mqtt.MqttReceivedMessage<mqtt.MqttMessage>> events) {
//           for (final e in events) {
//             _msgCtrl.add(e);
//           }
//         },
//       );

//       final connected =
//           _client.connectionStatus?.state == mqtt.MqttConnectionState.connected;
//       state = connected ? MqttConnState.connected : MqttConnState.error;
//       return connected;
//     } catch (e) {
//       lastError = e.toString();
//       _client.disconnect();
//       state = MqttConnState.error;
//       return false;
//     }
//   }

//   void _onConnected() => state = MqttConnState.connected;

//   void _onDisconnected() {
//     if (state != MqttConnState.error) {
//       state = MqttConnState.disconnected;
//     }
//   }

//   void _onPong() => lastPingMs = -1;

//   bool get isConnected => state == MqttConnState.connected;

//   /// Subscribe to a topic (no-op if not connected).
//   void subscribe(String topic, {mqtt.MqttQos qos = mqtt.MqttQos.atLeastOnce}) {
//     if (!isConnected) return;
//     _client.subscribe(topic, qos);
//   }

//   /// Publish a raw string payload to a topic.
//   Future<void> publishString(
//       String topic,
//       String payload, {
//         mqtt.MqttQos qos = mqtt.MqttQos.atLeastOnce,
//       }) async {
//     if (!isConnected) {
//       final ok = await connect();
//       if (!ok) throw StateError('MQTT not connected: $lastError');
//     }

//     final b = mqtt.MqttClientPayloadBuilder()..addString(payload);
//     _client.publishMessage(topic, qos, b.payload!);
//   }

//   /// Convenience wrapper to publish JSON.
//   Future<void> publishJson(
//       String topic,
//       Map<String, dynamic> jsonMap, {
//         mqtt.MqttQos qos = mqtt.MqttQos.atLeastOnce,
//       }) async {
//     await publishString(topic, jsonEncode(jsonMap), qos: qos);
//   }

//   /// Clean up MQTT connection and streams.
//   void dispose() {
//     _updatesSub?.cancel();
//     _msgCtrl.close();
//     _client.disconnect();
//   }
// }
