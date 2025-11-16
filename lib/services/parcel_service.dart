// // lib/services/parcel_service.dart

// import 'dart:async';
// import 'dart:convert';

// import 'package:mqtt_client/mqtt_client.dart';
// import 'package:mqtt_client/mqtt_server_client.dart';

// import '../models/parcel_model.dart';

// /// Service responsible for:
// /// - connecting to MQTT (EMQX only)
// /// - mirroring parcel state (queued / inTransit / delivered) in memory
// /// - exposing streams for the dashboard UI
// /// - reacting to robot/RFID/status topics
// class ParcelService {
//   ParcelService._private();
//   static final ParcelService instance = ParcelService._private();

//   // ========= MQTT CONFIG – EMQX ONLY, SIMPLE AUTH =========

//   static const String _mqttHost = 'r38d6e25.ala.us-east-1.emqxsl.com';
//   static const int _mqttPort = 8883; // EMQX TLS port

//   // Use a fixed client ID; don't run MQTTX with the same ID at the same time
//   static const String _mqttClientId = 'parcel-app';

//   static const String _mqttUsername = 'parcel2';
//   static const String _mqttPassword = 'password';

//   static const String _mqttTopicParcels = 'parcel/db/update';
//   static const String _topicNewParcel   = 'parcel/events';
//   static const String _topicStatus      = 'parcel/status';
//   static const String _topicCmd         = 'parcel/cmd';

//   late MqttServerClient _mqttClient;
//   bool _mqttConnected = false;

//   // ========= In-memory parcel store & streams =========

//   final Map<String, Parcel> _byId = {};
//   final Map<String, String> _idByTag = {};

//   final _queuedCtrl    = StreamController<List<Parcel>>.broadcast();
//   final _inTransitCtrl = StreamController<List<Parcel>>.broadcast();
//   final _deliveredCtrl = StreamController<List<Parcel>>.broadcast();

//   Stream<List<Parcel>> streamByStatus(ParcelStatus status) {
//     switch (status) {
//       case ParcelStatus.queued:
//         return _queuedCtrl.stream;
//       case ParcelStatus.inTransit:
//         return _inTransitCtrl.stream;
//       case ParcelStatus.delivered:
//         return _deliveredCtrl.stream;
//     }
//   }

//   void _emitStreams() {
//     final all = _byId.values.toList();
//     _queuedCtrl.add(
//         all.where((p) => p.status == ParcelStatus.queued).toList());
//     _inTransitCtrl.add(
//         all.where((p) => p.status == ParcelStatus.inTransit).toList());
//     _deliveredCtrl.add(
//         all.where((p) => p.status == ParcelStatus.delivered).toList());
//   }

//   // ========= INIT / CONNECT =========

//   Future<void> init() async {
//     if (_mqttConnected) {
//       print('[ParcelService] MQTT already connected, skip init().');
//       return;
//     }
//     await _connectMqtt();
//   }

//   Future<void> _connectMqtt() async {
//     print(
//         '[ParcelService] Connecting to EMQX at $_mqttHost:$_mqttPort (TLS) ...');

//     // Simplest possible client setup for EMQX
//     _mqttClient =
//         MqttServerClient.withPort(_mqttHost, _mqttClientId, _mqttPort);

//     _mqttClient
//       ..logging(on: true)
//       ..keepAlivePeriod = 30
//       ..secure = true
//       ..onDisconnected = _onDisconnected
//       ..autoReconnect = true;

//     // WARNING: this accepts any TLS cert (dev only)
//     _mqttClient.onBadCertificate = (dynamic cert) {
//       print(
//           '[ParcelService] WARNING: accepting bad TLS certificate (DEV ONLY).');
//       return true;
//     };

//     // Use MQTT 3.1.1
//     _mqttClient.setProtocolV311();

//     final connMsg = MqttConnectMessage()
//         .withClientIdentifier(_mqttClientId)
//         .authenticateAs(_mqttUsername, _mqttPassword)
//         .startClean()
//         .withWillQos(MqttQos.atLeastOnce);

//     _mqttClient.connectionMessage = connMsg;

//     try {
//       final connResult = await _mqttClient.connect();
//       print(
//           '[ParcelService] MQTT connect result: ${connResult?.state} / ${_mqttClient.connectionStatus?.state}');

//       _mqttConnected =
//           _mqttClient.connectionStatus?.state ==
//               MqttConnectionState.connected;

//       if (_mqttConnected) {
//         print('[ParcelService] MQTT connected, subscribing to topics...');
//         _subscribeTopics();
//       } else {
//         print(
//             '[ParcelService] MQTT connection FAILED, status=${_mqttClient.connectionStatus}');
//         _mqttClient.disconnect();
//       }
//     } catch (e) {
//       _mqttConnected = false;
//       print('[ParcelService] MQTT exception during connect: $e');
//       _mqttClient.disconnect();
//     }
//   }

//   void _onDisconnected() {
//     _mqttConnected = false;
//     print('[ParcelService] MQTT disconnected.');
//   }

//   // ========= SUBSCRIBE (MQTT → in-memory store) =========

//   void _subscribeTopics() {
//     print('[ParcelService] Subscribing to $_topicNewParcel and $_topicStatus');

//     final sub1 = _mqttClient.subscribe(_topicNewParcel, MqttQos.atLeastOnce);
//     final sub2 = _mqttClient.subscribe(_topicStatus, MqttQos.atLeastOnce);

//     print('[ParcelService] subscribe() results: '
//         '$_topicNewParcel -> $sub1, $_topicStatus -> $sub2');

//     _mqttClient.updates?.listen((events) {
//       print(
//           '[ParcelService] _mqttClient.updates fired, events.length=${events.length}');
//       if (events.isEmpty) return;

//       for (final rec in events) {
//         final topic = rec.topic;
//         final msg = rec.payload as MqttPublishMessage;
//         final payloadString =
//             MqttPublishPayload.bytesToStringAsString(msg.payload.message);

//         print('[ParcelService] MQTT message on "$topic": $payloadString');
//         _handleMqttMessage(topic, payloadString);
//       }
//     }, onError: (err) {
//       print('[ParcelService] ERROR in _mqttClient.updates stream: $err');
//     }, onDone: () {
//       print('[ParcelService] _mqttClient.updates stream DONE.');
//     });
//   }

//   Future<void> _handleMqttMessage(String topic, String payload) async {
//     print(
//         '[ParcelService] _handleMqttMessage(topic=$topic, payload=$payload)');

//     Map<String, dynamic>? data;
//     try {
//       final decoded = jsonDecode(payload);
//       if (decoded is Map<String, dynamic>) {
//         data = decoded;
//       }
//     } catch (_) {
//       print(
//           '[ParcelService] Payload is not valid JSON, will treat as raw if needed.');
//     }

//     if (topic == _topicNewParcel) {
//       if (data != null) {
//         print('[ParcelService] Handling NEW PARCEL event with JSON: $data');
//         await _handleNewParcelEvent(data);
//       } else {
//         final map = {'rfidTag': payload.trim()};
//         print(
//             '[ParcelService] Handling NEW PARCEL event with raw payload -> $map');
//         await _handleNewParcelEvent(map);
//       }
//     } else if (topic == _topicStatus) {
//       if (data != null) {
//         print('[ParcelService] Handling STATUS event with JSON: $data');
//         await _handleStatusEvent(data);
//       } else {
//         print('[ParcelService] Ignoring non-JSON status payload: $payload');
//       }
//     } else {
//       print('[ParcelService] Received message on unexpected topic: $topic');
//     }
//   }

//   // ========= PUBLISH (APP → MQTT) =========

//   void _publishParcelUpdate(Parcel parcel) {
//     if (!_mqttConnected) {
//       print('[ParcelService] _publishParcelUpdate: MQTT not connected, skip.');
//       return;
//     }

//     final payload = jsonEncode(
//       parcel.toJson()..addAll({'id': parcel.id}),
//     );

//     final builder = MqttClientPayloadBuilder()..addUTF8String(payload);

//     print(
//         '[ParcelService] Publishing parcel update on $_mqttTopicParcels: $payload');

//     _mqttClient.publishMessage(
//       _mqttTopicParcels,
//       MqttQos.atLeastOnce,
//       builder.payload!,
//       retain: false,
//     );
//   }

//   Future<void> publishStopCommand() async {
//     if (!_mqttConnected) {
//       print('[ParcelService] publishStopCommand: MQTT not connected, skip.');
//       return;
//     }

//     final payload = jsonEncode({'command': 'STOP'});
//     final builder = MqttClientPayloadBuilder()..addUTF8String(payload);

//     print('[ParcelService] Publishing STOP command on $_topicCmd: $payload');

//     _mqttClient.publishMessage(
//       _topicCmd,
//       MqttQos.atLeastOnce,
//       builder.payload!,
//       retain: false,
//     );
//   }

//   // ========= App-side helpers to manipulate in-memory parcels =========

//   Future<void> onRfidScanned(String rfidTag) async {
//     final now = DateTime.now();
//     print('[ParcelService] onRfidScanned($rfidTag)');

//     final existingId = _idByTag[rfidTag];

//     if (existingId == null) {
//       final id = now.microsecondsSinceEpoch.toString();
//       final parcel = Parcel(
//         id: id,
//         rfidTag: rfidTag,
//         status: ParcelStatus.queued,
//         createdAt: now,
//         updatedAt: now,
//       );
//       _byId[id] = parcel;
//       _idByTag[rfidTag] = id;

//       print(
//           '[ParcelService] Created NEW parcel id=$id for rfidTag=$rfidTag');

//       _publishParcelUpdate(parcel);
//     } else {
//       final parcel = _byId[existingId];
//       if (parcel != null) {
//         final updated = parcel.copyWith(
//           status: ParcelStatus.queued,
//           updatedAt: now,
//         );
//         _byId[existingId] = updated;

//         print(
//             '[ParcelService] Updated EXISTING parcel id=$existingId to queued for rfidTag=$rfidTag');

//         _publishParcelUpdate(updated);
//       } else {
//         print(
//             '[ParcelService] WARNING: _idByTag had id=$existingId but _byId has no entry.');
//       }
//     }

//     _emitStreams();
//   }

//   Future<void> markInTransit(String parcelId) async {
//     final parcel = _byId[parcelId];
//     if (parcel == null) {
//       print('[ParcelService] markInTransit: parcelId=$parcelId not found.');
//       return;
//     }

//     final now = DateTime.now();
//     final updated = parcel.copyWith(
//       status: ParcelStatus.inTransit,
//       updatedAt: now,
//     );
//     _byId[parcelId] = updated;

//     print('[ParcelService] markInTransit: parcelId=$parcelId');

//     _publishParcelUpdate(updated);
//     _emitStreams();
//   }

//   Future<void> markDelivered(String parcelId) async {
//     final parcel = _byId[parcelId];
//     if (parcel == null) {
//       print('[ParcelService] markDelivered: parcelId=$parcelId not found.');
//       return;
//     }

//     final now = DateTime.now();
//     final updated = parcel.copyWith(
//       status: ParcelStatus.delivered,
//       updatedAt: now,
//     );
//     _byId[parcelId] = updated;

//     print('[ParcelService] markDelivered: parcelId=$parcelId');

//     _publishParcelUpdate(updated);
//     _emitStreams();
//   }

//   Future<void> dispose() async {
//     print('[ParcelService] dispose() called.');
//     await _queuedCtrl.close();
//     await _inTransitCtrl.close();
//     await _deliveredCtrl.close();
//     if (_mqttConnected) {
//       _mqttClient.disconnect();
//     }
//   }
// }



// // lib/services/parcel_service.dart
//
// import 'dart:async';
// import 'dart:convert';
//
// import 'package:mqtt_client/mqtt_client.dart';
// import 'package:mqtt_client/mqtt_server_client.dart';
//
// import '../models/parcel_model.dart';
//
// /// Service responsible for:
// /// - connecting to MQTT
// /// - mirroring parcel state (queued / inTransit / delivered) in memory
// /// - exposing streams for the dashboard UI
// /// - reacting to robot/RFID/status topics
// class ParcelService {
//   ParcelService._private();
//   static final ParcelService instance = ParcelService._private();
//
//   // ========= MQTT CONFIG – TELEMETRY ONLY =========
//
//   static const String _mqttHost = 'r38d6e25.ala.us-east-1.emqxsl.com';
//
//   // For debugging: use 1883 + secure=false.
//   // Once confirmed, you can move back to 8883 + TLS with proper certs.
//   static const int _mqttPort = 8883;
//
//   static const String _mqttClientId = 'esp32-rfid-1';
//   static const String _mqttUsername = 'parcel2';
//   static const String _mqttPassword = 'password';
//
//   // Topic for app → robot parcel updates
//   static const String _mqttTopicParcels = 'parcel/db/update';
//
//   // Robot → app events
//   static const String _topicNewParcel = 'parcel/events'; // RFID events
//   static const String _topicStatus = 'parcel/status';    // IMU / status updates
//
//   // App → robot commands
//   static const String _topicCmd = 'parcel/cmd';
//
//   late MqttServerClient _mqttClient;
//   bool _mqttConnected = false;
//
//   // ========= In-memory parcel store =========
//
//   final Map<String, Parcel> _byId = {};        // local ID → Parcel
//   final Map<String, String> _idByTag = {};     // rfidTag → local ID
//
//   // Streams per status for the UI.
//   final _queuedCtrl = StreamController<List<Parcel>>.broadcast();
//   final _inTransitCtrl = StreamController<List<Parcel>>.broadcast();
//   final _deliveredCtrl = StreamController<List<Parcel>>.broadcast();
//
//   /// Expose parcels as a stream filtered by status.
//   Stream<List<Parcel>> streamByStatus(ParcelStatus status) {
//     switch (status) {
//       case ParcelStatus.queued:
//         return _queuedCtrl.stream;
//       case ParcelStatus.inTransit:
//         return _inTransitCtrl.stream;
//       case ParcelStatus.delivered:
//         return _deliveredCtrl.stream;
//     }
//   }
//
//   /// Recompute and emit parcel lists whenever something changes.
//   void _emitStreams() {
//     final all = _byId.values.toList();
//     _queuedCtrl.add(
//       all.where((p) => p.status == ParcelStatus.queued).toList(),
//     );
//     _inTransitCtrl.add(
//       all.where((p) => p.status == ParcelStatus.inTransit).toList(),
//     );
//     _deliveredCtrl.add(
//       all.where((p) => p.status == ParcelStatus.delivered).toList(),
//     );
//   }
//
//   // ========= INIT / CONNECT =========
//
//   /// TELEMETRY INIT – call once (e.g. from Dashboard.initState) to connect to MQTT.
//   Future<void> init() async {
//     if (_mqttConnected) {
//       // ignore: avoid_print
//       print('[ParcelService] MQTT already connected, skip init().');
//       return;
//     }
//     await _connectMqtt();
//   }
//
//   Future<void> _connectMqtt() async {
//     // ignore: avoid_print
//     print('[ParcelService] Connecting to MQTT at $_mqttHost:$_mqttPort ...');
//
//     _mqttClient = MqttServerClient(_mqttHost, _mqttClientId)
//       ..port = _mqttPort
//       ..logging(on: true)      // enable during debugging
//       ..keepAlivePeriod = 30
//       ..secure = true         // because we’re using 1883 here
//       ..onDisconnected = _onDisconnected;
//
//     var msg = MqttConnectMessage()
//         .withClientIdentifier(_mqttClientId)
//         .startClean()
//         .withWillQos(MqttQos.atLeastOnce);
//
//     if (_mqttUsername.isNotEmpty) {
//       msg = msg.authenticateAs(_mqttUsername, _mqttPassword);
//     }
//
//     _mqttClient.connectionMessage = msg;
//
//     try {
//       final connResult = await _mqttClient.connect();
//       // ignore: avoid_print
//       print('[ParcelService] MQTT connect result: ${connResult?.state}');
//
//       _mqttConnected =
//           connResult?.state == MqttConnectionState.connected;
//
//       if (_mqttConnected) {
//         // ignore: avoid_print
//         print('[ParcelService] MQTT connected, subscribing to telemetry topics...');
//         _subscribeTopics();
//       } else {
//         // ignore: avoid_print
//         print('[ParcelService] MQTT connection FAILED, disconnecting.');
//         _mqttClient.disconnect();
//       }
//     } catch (e) {
//       _mqttConnected = false;
//       // ignore: avoid_print
//       print('[ParcelService] MQTT exception during connect: $e');
//       _mqttClient.disconnect();
//     }
//   }
//
//   void _onDisconnected() {
//     _mqttConnected = false;
//     // ignore: avoid_print
//     print('[ParcelService] MQTT disconnected.');
//   }
//
//   // ========= SUBSCRIBE (MQTT → in-memory store) =========
//
//   void _subscribeTopics() {
//     // ignore: avoid_print
//     print('[ParcelService] Subscribing to $_topicNewParcel and $_topicStatus');
//
//     _mqttClient.subscribe(_topicNewParcel, MqttQos.atLeastOnce);
//     _mqttClient.subscribe(_topicStatus, MqttQos.atLeastOnce);
//
//     _mqttClient.updates?.listen((events) {
//       if (events.isEmpty) return;
//
//       final rec = events.first;
//       final topic = rec.topic;
//       final msg = rec.payload as MqttPublishMessage;
//       final payloadString =
//       MqttPublishPayload.bytesToStringAsString(msg.payload.message);
//
//       // ignore: avoid_print
//       print('[ParcelService] MQTT message on "$topic": $payloadString');
//
//       _handleMqttMessage(topic, payloadString);
//     });
//   }
//
//   Future<void> _handleMqttMessage(String topic, String payload) async {
//     Map<String, dynamic>? data;
//     try {
//       final decoded = jsonDecode(payload);
//       if (decoded is Map<String, dynamic>) {
//         data = decoded;
//       }
//     } catch (_) {
//       // non-JSON is handled below
//     }
//
//     if (topic == _topicNewParcel) {
//       if (data != null) {
//         await _handleNewParcelEvent(data);
//       } else {
//         await _handleNewParcelEvent({'rfidTag': payload.trim()});
//       }
//     } else if (topic == _topicStatus) {
//       if (data != null) {
//         await _handleStatusEvent(data);
//       } else {
//         // ignore: avoid_print
//         print('[ParcelService] Ignoring non-JSON status payload: $payload');
//       }
//     }
//   }
//
//   /// Handle an incoming RFID event (new parcel).
//   Future<void> _handleNewParcelEvent(Map<String, dynamic> data) async {
//     final rfidTag = data['rfidTag'] as String?;
//     if (rfidTag == null || rfidTag.isEmpty) {
//       // ignore: avoid_print
//       print('[ParcelService] Missing rfidTag in new-parcel payload: $data');
//       return;
//     }
//
//     await onRfidScanned(rfidTag);
//   }
//
//   /// Handle an incoming status event from the robot/IMU.
//   /// Payload examples:
//   ///   { "rfidTag": "ABC123", "status": "inTransit" }
//   ///   { "id": "LOCAL_ID",   "status": "delivered" }
//   Future<void> _handleStatusEvent(Map<String, dynamic> data) async {
//     final newStatusStr = data['status'] as String?;
//     if (newStatusStr == null) {
//       // ignore: avoid_print
//       print('[ParcelService] Missing status in status payload: $data');
//       return;
//     }
//
//     final newStatus = parcelStatusFromString(newStatusStr);
//     String? id = data['id'] as String?;
//
//     if (id == null && data['rfidTag'] != null) {
//       final tag = data['rfidTag'] as String;
//       id = _idByTag[tag];
//       if (id == null) {
//         // We don't know this parcel yet; create it and apply status.
//         await onRfidScanned(tag);
//         id = _idByTag[tag];
//       }
//     }
//
//     if (id == null) {
//       // ignore: avoid_print
//       print('[ParcelService] No parcel found for payload: $data');
//       return;
//     }
//
//     switch (newStatus) {
//       case ParcelStatus.queued:
//         await onRfidScanned(data['rfidTag'] as String? ?? '');
//         break;
//       case ParcelStatus.inTransit:
//         await markInTransit(id);
//         break;
//       case ParcelStatus.delivered:
//         await markDelivered(id);
//         break;
//     }
//
//     // ignore: avoid_print
//     print('[ParcelService] Updated parcel status to $newStatusStr for id $id');
//   }
//
//   // ========= PUBLISH (APP → MQTT) =========
//
//   void _publishParcelUpdate(Parcel parcel) {
//     if (!_mqttConnected) return;
//
//     final payload = jsonEncode(
//       parcel.toJson()..addAll({'id': parcel.id}),
//     );
//
//     final builder = MqttClientPayloadBuilder()..addUTF8String(payload);
//
//     _mqttClient.publishMessage(
//       _mqttTopicParcels,
//       MqttQos.atLeastOnce,
//       builder.payload!,
//       retain: false,
//     );
//   }
//
//   /// Public command: ask robot to stop moving.
//   Future<void> publishStopCommand() async {
//     if (!_mqttConnected) return;
//
//     final builder = MqttClientPayloadBuilder()
//       ..addUTF8String(jsonEncode({'command': 'STOP'}));
//
//     _mqttClient.publishMessage(
//       _topicCmd,
//       MqttQos.atLeastOnce,
//       builder.payload!,
//       retain: false,
//     );
//   }
//
//   // ========= App-side helpers to manipulate in-memory parcels =========
//
//   /// Called when a new RFID tag is scanned (either from MQTT or manually).
//   Future<void> onRfidScanned(String rfidTag) async {
//     final now = DateTime.now();
//
//     // Check if we already have a parcel for this tag.
//     final existingId = _idByTag[rfidTag];
//
//     if (existingId == null) {
//       // Create a new parcel with a local ID.
//       final id = now.microsecondsSinceEpoch.toString();
//       final parcel = Parcel(
//         id: id,
//         rfidTag: rfidTag,
//         status: ParcelStatus.queued,
//         createdAt: now,
//         updatedAt: now,
//       );
//       _byId[id] = parcel;
//       _idByTag[rfidTag] = id;
//       _publishParcelUpdate(parcel);
//     } else {
//       // Reset status to queued for existing parcel.
//       final parcel = _byId[existingId];
//       if (parcel != null) {
//         final updated = parcel.copyWith(
//           status: ParcelStatus.queued,
//           updatedAt: now,
//         );
//         _byId[existingId] = updated;
//         _publishParcelUpdate(updated);
//       }
//     }
//
//     _emitStreams();
//   }
//
//   Future<void> markInTransit(String parcelId) async {
//     final parcel = _byId[parcelId];
//     if (parcel == null) return;
//
//     final now = DateTime.now();
//     final updated = parcel.copyWith(
//       status: ParcelStatus.inTransit,
//       updatedAt: now,
//     );
//     _byId[parcelId] = updated;
//     _publishParcelUpdate(updated);
//     _emitStreams();
//   }
//
//   Future<void> markDelivered(String parcelId) async {
//     final parcel = _byId[parcelId];
//     if (parcel == null) return;
//
//     final now = DateTime.now();
//     final updated = parcel.copyWith(
//       status: ParcelStatus.delivered,
//       updatedAt: now,
//     );
//     _byId[parcelId] = updated;
//     _publishParcelUpdate(updated);
//     _emitStreams();
//   }
//
//   /// Dispose everything when the app shuts down (optional).
//   Future<void> dispose() async {
//     await _queuedCtrl.close();
//     await _inTransitCtrl.close();
//     await _deliveredCtrl.close();
//     if (_mqttConnected) {
//       _mqttClient.disconnect();
//     }
//   }
// }
//
// // // lib/services/parcel_service.dart
// //
// // import 'dart:async';
// // import 'dart:convert';
// //
// // import 'package:mqtt_client/mqtt_client.dart';
// // import 'package:mqtt_client/mqtt_server_client.dart';
// //
// // import '../models/parcel_model.dart';
// //
// // /// Service responsible for:
// // /// - connecting to MQTT
// // /// - mirroring parcel state (queued / inTransit / delivered) in memory
// // /// - exposing streams for the dashboard UI
// // /// - reacting to robot/RFID/status topics
// // class ParcelService {
// //   ParcelService._private();
// //   static final ParcelService instance = ParcelService._private();
// //
// //   // ========= MQTT CONFIG – TELEMETRY ONLY =========
// //
// //   static const String _mqttHost = 'r38d6e25.ala.us-east-1.emqxsl.com';
// //
// //   // For debugging: use 1883 + secure=false
// //   // Once confirmed, you can move back to 8883 + TLS.
// //   static const int _mqttPort = 8883;
// //
// //   static const String _mqttClientId = 'esp32-rfid-1';
// //   static const String _mqttUsername = 'parcel2';
// //   static const String _mqttPassword = 'password';
// //
// //   static const String _mqttTopicParcels = 'parcel/db/update';
// //   static const String _topicNewParcel   = 'parcel/events';
// //   static const String _topicStatus      = 'parcel/status';
// //   static const String _topicCmd         = 'parcel/cmd';
// //
// //   late final MqttServerClient _mqttClient;
// //   bool _mqttConnected = false;
// //
// //   // ... maps + stream controllers unchanged ...
// //
// //   /// TELEMETRY INIT – call once from Dashboard.initState
// //   Future<void> init() async {
// //     if (_mqttConnected) {
// //       // ignore: avoid_print
// //       print('[ParcelService] MQTT already connected, skip init().');
// //       return;
// //     }
// //     await _connectMqtt();
// //   }
// //
// //   Future<void> _connectMqtt() async {
// //     // ignore: avoid_print
// //     print('[ParcelService] Connecting to MQTT at $_mqttHost:$_mqttPort ...');
// //
// //     _mqttClient = MqttServerClient(_mqttHost, _mqttClientId)
// //       ..port = _mqttPort
// //       ..logging(on: true)      // enable during debugging
// //       ..keepAlivePeriod = 30
// //       ..secure = false         // because we’re using 1883 here
// //       ..onDisconnected = _onDisconnected;
// //
// //     var msg = MqttConnectMessage()
// //         .withClientIdentifier(_mqttClientId)
// //         .startClean()
// //         .withWillQos(MqttQos.atLeastOnce);
// //
// //     if (_mqttUsername.isNotEmpty) {
// //       msg = msg.authenticateAs(_mqttUsername, _mqttPassword);
// //     }
// //
// //     _mqttClient.connectionMessage = msg;
// //
// //     try {
// //       final connResult = await _mqttClient.connect();
// //       // ignore: avoid_print
// //       print('[ParcelService] MQTT connect result: ${connResult?.state}');
// //
// //       _mqttConnected =
// //           connResult?.state == MqttConnectionState.connected;
// //
// //       if (_mqttConnected) {
// //         // ignore: avoid_print
// //         print('[ParcelService] MQTT connected, subscribing to telemetry topics...');
// //         _subscribeTopics();
// //       } else {
// //         // ignore: avoid_print
// //         print('[ParcelService] MQTT connection FAILED, disconnecting.');
// //         _mqttClient.disconnect();
// //       }
// //     } catch (e) {
// //       _mqttConnected = false;
// //       // ignore: avoid_print
// //       print('[ParcelService] MQTT exception during connect: $e');
// //       _mqttClient.disconnect();
// //     }
// //   }
// //
// //   void _onDisconnected() {
// //     _mqttConnected = false;
// //     // ignore: avoid_print
// //     print('[ParcelService] MQTT disconnected.');
// //   }
// //
// //   void _subscribeTopics() {
// //     // ignore: avoid_print
// //     print('[ParcelService] Subscribing to $_topicNewParcel and $_topicStatus');
// //
// //     _mqttClient.subscribe(_topicNewParcel, MqttQos.atLeastOnce);
// //     _mqttClient.subscribe(_topicStatus, MqttQos.atLeastOnce);
// //
// //     _mqttClient.updates?.listen((events) {
// //       if (events.isEmpty) return;
// //
// //       final rec = events.first;
// //       final topic = rec.topic;
// //       final msg = rec.payload as MqttPublishMessage;
// //       final payloadString =
// //       MqttPublishPayload.bytesToStringAsString(msg.payload.message);
// //
// //       // ignore: avoid_print
// //       print('[ParcelService] MQTT message on "$topic": $payloadString');
// //
// //       _handleMqttMessage(topic, payloadString);
// //     });
// //   }
// //   // ParcelService._private();
// //   // static final ParcelService instance = ParcelService._private();
// //   //
// //   // // ========= MQTT CONFIG – FILL WITH YOUR EMQX CLOUD VALUES =========
// //   //
// //   // static const String _mqttHost = 'r38d6e25.ala.us-east-1.emqxsl.com';
// //   // static const int _mqttPort = 8883;
// //   // static const String _mqttClientId = 'esp32-rfid-1';
// //   //
// //   // static const String _mqttUsername = 'parcel2';
// //   // static const String _mqttPassword = 'password';
// //   //
// //   // // Topic for app → robot parcel updates
// //   // static const String _mqttTopicParcels = 'parcel/db/update';
// //   //
// //   // // Robot → app events
// //   // static const String _topicNewParcel = 'parcel/events'; // RFID events
// //   // static const String _topicStatus = 'parcel/status'; // IMU / status updates
// //   //
// //   // // App → robot commands
// //   // static const String _topicCmd = 'parcel/cmd';
// //   //
// //   // late final MqttServerClient _mqttClient;
// //   // bool _mqttConnected = false;
// //   //
// //   // // ========= In-memory parcel store =========
// //   //
// //   // final Map<String, Parcel> _byId = {};        // local ID → Parcel
// //   // final Map<String, String> _idByTag = {};     // rfidTag → local ID
// //   //
// //   // // Streams per status for the UI.
// //   // final _queuedCtrl = StreamController<List<Parcel>>.broadcast();
// //   // final _inTransitCtrl = StreamController<List<Parcel>>.broadcast();
// //   // final _deliveredCtrl = StreamController<List<Parcel>>.broadcast();
// //   //
// //   // /// Expose parcels as a stream filtered by status.
// //   // Stream<List<Parcel>> streamByStatus(ParcelStatus status) {
// //   //   switch (status) {
// //   //     case ParcelStatus.queued:
// //   //       return _queuedCtrl.stream;
// //   //     case ParcelStatus.inTransit:
// //   //       return _inTransitCtrl.stream;
// //   //     case ParcelStatus.delivered:
// //   //       return _deliveredCtrl.stream;
// //   //   }
// //   // }
// //   //
// //   // /// Recompute and emit parcel lists whenever something changes.
// //   // void _emitStreams() {
// //   //   final all = _byId.values.toList();
// //   //   _queuedCtrl.add(
// //   //     all.where((p) => p.status == ParcelStatus.queued).toList(),
// //   //   );
// //   //   _inTransitCtrl.add(
// //   //     all.where((p) => p.status == ParcelStatus.inTransit).toList(),
// //   //   );
// //   //   _deliveredCtrl.add(
// //   //     all.where((p) => p.status == ParcelStatus.delivered).toList(),
// //   //   );
// //   // }
// //   //
// //   // // ========= INIT / CONNECT =========
// //   //
// //   // /// Call once (e.g. from Dashboard initState) to connect to MQTT.
// //   // Future<void> init() async {
// //   //   await _connectMqtt();
// //   // }
// //   //
// //   // Future<void> _connectMqtt() async {
// //   //   _mqttClient = MqttServerClient(_mqttHost, _mqttClientId)
// //   //     ..port = _mqttPort
// //   //     ..logging(on: false)
// //   //     ..keepAlivePeriod = 30
// //   //     ..secure = false // set true + TLS setup if you really use 8883/TLS
// //   //     ..onDisconnected = _onDisconnected;
// //   //
// //   //   var msg = MqttConnectMessage()
// //   //       .withClientIdentifier(_mqttClientId)
// //   //       .startClean()
// //   //       .withWillQos(MqttQos.atLeastOnce);
// //   //
// //   //   if (_mqttUsername.isNotEmpty) {
// //   //     msg = msg.authenticateAs(_mqttUsername, _mqttPassword);
// //   //   }
// //   //
// //   //   _mqttClient.connectionMessage = msg;
// //   //
// //   //   try {
// //   //     final connResult = await _mqttClient.connect();
// //   //     _mqttConnected = connResult?.state == MqttConnectionState.connected;
// //   //
// //   //     if (_mqttConnected) {
// //   //       _subscribeTopics(); // listen to robot / RFID messages
// //   //     }
// //   //   } catch (e) {
// //   //     _mqttConnected = false;
// //   //     _mqttClient.disconnect();
// //   //   }
// //   // }
// //   //
// //   // void _onDisconnected() {
// //   //   _mqttConnected = false;
// //   // }
// //   //
// //   // // ========= PUBLISH (APP → MQTT) =========
// //   //
// //   // void _publishParcelUpdate(Parcel parcel) {
// //   //   if (!_mqttConnected) return;
// //   //
// //   //   final payload = jsonEncode(
// //   //     parcel.toJson()..addAll({'id': parcel.id}),
// //   //   );
// //   //
// //   //   final builder = MqttClientPayloadBuilder()..addUTF8String(payload);
// //   //
// //   //   _mqttClient.publishMessage(
// //   //     _mqttTopicParcels,
// //   //     MqttQos.atLeastOnce,
// //   //     builder.payload!,
// //   //     retain: false,
// //   //   );
// //   // }
// //   //
// //   // /// Public command: ask robot to stop moving.
// //   // Future<void> publishStopCommand() async {
// //   //   if (!_mqttConnected) return;
// //   //
// //   //   final builder = MqttClientPayloadBuilder()
// //   //     ..addUTF8String(jsonEncode({'command': 'STOP'}));
// //   //
// //   //   _mqttClient.publishMessage(
// //   //     _topicCmd,
// //   //     MqttQos.atLeastOnce,
// //   //     builder.payload!,
// //   //     retain: false,
// //   //   );
// //   // }
// //   //
// //   // // ========= App-side helpers to manipulate in-memory parcels =========
// //   //
// //   // /// Called when a new RFID tag is scanned (either from MQTT or manually).
// //   // Future<void> onRfidScanned(String rfidTag) async {
// //   //   final now = DateTime.now();
// //   //
// //   //   // Check if we already have a parcel for this tag.
// //   //   final existingId = _idByTag[rfidTag];
// //   //
// //   //   if (existingId == null) {
// //   //     // Create a new parcel with a local ID.
// //   //     final id = now.microsecondsSinceEpoch.toString();
// //   //     final parcel = Parcel(
// //   //       id: id,
// //   //       rfidTag: rfidTag,
// //   //       status: ParcelStatus.queued,
// //   //       createdAt: now,
// //   //       updatedAt: now,
// //   //     );
// //   //     _byId[id] = parcel;
// //   //     _idByTag[rfidTag] = id;
// //   //     _publishParcelUpdate(parcel);
// //   //   } else {
// //   //     // Reset status to queued for existing parcel.
// //   //     final parcel = _byId[existingId];
// //   //     if (parcel != null) {
// //   //       final updated = parcel.copyWith(
// //   //         status: ParcelStatus.queued,
// //   //         updatedAt: now,
// //   //       );
// //   //       _byId[existingId] = updated;
// //   //       _publishParcelUpdate(updated);
// //   //     }
// //   //   }
// //   //
// //   //   _emitStreams();
// //   // }
// //   //
// //   // Future<void> markInTransit(String parcelId) async {
// //   //   final parcel = _byId[parcelId];
// //   //   if (parcel == null) return;
// //   //
// //   //   final now = DateTime.now();
// //   //   final updated = parcel.copyWith(
// //   //     status: ParcelStatus.inTransit,
// //   //     updatedAt: now,
// //   //   );
// //   //   _byId[parcelId] = updated;
// //   //   _publishParcelUpdate(updated);
// //   //   _emitStreams();
// //   // }
// //   //
// //   // Future<void> markDelivered(String parcelId) async {
// //   //   final parcel = _byId[parcelId];
// //   //   if (parcel == null) return;
// //   //
// //   //   final now = DateTime.now();
// //   //   final updated = parcel.copyWith(
// //   //     status: ParcelStatus.delivered,
// //   //     updatedAt: now,
// //   //   );
// //   //   _byId[parcelId] = updated;
// //   //   _publishParcelUpdate(updated);
// //   //   _emitStreams();
// //   // }
// //   //
// //   // // ========= SUBSCRIBE (MQTT → in-memory store) =========
// //   //
// //   // void _subscribeTopics() {
// //   //   _mqttClient.subscribe(_topicNewParcel, MqttQos.atLeastOnce);
// //   //   _mqttClient.subscribe(_topicStatus, MqttQos.atLeastOnce);
// //   //
// //   //   _mqttClient.updates?.listen((events) {
// //   //     if (events.isEmpty) return;
// //   //
// //   //     final rec = events.first;
// //   //     final topic = rec.topic;
// //   //     final msg = rec.payload as MqttPublishMessage;
// //   //     final payloadString =
// //   //     MqttPublishPayload.bytesToStringAsString(msg.payload.message);
// //   //
// //   //     // ignore: avoid_print
// //   //     print('[ParcelService] MQTT message on "$topic": $payloadString');
// //   //
// //   //     _handleMqttMessage(topic, payloadString);
// //   //   });
// //   // }
// //
// //   Future<void> _handleMqttMessage(String topic, String payload) async {
// //     Map<String, dynamic>? data;
// //     try {
// //       final decoded = jsonDecode(payload);
// //       if (decoded is Map<String, dynamic>) {
// //         data = decoded;
// //       }
// //     } catch (_) {
// //       // non-JSON is handled below
// //     }
// //
// //     if (topic == _topicNewParcel) {
// //       if (data != null) {
// //         await _handleNewParcelEvent(data);
// //       } else {
// //         await _handleNewParcelEvent({'rfidTag': payload.trim()});
// //       }
// //     } else if (topic == _topicStatus) {
// //       if (data != null) {
// //         await _handleStatusEvent(data);
// //       } else {
// //         // ignore: avoid_print
// //         print('[ParcelService] Ignoring non-JSON status payload: $payload');
// //       }
// //     }
// //   }
// //
// //   /// Handle an incoming RFID event (new parcel).
// //   Future<void> _handleNewParcelEvent(Map<String, dynamic> data) async {
// //     final rfidTag = data['rfidTag'] as String?;
// //     if (rfidTag == null || rfidTag.isEmpty) {
// //       // ignore: avoid_print
// //       print('[ParcelService] Missing rfidTag in new-parcel payload: $data');
// //       return;
// //     }
// //
// //     await onRfidScanned(rfidTag);
// //   }
// //
// //   /// Handle an incoming status event from the robot/IMU.
// //   /// Payload examples:
// //   ///   { "rfidTag": "ABC123", "status": "inTransit" }
// //   ///   { "id": "LOCAL_ID",   "status": "delivered" }
// //   Future<void> _handleStatusEvent(Map<String, dynamic> data) async {
// //     final newStatusStr = data['status'] as String?;
// //     if (newStatusStr == null) {
// //       // ignore: avoid_print
// //       print('[ParcelService] Missing status in status payload: $data');
// //       return;
// //     }
// //
// //     final newStatus = parcelStatusFromString(newStatusStr);
// //     String? id = data['id'] as String?;
// //
// //     if (id == null && data['rfidTag'] != null) {
// //       final tag = data['rfidTag'] as String;
// //       id = _idByTag[tag];
// //       if (id == null) {
// //         // We don't know this parcel yet; create it and apply status.
// //         await onRfidScanned(tag);
// //         id = _idByTag[tag];
// //       }
// //     }
// //
// //     if (id == null) {
// //       // ignore: avoid_print
// //       print('[ParcelService] No parcel found for payload: $data');
// //       return;
// //     }
// //
// //     switch (newStatus) {
// //       case ParcelStatus.queued:
// //         await onRfidScanned(data['rfidTag'] as String? ?? '');
// //         break;
// //       case ParcelStatus.inTransit:
// //         await markInTransit(id);
// //         break;
// //       case ParcelStatus.delivered:
// //         await markDelivered(id);
// //         break;
// //     }
// //
// //     // ignore: avoid_print
// //     print('[ParcelService] Updated parcel status to $newStatusStr for id $id');
// //   }
// //
// //   /// Dispose everything when the app shuts down (optional).
// //   Future<void> dispose() async {
// //     _queuedCtrl.close();
// //     _inTransitCtrl.close();
// //     _deliveredCtrl.close();
// //     if (_mqttConnected) {
// //       _mqttClient.disconnect();
// //     }
// //   }
// // }
