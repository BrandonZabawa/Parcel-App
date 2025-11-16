// lib/pages/dashboard_page_route.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../routes.dart';

class DashboardPageRoute extends StatefulWidget {
  const DashboardPageRoute({super.key});

  @override
  State<DashboardPageRoute> createState() => _DashboardPageRouteState();
}

class _DashboardPageRouteState extends State<DashboardPageRoute> {
  // ---------- ESP32 mini-HTTP /packets ----------

  // IMPORTANT: includes http://
  static const String _espBaseUrl = 'http://172.20.10.2';

  bool _espLoading = false;
  String? _espError;
  List<Map<String, dynamic>> _espPackets = [];

  // ---------- Livestream / Livemap (Pi) ----------

  // Camera snapshots (MJPG-streamer or similar)
  final String _piStreamPath = '172.20.10.7:8080/?action=snapshot';

  // Live-Map images (fake_livemap_server.py or ESP32 map endpoint)
  // final String _piLiveMapPath = '172.20.10.7:8000/frame/next';
  final String _piLiveMapPath = '172.20.10.4:8000/frame/next';

  Timer? _refreshTimer;

  // ========= Lifecycle =========

  @override
  void initState() {
    super.initState();

    // Initial load from ESP32
    _fetchEspPackets();

    // Periodic refresh: packets + snapshots (cache-buster)
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      _fetchEspPackets();
      setState(() {
        // rebuild so snapshot/map URLs get new timestamps
      });
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // ========== HTTP: fetch /packets from ESP32 ==========

  Future<void> _fetchEspPackets() async {
    setState(() {
      _espLoading = true;
      _espError = null;
    });

    try {
      final uri = Uri.parse('$_espBaseUrl/packets');
      debugPrint('[_fetchEspPackets] >>> START GET $uri');

      final resp = await http.get(uri).timeout(const Duration(seconds: 3));

      debugPrint('[_fetchEspPackets] <<< STATUS: ${resp.statusCode}');
      debugPrint(
          '[_fetchEspPackets] <<< RAW BODY (${resp.body.length} chars):');
      debugPrint(resp.body);

      if (resp.statusCode != 200) {
        setState(() {
          _espError = 'HTTP error: ${resp.statusCode}';
          _espPackets = [];
        });
        debugPrint('[_fetchEspPackets] !!! NON-200 STATUS, aborting decode');
        return;
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(resp.body);
        debugPrint(
          '[_fetchEspPackets] decoded runtimeType = ${decoded.runtimeType}',
        );
      } catch (e, st) {
        debugPrint('[_fetchEspPackets] !!! jsonDecode FAILED: $e');
        debugPrint(st.toString());
        setState(() {
          _espError = 'JSON decode failed: $e';
          _espPackets = [];
        });
        return;
      }

      // Allow:
      //   1) [ { ... }, { ... } ]
      //   2) { "history": [ { ... } ] }
      //   3) single Map -> treat as 1 packet
      List<dynamic> rawList;
      if (decoded is List) {
        rawList = decoded;
        debugPrint(
            '[_fetchEspPackets] treating decoded as List, length=${rawList.length}');
      } else if (decoded is Map && decoded['history'] is List) {
        rawList = decoded['history'] as List;
        debugPrint(
            '[_fetchEspPackets] using decoded["history"] as List, length=${rawList.length}');
      } else if (decoded is Map) {
        debugPrint(
            '[_fetchEspPackets] treating single Map as one packet: $decoded');
        rawList = [decoded];
      } else {
        debugPrint(
          '[_fetchEspPackets] !!! Unexpected JSON shape: ${decoded.runtimeType}, content=$decoded',
        );
        setState(() {
          _espError = 'Unexpected JSON (not List or {history: [...]})';
          _espPackets = [];
        });
        return;
      }

      final packets = <Map<String, dynamic>>[];
      for (var i = 0; i < rawList.length; i++) {
        final e = rawList[i];
        if (e is Map) {
          final map = Map<String, dynamic>.from(e);
          debugPrint('[_fetchEspPackets] packet[$i] = $map');
          packets.add(map);
        } else {
          debugPrint(
            '[_fetchEspPackets] packet[$i] not Map (runtimeType=${e.runtimeType}), wrapping as {raw: ...}',
          );
          packets.add(<String, dynamic>{'raw': e.toString()});
        }
      }

      debugPrint('[_fetchEspPackets] FINAL packet count = ${packets.length}');

      setState(() {
        _espPackets = packets;
      });
    } catch (e, st) {
      debugPrint('[_fetchEspPackets] !!! REQUEST FAILED: $e');
      debugPrint(st.toString());
      setState(() {
        _espError = 'Request failed: $e';
        _espPackets = [];
      });
    } finally {
      if (mounted) {
        setState(() {
          _espLoading = false;
        });
        debugPrint(
            '[_fetchEspPackets] DONE. _espPackets.length=${_espPackets.length}, _espError=$_espError');
      }
    }
  }

  // ========== Livestream / Livemap helpers ==========

  String _buildSnapshotUrl() {
    final base = 'http://$_piStreamPath';
    final sep = base.contains('?') ? '&' : '?';
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '$base${sep}ts=$ts';
  }

  String _buildMapUrl() {
    final base = 'http://$_piLiveMapPath';
    final sep = base.contains('?') ? '&' : '?';
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '$base${sep}ts=$ts';
  }

  void _refreshStream() {
    setState(() {
      // Just forces rebuild; URLs get new ts
    });
  }

  void _signOut() {
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(PageRoutes.welcome);
  }

  // ========== UI ==========

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PARCEL Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // -------- LEFT: Packages card (HTTP from ESP32) --------
            SizedBox(
              width: 260,
              child: _buildPackagesCard(),
            ),

            // -------- CENTER: Livestream + Livemap --------
            Expanded(
              child: Column(
                children: [
                  // --- Livestream (camera snapshots) ---
                  Expanded(
                    flex: 4,
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: _roundedBoxDecoration(),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.videocam, size: 18),
                                const SizedBox(width: 8),
                                const Text(
                                  'Livestream (Camera Snapshots)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.refresh),
                                  onPressed: _refreshStream,
                                  tooltip: 'Refresh Snapshot',
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Card(
                              color: Colors.blue.shade50,
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Livestream base URL:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'http://$_piStreamPath',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: Card(
                                elevation: 2,
                                clipBehavior: Clip.antiAlias,
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.stretch,
                                  children: [
                                    Container(
                                      color: Colors.black12,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      child: const Row(
                                        children: [
                                          Icon(Icons.camera_alt, size: 18),
                                          SizedBox(width: 8),
                                          Text(
                                            'Livestream',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(child: _buildStream()),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // --- Livemap ---
                  Expanded(
                    flex: 3,
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: _roundedBoxDecoration(),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Card(
                          elevation: 2,
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                color: Colors.black12,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.map, size: 18),
                                    SizedBox(width: 8),
                                    Text(
                                      'Livemap',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  'Livemap base URL: http://$_piLiveMapPath',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              Expanded(child: _buildMapStream()),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- UI helpers ----------

  BoxDecoration _roundedBoxDecoration() {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.black54, width: 1.5),
    );
  }

  // --- Packages card using _espPackets from /packets ---
  Widget _buildPackagesCard() {
    debugPrint(
      '[_buildPackagesCard] BUILD: packets=${_espPackets.length}, error=$_espError',
    );

    final latest = _espPackets.isNotEmpty ? _espPackets.last : null;

    return Card(
      margin: const EdgeInsets.all(8),
      color: const Color(0xFFF7F3FF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.black87,
            child: const Text(
              'Packages',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),

          // Status / error row + first-packet debug
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (_espLoading)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(Icons.cloud_download, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _espError ??
                            (_espPackets.isEmpty
                                ? 'Waiting for parcels...'
                                : 'Packets: ${_espPackets.length}'
                                '${latest != null && latest["id"] != null ? " | Latest: ${latest["id"]}" : ""}'),
                        style: TextStyle(
                          fontSize: 11,
                          color: _espError == null
                              ? Colors.black87
                              : Colors.red,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      tooltip: 'Refresh from ESP32',
                      onPressed: _espLoading ? null : _fetchEspPackets,
                    ),
                  ],
                ),

                if (_espPackets.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'First packet raw: ${_espPackets.first}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: Colors.black54,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const Divider(height: 1),

          // Sequential list of messages
          Expanded(
            child: _espPackets.isEmpty
                ? const Center(
              child: Text(
                'Waiting for parcels...',
                style: TextStyle(fontSize: 12),
              ),
            )
                : ListView.builder(
              itemCount: _espPackets.length,
              itemBuilder: (context, index) {
                final packet = _espPackets[index];

                final id = packet['id']?.toString() ?? 'unknown';
                final msg = (packet['msg'] ??
                    packet['message'] ??
                    packet['status'] ??
                    packet['raw'] ??
                    packet.toString())
                    .toString();
                final ts = packet['timestamp']?.toString();

                return ListTile(
                  dense: true,
                  title: Text(
                    id,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    ts != null ? '$msg\n$ts' : msg,
                    style: const TextStyle(fontSize: 11),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Build the camera snapshot widget using Image.network.
  Widget _buildStream() {
    final streamUrl = _buildSnapshotUrl();

    return Image.network(
      streamUrl,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }
        return const Center(
          child: CircularProgressIndicator(),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline,
                    color: Colors.red, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'Cannot load camera snapshot',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'URL: $streamUrl',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Error: ${error.toString()}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Live-Map snapshot widget (fake images from Pi5).
  Widget _buildMapStream() {
    final streamUrl = _buildMapUrl();

    return Image.network(
      streamUrl,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }
        return const Center(
          child: CircularProgressIndicator(),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline,
                    color: Colors.red, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'Cannot load Live-Map snapshot',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'URL: $streamUrl',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Error: ${error.toString()}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// import 'dart:async';
// import 'dart:convert';
//
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;
//
// import '../routes.dart';
//
// class DashboardPageRoute extends StatefulWidget {
//   const DashboardPageRoute({super.key});
//
//   @override
//   State<DashboardPageRoute> createState() => _DashboardPageRouteState();
// }
//
// class _DashboardPageRouteState extends State<DashboardPageRoute> {
//   // ---------- ESP32 mini-HTTP /packets ----------
//
//   // IMPORTANT: includes http://
//   static const String _espBaseUrl = 'http://172.20.10.9';
//
//   bool _espLoading = false;
//   String? _espError;
//   List<Map<String, dynamic>> _espPackets = [];
//
//   // ---------- Livestream / Livemap (Pi) ----------
//
//   // Camera snapshots (MJPG-streamer or similar)
//   final String _piStreamPath = '172.20.10.7:8080/?action=snapshot';
//
//   // Live-Map images (fake_livemap_server.py or ESP32 map endpoint)
//   final String _piLiveMapPath = '172.20.10.7:8000/frame/next';
//
//   Timer? _refreshTimer;
//
//   // ========= Lifecycle =========
//
//   @override
//   void initState() {
//     super.initState();
//
//     // Initial load from ESP32
//     _fetchEspPackets();
//
//     // Periodic refresh: packets + images cache-buster
//     _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
//       if (!mounted) return;
//       _fetchEspPackets();
//       setState(() {
//         // force rebuild so snapshot/map URLs get new timestamps
//       });
//     });
//   }
//
//   @override
//   void dispose() {
//     _refreshTimer?.cancel();
//     super.dispose();
//   }
//
//   // ========== HTTP: fetch /packets from ESP32 ==========
//
//   Future<void> _fetchEspPackets() async {
//     setState(() {
//       _espLoading = true;
//       _espError = null;
//     });
//
//     try {
//       final uri = Uri.parse('$_espBaseUrl/packets');
//       debugPrint('[_fetchEspPackets] >>> GET $uri');
//
//       final resp = await http.get(uri).timeout(const Duration(seconds: 3));
//
//       debugPrint('[_fetchEspPackets] <<< status=${resp.statusCode}');
//       debugPrint('[_fetchEspPackets] <<< body=${resp.body}');
//
//       if (resp.statusCode != 200) {
//         setState(() {
//           _espError = 'HTTP error: ${resp.statusCode}';
//           _espPackets = [];
//         });
//         return;
//       }
//
//       dynamic decoded;
//       try {
//         decoded = jsonDecode(resp.body);
//       } catch (e) {
//         setState(() {
//           _espError = 'JSON decode failed: $e';
//           _espPackets = [];
//         });
//         return;
//       }
//
//       // Accept:
//       // 1) [ {...}, {...} ]
//       // 2) { "history": [ {...} ] }
//       // 3) { single_object }
//       List<dynamic> rawList;
//       if (decoded is List) {
//         rawList = decoded;
//       } else if (decoded is Map && decoded['history'] is List) {
//         rawList = decoded['history'] as List;
//       } else if (decoded is Map) {
//         rawList = [decoded];
//       } else {
//         setState(() {
//           _espError = 'Unexpected JSON shape: ${decoded.runtimeType}';
//           _espPackets = [];
//         });
//         return;
//       }
//
//       final packets = <Map<String, dynamic>>[];
//       for (final e in rawList) {
//         if (e is Map) {
//           packets.add(Map<String, dynamic>.from(e));
//         } else {
//           packets.add({'raw': e.toString()});
//         }
//       }
//
//       setState(() {
//         _espPackets = packets;
//       });
//     } catch (e) {
//       setState(() {
//         _espError = 'Request failed: $e';
//         _espPackets = [];
//       });
//     } finally {
//       if (mounted) {
//         setState(() {
//           _espLoading = false;
//         });
//       }
//     }
//   }
//
//   // ========== Livestream / Livemap helpers ==========
//
//   String _buildSnapshotUrl() {
//     final base = 'http://$_piStreamPath';
//     final sep = base.contains('?') ? '&' : '?';
//     final ts = DateTime.now().millisecondsSinceEpoch;
//     return '$base${sep}ts=$ts';
//   }
//
//   String _buildMapUrl() {
//     final base = 'http://$_piLiveMapPath';
//     final sep = base.contains('?') ? '&' : '?';
//     final ts = DateTime.now().millisecondsSinceEpoch;
//     return '$base${sep}ts=$ts';
//   }
//
//   void _refreshStream() {
//     setState(() {
//       // just force rebuild
//     });
//   }
//
//   void _signOut() {
//     if (!mounted) return;
//     Navigator.of(context).pushReplacementNamed(PageRoutes.welcome);
//   }
//
//   // ========== UI ==========
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('PARCEL Dashboard'),
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.logout),
//             onPressed: _signOut,
//             tooltip: 'Sign out',
//           ),
//         ],
//       ),
//       body: SafeArea(
//         child: Row(
//           crossAxisAlignment: CrossAxisAlignment.stretch,
//           children: [
//             // LEFT: Packages column
//             SizedBox(width: 260, child: _buildPackagesCard()),
//
//             // CENTER: Livestream + Livemap
//             Expanded(
//               child: Column(
//                 children: [
//                   Expanded(flex: 4, child: _buildLiveStreamCard()),
//                   Expanded(flex: 3, child: _buildLiveMapCard()),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   // ---------- UI helpers ----------
//
//   BoxDecoration _roundedBoxDecoration() {
//     return BoxDecoration(
//       borderRadius: BorderRadius.circular(18),
//       border: Border.all(color: Colors.black54, width: 1.5),
//     );
//   }
//
//   // --- Packages card using _espPackets from /packets ---
//   Widget _buildPackagesCard() {
//     debugPrint(
//       '[_buildPackagesCard] BUILD: packets=${_espPackets.length}, error=$_espError',
//     );
//
//     final latest = _espPackets.isNotEmpty ? _espPackets.last : null;
//
//     return Card(
//       margin: const EdgeInsets.all(8),
//       color: const Color(0xFFF7F3FF),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.stretch,
//         children: [
//           // Header
//           Container(
//             padding: const EdgeInsets.all(8),
//             color: Colors.black87,
//             child: const Text(
//               'Packages',
//               style: TextStyle(
//                 fontSize: 14,
//                 fontWeight: FontWeight.bold,
//                 color: Colors.white,
//               ),
//             ),
//           ),
//
//           // Status / error row + first-packet debug
//           Padding(
//             padding: const EdgeInsets.all(8.0),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.stretch,
//               children: [
//                 Row(
//                   children: [
//                     if (_espLoading)
//                       const SizedBox(
//                         width: 16,
//                         height: 16,
//                         child: CircularProgressIndicator(strokeWidth: 2),
//                       )
//                     else
//                       const Icon(Icons.cloud_download, size: 16),
//                     const SizedBox(width: 8),
//                     Expanded(
//                       child: Text(
//                         _espError ??
//                             (_espPackets.isEmpty
//                                 ? 'Waiting for parcels...'
//                                 : 'Packets: ${_espPackets.length}'
//                                 '${latest != null && latest["id"] != null ? " | Latest: ${latest["id"]}" : ""}'),
//                         style: TextStyle(
//                           fontSize: 11,
//                           color: _espError == null
//                               ? Colors.black87
//                               : Colors.red,
//                         ),
//                       ),
//                     ),
//                     IconButton(
//                       icon: const Icon(Icons.refresh, size: 18),
//                       tooltip: 'Refresh from ESP32',
//                       onPressed: _espLoading ? null : _fetchEspPackets,
//                     ),
//                   ],
//                 ),
//
//                 if (_espPackets.isNotEmpty) ...[
//                   const SizedBox(height: 4),
//                   Text(
//                     'First packet raw: ${_espPackets.first}',
//                     maxLines: 2,
//                     overflow: TextOverflow.ellipsis,
//                     style: const TextStyle(
//                       fontSize: 10,
//                       fontFamily: 'monospace',
//                       color: Colors.black54,
//                     ),
//                   ),
//                 ],
//               ],
//             ),
//           ),
//
//           const Divider(height: 1),
//
//           // Sequential list of messages
//           Expanded(
//             child: _espPackets.isEmpty
//                 ? const Center(
//               child: Text(
//                 'Waiting for parcels...',
//                 style: TextStyle(fontSize: 12),
//               ),
//             )
//                 : ListView.builder(
//               itemCount: _espPackets.length,
//               itemBuilder: (context, index) {
//                 final packet = _espPackets[index];
//
//                 final id = packet['id']?.toString() ?? 'unknown';
//                 final msg = (packet['msg'] ??
//                     packet['message'] ??
//                     packet['status'] ??
//                     packet['raw'] ??
//                     packet.toString())
//                     .toString();
//                 final ts = packet['timestamp']?.toString();
//
//                 return ListTile(
//                   dense: true,
//                   title: Text(
//                     id,
//                     style: const TextStyle(
//                       fontSize: 12,
//                       fontWeight: FontWeight.w600,
//                     ),
//                   ),
//                   subtitle: Text(
//                     ts != null ? '$msg\n$ts' : msg,
//                     style: const TextStyle(fontSize: 11),
//                   ),
//                 );
//               },
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   // --- Livestream (snapshot-based) ---
//   Widget _buildLiveStreamCard() {
//     final url = _buildSnapshotUrl();
//     return Container(
//       margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//       decoration: _roundedBoxDecoration(),
//       child: Padding(
//         padding: const EdgeInsets.all(8.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.stretch,
//           children: [
//             Row(
//               children: [
//                 const Icon(Icons.videocam, size: 18),
//                 const SizedBox(width: 8),
//                 const Text(
//                   'Livestream (Camera Snapshots)',
//                   style: TextStyle(fontWeight: FontWeight.w600),
//                 ),
//                 const Spacer(),
//                 IconButton(
//                   icon: const Icon(Icons.refresh),
//                   onPressed: _refreshStream,
//                   tooltip: 'Refresh Snapshot',
//                 ),
//               ],
//             ),
//             const SizedBox(height: 8),
//             Expanded(
//               child: Card(
//                 elevation: 2,
//                 clipBehavior: Clip.antiAlias,
//                 child: Image.network(
//                   url,
//                   fit: BoxFit.cover,
//                   errorBuilder: (context, error, stackTrace) {
//                     return Center(
//                       child: Text(
//                         'Livestream failed to load.\nURL: $url\nError: $error',
//                         textAlign: TextAlign.center,
//                         style: const TextStyle(
//                           fontSize: 12,
//                           color: Colors.red,
//                         ),
//                       ),
//                     );
//                   },
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   // --- Livemap ---
//   Widget _buildLiveMapCard() {
//     final url = _buildMapUrl();
//     return Container(
//       margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//       decoration: _roundedBoxDecoration(),
//       child: Padding(
//         padding: const EdgeInsets.all(8.0),
//         child: Card(
//           elevation: 2,
//           clipBehavior: Clip.antiAlias,
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.stretch,
//             children: [
//               Container(
//                 color: Colors.black12,
//                 padding:
//                 const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//                 child: const Row(
//                   children: [
//                     Icon(Icons.map, size: 18),
//                     SizedBox(width: 8),
//                     Text(
//                       'Livemap',
//                       style: TextStyle(fontWeight: FontWeight.w600),
//                     ),
//                   ],
//                 ),
//               ),
//               Expanded(
//                 child: Image.network(
//                   url,
//                   fit: BoxFit.cover,
//                   errorBuilder: (context, error, stackTrace) {
//                     return Center(
//                       child: Text(
//                         'Livemap failed to load.\nURL: $url\nError: $error',
//                         textAlign: TextAlign.center,
//                         style: const TextStyle(
//                           fontSize: 12,
//                           color: Colors.red,
//                         ),
//                       ),
//                     );
//                   },
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
//
// // // lib/pages/dashboard_page_route.dart
// //
// // import 'dart:async';
// // import 'dart:convert';
// //
// // import 'package:flutter/material.dart';
// // import 'package:http/http.dart' as http;
// //
// // import '../routes.dart';
// //
// // class DashboardPageRoute extends StatefulWidget {
// //   const DashboardPageRoute({super.key});
// //
// //   @override
// //   State<DashboardPageRoute> createState() => _DashboardPageRouteState();
// // }
// //
// // class _DashboardPageRouteState extends State<DashboardPageRoute> {
// //   // ---------- ESP32 mini-HTTP /packets ----------
// //
// //   // IMPORTANT: include http:// here
// //   static const String _espBaseUrl = 'http://172.20.10.9';
// //
// //   bool _espLoading = false;
// //   String? _espError;
// //   List<Map<String, dynamic>> _espPackets = [];
// //
// //   // ---------- Livestream / Livemap (Pi) ----------
// //
// //   // Camera snapshots (MJPG-streamer or similar)
// //   final String _piStreamPath = '172.20.10.7:8080/?action=snapshot';
// //
// //   // Live-Map images (fake_livemap_server.py or ESP32 map endpoint)
// //   final String _piLiveMapPath = '172.20.10.7:8000/frame/next';
// //
// //   Timer? _refreshTimer;
// //
// //   @override
// //   void initState() {
// //     super.initState();
// //
// //     // Initial load from ESP32
// //     _fetchEspPackets();
// //
// //     // Periodic refresh: packets + images cache-buster
// //     _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
// //       if (!mounted) return;
// //       _fetchEspPackets();
// //       setState(() {
// //         // rebuild so snapshot/map URLs get new timestamps
// //       });
// //     });
// //   }
// //
// //   @override
// //   void dispose() {
// //     _refreshTimer?.cancel();
// //     super.dispose();
// //   }
// //
// //   // ========== HTTP: fetch /packets from ESP32 ==========
// //
// //   Future<void> _fetchEspPackets() async {
// //     setState(() {
// //       _espLoading = true;
// //       _espError = null;
// //     });
// //
// //     try {
// //       final uri = Uri.parse('$_espBaseUrl/packets');
// //       debugPrint('[_fetchEspPackets] >>> START GET $uri');
// //
// //       final resp = await http.get(uri).timeout(const Duration(seconds: 3));
// //
// //       debugPrint('[_fetchEspPackets] <<< STATUS: ${resp.statusCode}');
// //       debugPrint(
// //           '[_fetchEspPackets] <<< RAW BODY (${resp.body.length} chars):');
// //       debugPrint(resp.body);
// //
// //       if (resp.statusCode != 200) {
// //         setState(() {
// //           _espError = 'HTTP error: ${resp.statusCode}';
// //           _espPackets = [];
// //         });
// //         debugPrint('[_fetchEspPackets] !!! NON-200 STATUS, aborting decode');
// //         return;
// //       }
// //
// //       dynamic decoded;
// //       try {
// //         decoded = jsonDecode(resp.body);
// //         debugPrint(
// //           '[_fetchEspPackets] decoded runtimeType = ${decoded.runtimeType}',
// //         );
// //       } catch (e, st) {
// //         debugPrint('[_fetchEspPackets] !!! jsonDecode FAILED: $e');
// //         debugPrint(st.toString());
// //         setState(() {
// //           _espError = 'JSON decode failed: $e';
// //           _espPackets = [];
// //         });
// //         return;
// //       }
// //
// //       // Allow:
// //       //   1) [ { ... }, { ... } ]
// //       //   2) { "history": [ { ... } ] }
// //       List<dynamic> rawList;
// //       if (decoded is List) {
// //         rawList = decoded;
// //         debugPrint(
// //             '[_fetchEspPackets] treating decoded as List, length=${rawList.length}');
// //       } else if (decoded is Map && decoded['history'] is List) {
// //         rawList = decoded['history'] as List;
// //         debugPrint(
// //             '[_fetchEspPackets] using decoded["history"] as List, length=${rawList.length}');
// //       } else if (decoded is Map) {
// //         // Optional: treat single object as one packet
// //         debugPrint(
// //             '[_fetchEspPackets] treating single Map as one packet: $decoded');
// //         rawList = [decoded];
// //       } else {
// //         debugPrint(
// //           '[_fetchEspPackets] !!! Unexpected JSON shape: ${decoded.runtimeType}, content=$decoded',
// //         );
// //         setState(() {
// //           _espError = 'Unexpected JSON (not List or {history: [...]})';
// //           _espPackets = [];
// //         });
// //         return;
// //       }
// //
// //       final packets = <Map<String, dynamic>>[];
// //       for (var i = 0; i < rawList.length; i++) {
// //         final e = rawList[i];
// //         if (e is Map) {
// //           final map = Map<String, dynamic>.from(e);
// //           debugPrint('[_fetchEspPackets] packet[$i] = $map');
// //           packets.add(map);
// //         } else {
// //           debugPrint(
// //             '[_fetchEspPackets] packet[$i] not Map (runtimeType=${e.runtimeType}), wrapping as {raw: ...}',
// //           );
// //           packets.add(<String, dynamic>{'raw': e.toString()});
// //         }
// //       }
// //
// //       debugPrint('[_fetchEspPackets] FINAL packet count = ${packets.length}');
// //
// //       setState(() {
// //         _espPackets = packets;
// //       });
// //     } catch (e, st) {
// //       debugPrint('[_fetchEspPackets] !!! REQUEST FAILED: $e');
// //       debugPrint(st.toString());
// //       setState(() {
// //         _espError = 'Request failed: $e';
// //         _espPackets = [];
// //       });
// //     } finally {
// //       if (mounted) {
// //         setState(() {
// //           _espLoading = false;
// //         });
// //         debugPrint(
// //             '[_fetchEspPackets] DONE. _espPackets.length=${_espPackets.length}, _espError=$_espError');
// //       }
// //     }
// //   }
// //
// //   // ========== Livestream / Livemap helpers ==========
// //
// //   String _buildSnapshotUrl() {
// //     final base = 'http://$_piStreamPath';
// //     final sep = base.contains('?') ? '&' : '?';
// //     final ts = DateTime.now().millisecondsSinceEpoch;
// //     return '$base${sep}ts=$ts';
// //   }
// //
// //   String _buildMapUrl() {
// //     final base = 'http://$_piLiveMapPath';
// //     final sep = base.contains('?') ? '&' : '?';
// //     final ts = DateTime.now().millisecondsSinceEpoch;
// //     return '$base${sep}ts=$ts';
// //   }
// //
// //   void _refreshStream() {
// //     setState(() {
// //       // Just forces rebuild; URLs get new ts
// //     });
// //   }
// //
// //   void _signOut() {
// //     if (!mounted) return;
// //     Navigator.of(context).pushReplacementNamed(PageRoutes.welcome);
// //   }
// //
// //   // ========== UI ==========
// //
// //   @override
// //   Widget build(BuildContext context) {
// //     return Scaffold(
// //       appBar: AppBar(
// //         title: const Text('PARCEL Dashboard'),
// //         actions: [
// //           IconButton(
// //             icon: const Icon(Icons.logout),
// //             onPressed: _signOut,
// //             tooltip: 'Sign out',
// //           ),
// //         ],
// //       ),
// //       body: SafeArea(
// //         child: Row(
// //           crossAxisAlignment: CrossAxisAlignment.stretch,
// //           children: [
// //             // -------- LEFT: Packages card (HTTP from ESP32) --------
// //             SizedBox(
// //               width: 260,
// //               child: _buildPackagesCard(),
// //             ),
// //
// //             // -------- CENTER: Livestream + Livemap --------
// //             Expanded(
// //               child: Column(
// //                 children: [
// //                   // --- Livestream (camera snapshots) ---
// //                   Expanded(
// //                     flex: 4,
// //                     child: Container(
// //                       margin: const EdgeInsets.symmetric(
// //                         horizontal: 8,
// //                         vertical: 4,
// //                       ),
// //                       decoration: _roundedBoxDecoration(),
// //                       child: Padding(
// //                         padding: const EdgeInsets.all(8.0),
// //                         child: Column(
// //                           crossAxisAlignment: CrossAxisAlignment.stretch,
// //                           children: [
// //                             Row(
// //                               children: [
// //                                 const Icon(Icons.videocam, size: 18),
// //                                 const SizedBox(width: 8),
// //                                 const Text(
// //                                   'Livestream (Camera Snapshots)',
// //                                   style: TextStyle(
// //                                     fontWeight: FontWeight.w600,
// //                                   ),
// //                                 ),
// //                                 const Spacer(),
// //                                 IconButton(
// //                                   icon: const Icon(Icons.refresh),
// //                                   onPressed: _refreshStream,
// //                                   tooltip: 'Refresh Snapshot',
// //                                 ),
// //                               ],
// //                             ),
// //                             const SizedBox(height: 8),
// //                             Card(
// //                               color: Colors.blue.shade50,
// //                               child: Padding(
// //                                 padding: const EdgeInsets.all(8.0),
// //                                 child: Column(
// //                                   crossAxisAlignment: CrossAxisAlignment.start,
// //                                   children: [
// //                                     const Text(
// //                                       'Livestream base URL:',
// //                                       style: TextStyle(
// //                                         fontWeight: FontWeight.w600,
// //                                         fontSize: 12,
// //                                       ),
// //                                     ),
// //                                     const SizedBox(height: 4),
// //                                     Text(
// //                                       'http://$_piStreamPath',
// //                                       style: const TextStyle(
// //                                         fontSize: 12,
// //                                         fontFamily: 'monospace',
// //                                       ),
// //                                     ),
// //                                   ],
// //                                 ),
// //                               ),
// //                             ),
// //                             const SizedBox(height: 8),
// //                             Expanded(
// //                               child: Card(
// //                                 elevation: 2,
// //                                 clipBehavior: Clip.antiAlias,
// //                                 child: Column(
// //                                   crossAxisAlignment:
// //                                   CrossAxisAlignment.stretch,
// //                                   children: [
// //                                     Container(
// //                                       color: Colors.black12,
// //                                       padding: const EdgeInsets.symmetric(
// //                                         horizontal: 12,
// //                                         vertical: 8,
// //                                       ),
// //                                       child: const Row(
// //                                         children: [
// //                                           Icon(Icons.camera_alt, size: 18),
// //                                           SizedBox(width: 8),
// //                                           Text(
// //                                             'Livestream',
// //                                             style: TextStyle(
// //                                               fontWeight: FontWeight.w600,
// //                                             ),
// //                                           ),
// //                                         ],
// //                                       ),
// //                                     ),
// //                                     Expanded(child: _buildStream()),
// //                                   ],
// //                                 ),
// //                               ),
// //                             ),
// //                           ],
// //                         ),
// //                       ),
// //                     ),
// //                   ),
// //
// //                   // --- Livemap ---
// //                   Expanded(
// //                     flex: 3,
// //                     child: Container(
// //                       margin: const EdgeInsets.symmetric(
// //                         horizontal: 8,
// //                         vertical: 4,
// //                       ),
// //                       decoration: _roundedBoxDecoration(),
// //                       child: Padding(
// //                         padding: const EdgeInsets.all(8.0),
// //                         child: Card(
// //                           elevation: 2,
// //                           clipBehavior: Clip.antiAlias,
// //                           child: Column(
// //                             crossAxisAlignment: CrossAxisAlignment.stretch,
// //                             children: [
// //                               Container(
// //                                 color: Colors.black12,
// //                                 padding: const EdgeInsets.symmetric(
// //                                   horizontal: 12,
// //                                   vertical: 8,
// //                                 ),
// //                                 child: const Row(
// //                                   children: [
// //                                     Icon(Icons.map, size: 18),
// //                                     SizedBox(width: 8),
// //                                     Text(
// //                                       'Livemap',
// //                                       style: TextStyle(
// //                                         fontWeight: FontWeight.w600,
// //                                       ),
// //                                     ),
// //                                   ],
// //                                 ),
// //                               ),
// //                               Padding(
// //                                 padding: const EdgeInsets.all(8.0),
// //                                 child: Text(
// //                                   'Livemap base URL: http://$_piLiveMapPath',
// //                                   style: const TextStyle(
// //                                     fontSize: 11,
// //                                     fontFamily: 'monospace',
// //                                   ),
// //                                 ),
// //                               ),
// //                               Expanded(child: _buildMapStream()),
// //                             ],
// //                           ),
// //                         ),
// //                       ),
// //                     ),
// //                   ),
// //                 ],
// //               ),
// //             ),
// //           ],
// //         ),
// //       ),
// //     );
// //   }
// //
// //   // ---------- UI helpers ----------
// //
// //   BoxDecoration _roundedBoxDecoration() {
// //     return BoxDecoration(
// //       borderRadius: BorderRadius.circular(18),
// //       border: Border.all(color: Colors.black54, width: 1.5),
// //     );
// //   }
// //
// //   // --- Packages card using _espPackets from /packets ---
// //   Widget _buildPackagesCard() {
// //     debugPrint(
// //       '[_buildPackagesCard] BUILD: packets=${_espPackets.length}, error=$_espError',
// //     );
// //
// //     final latest = _espPackets.isNotEmpty ? _espPackets.last : null;
// //
// //     return Card(
// //       margin: const EdgeInsets.all(8),
// //       color: const Color(0xFFF7F3FF),
// //       child: Column(
// //         crossAxisAlignment: CrossAxisAlignment.stretch,
// //         children: [
// //           // Header
// //           Container(
// //             padding: const EdgeInsets.all(8),
// //             color: Colors.black87,
// //             child: const Text(
// //               'Packages',
// //               style: TextStyle(
// //                 fontSize: 14,
// //                 fontWeight: FontWeight.bold,
// //                 color: Colors.white,
// //               ),
// //             ),
// //           ),
// //
// //           // Status / error row + first-packet debug
// //           Padding(
// //             padding: const EdgeInsets.all(8.0),
// //             child: Column(
// //               crossAxisAlignment: CrossAxisAlignment.stretch,
// //               children: [
// //                 Row(
// //                   children: [
// //                     if (_espLoading)
// //                       const SizedBox(
// //                         width: 16,
// //                         height: 16,
// //                         child: CircularProgressIndicator(strokeWidth: 2),
// //                       )
// //                     else
// //                       const Icon(Icons.cloud_download, size: 16),
// //                     const SizedBox(width: 8),
// //                     Expanded(
// //                       child: Text(
// //                         _espError ??
// //                             (_espPackets.isEmpty
// //                                 ? 'Waiting for parcels...'
// //                                 : 'Packets: ${_espPackets.length}'
// //                                 '${latest != null && latest["id"] != null ? " | Latest: ${latest["id"]}" : ""}'),
// //                         style: TextStyle(
// //                           fontSize: 11,
// //                           color: _espError == null
// //                               ? Colors.black87
// //                               : Colors.red,
// //                         ),
// //                       ),
// //                     ),
// //                     IconButton(
// //                       icon: const Icon(Icons.refresh, size: 18),
// //                       tooltip: 'Refresh from ESP32',
// //                       onPressed: _espLoading ? null : _fetchEspPackets,
// //                     ),
// //                   ],
// //                 ),
// //
// //                 if (_espPackets.isNotEmpty) ...[
// //                   const SizedBox(height: 4),
// //                   Text(
// //                     'First packet raw: ${_espPackets.first}',
// //                     maxLines: 2,
// //                     overflow: TextOverflow.ellipsis,
// //                     style: const TextStyle(
// //                       fontSize: 10,
// //                       fontFamily: 'monospace',
// //                       color: Colors.black54,
// //                     ),
// //                   ),
// //                 ],
// //               ],
// //             ),
// //           ),
// //
// //           const Divider(height: 1),
// //
// //           // Sequential list of messages
// //           Expanded(
// //             child: _espPackets.isEmpty
// //                 ? const Center(
// //               child: Text(
// //                 'Waiting for parcels...',
// //                 style: TextStyle(fontSize: 12),
// //               ),
// //             )
// //                 : ListView.builder(
// //               itemCount: _espPackets.length,
// //               itemBuilder: (context, index) {
// //                 final packet = _espPackets[index];
// //
// //                 final id = packet['id']?.toString() ?? 'unknown';
// //                 final msg = (packet['msg'] ??
// //                     packet['message'] ??
// //                     packet['status'] ??
// //                     packet['raw'] ??
// //                     packet.toString())
// //                     .toString();
// //                 final ts = packet['timestamp']?.toString();
// //
// //                 return ListTile(
// //                   dense: true,
// //                   title: Text(
// //                     id,
// //                     style: const TextStyle(
// //                       fontSize: 12,
// //                       fontWeight: FontWeight.w600,
// //                     ),
// //                   ),
// //                   subtitle: Text(
// //                     ts != null ? '$msg\n$ts' : msg,
// //                     style: const TextStyle(fontSize: 11),
// //                   ),
// //                 );
// //               },
// //             ),
// //           ),
// //         ],
// //       ),
// //     );
// //   }
// //
// //   // --- Livestream (snapshot-based) ---
// //   Widget _buildStream() {
// //     final url = _buildSnapshotUrl();
// //     return Image.network(
// //       url,
// //       fit: BoxFit.cover,
// //       errorBuilder: (context, error, stackTrace) {
// //         return Center(
// //           child: Text(
// //             'Livestream failed to load.\nURL: $url\nError: $error',
// //             textAlign: TextAlign.center,
// //             style: const TextStyle(fontSize: 12, color: Colors.red),
// //           ),
// //         );
// //       },
// //     );
// //   }
// //
// //   // --- Livemap ---
// //   Widget _buildMapStream() {
// //     final url = _buildMapUrl();
// //     return Image.network(
// //       url,
// //       fit: BoxFit.cover,
// //       errorBuilder: (context, error, stackTrace) {
// //         return Center(
// //           child: Text(
// //             'Livemap failed to load.\nURL: $url\nError: $error',
// //             textAlign: TextAlign.center,
// //             style: const TextStyle(fontSize: 12, color: Colors.red),
// //           ),
// //         );
// //       },
// //     );
// //   }
// // }
//
// // // lib/pages/dashboard_page_route.dart
// //
// // import 'dart:async';
// // import 'dart:convert';
// // import 'package:flutter/material.dart';
// // import 'package:http/http.dart' as http;
// //
// // import '../routes.dart';
// //
// // class DashboardPageRoute extends StatefulWidget {
// //   const DashboardPageRoute({super.key});
// //
// //   @override
// //   State<DashboardPageRoute> createState() => _DashboardPageRouteState();
// // }
// //
// // class _DashboardPageRouteState extends State<DashboardPageRoute> {
// //   // ---------- ESP32 mini-HTTP /packets ----------
// //
// //   // IMPORTANT: include http:// here
// //   static const String _espBaseUrl = 'http://172.20.10.9';
// //
// //   bool _espLoading = false;
// //   String? _espError;
// //   List<Map<String, dynamic>> _espPackets = [];
// //
// //   // ---------- Livestream / Livemap (Pi) ----------
// //
// //   // Camera snapshots (MJPG-streamer or similar)
// //   final String _piStreamPath = '172.20.10.7:8080/?action=snapshot';
// //
// //   // Live-Map images (fake_livemap_server.py or ESP32 map endpoint)
// //   final String _piLiveMapPath = '172.20.10.7:8000/frame/next';
// //
// //   Timer? _refreshTimer;
// //
// //   @override
// //   void initState() {
// //     super.initState();
// //
// //     // Initial load from ESP32
// //     _fetchEspPackets();
// //
// //     // Periodic refresh: packets + images cache-buster
// //     _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
// //       if (!mounted) return;
// //       // _fetchEspPackets();
// //       setState(() {
// //         // rebuild so snapshot/map URLs get new timestamps
// //       });
// //     });
// //   }
// //
// //   @override
// //   void dispose() {
// //     _refreshTimer?.cancel();
// //     super.dispose();
// //   }
// //
// //   // ========== HTTP: fetch /packets from ESP32 ==========
// //   Future<void> _fetchEspPackets() async {
// //   setState(() {
// //     _espLoading = true;
// //     _espError = null;
// //   });
// //
// //   try {
// //     final uri = Uri.parse('$_espBaseUrl/packets');
// //     debugPrint('[_fetchEspPackets] >>> START GET $uri');
// //
// //     final resp = await http.get(uri).timeout(const Duration(seconds: 3));
// //
// //     debugPrint('[_fetchEspPackets] <<< STATUS: ${resp.statusCode}');
// //     debugPrint('[_fetchEspPackets] <<< RAW BODY (${resp.body.length} chars):');
// //     debugPrint(resp.body);
// //
// //     if (resp.statusCode != 200) {
// //       setState(() {
// //         _espError = 'HTTP error: ${resp.statusCode}';
// //         _espPackets = [];
// //       });
// //       debugPrint('[_fetchEspPackets] !!! NON-200 STATUS, aborting decode');
// //       return;
// //     }
// //
// //     dynamic decoded;
// //     try {
// //       decoded = jsonDecode(resp.body);
// //       debugPrint(
// //         '[_fetchEspPackets] decoded runtimeType = ${decoded.runtimeType}',
// //       );
// //     } catch (e, st) {
// //       debugPrint('[_fetchEspPackets] !!! jsonDecode FAILED: $e');
// //       debugPrint(st.toString());
// //       setState(() {
// //         _espError = 'JSON decode failed: $e';
// //         _espPackets = [];
// //       });
// //       return;
// //     }
// //
// //     // Allow:
// //     //   1) [ { ... }, { ... } ]
// //     //   2) { "history": [ { ... } ] }
// //     List<dynamic> rawList;
// //     if (decoded is List) {
// //       rawList = decoded;
// //       debugPrint('[_fetchEspPackets] treating decoded as List, length=${rawList.length}');
// //     } else if (decoded is Map && decoded['history'] is List) {
// //       rawList = decoded['history'] as List;
// //       debugPrint('[_fetchEspPackets] using decoded["history"] as List, length=${rawList.length}');
// //     } else {
// //       debugPrint(
// //         '[_fetchEspPackets] !!! Unexpected JSON shape: ${decoded.runtimeType}, content=$decoded',
// //       );
// //       setState(() {
// //         _espError = 'Unexpected JSON (not List or {history: [...]})';
// //         _espPackets = [];
// //       });
// //       return;
// //     }
// //
// //     final packets = <Map<String, dynamic>>[];
// //     for (var i = 0; i < rawList.length; i++) {
// //       final e = rawList[i];
// //       if (e is Map) {
// //         final map = Map<String, dynamic>.from(e);
// //         debugPrint('[_fetchEspPackets] packet[$i] = $map');
// //         packets.add(map);
// //       } else {
// //         debugPrint(
// //           '[_fetchEspPackets] packet[$i] not Map (runtimeType=${e.runtimeType}), wrapping as {raw: ...}',
// //         );
// //         packets.add(<String, dynamic>{'raw': e.toString()});
// //       }
// //     }
// //
// //     debugPrint('[_fetchEspPackets] FINAL packet count = ${packets.length}');
// //
// //     setState(() {
// //       _espPackets = packets;
// //     });
// //   } catch (e, st) {
// //     debugPrint('[_fetchEspPackets] !!! REQUEST FAILED: $e');
// //     debugPrint(st.toString());
// //     setState(() {
// //       _espError = 'Request failed: $e';
// //       _espPackets = [];
// //     });
// //   } finally {
// //     if (mounted) {
// //       setState(() {
// //         _espLoading = false;
// //       });
// //       debugPrint('[_fetchEspPackets] DONE. _espPackets.length=${_espPackets.length}, _espError=$_espError');
// //     }
// //   }
// // }
// //
// //
// //   // Future<void> _fetchEspPackets() async {
// //   //   setState(() {
// //   //     _espLoading = true;
// //   //     _espError = null;
// //   //   });
// //
// //   //   try {
// //   //     final uri = Uri.parse('$_espBaseUrl/packets');
// //   //     debugPrint('[_fetchEspPackets] GET $uri');
// //
// //   //     final resp = await http.get(uri).timeout(const Duration(seconds: 3));
// //
// //   //     debugPrint('[_fetchEspPackets] status = ${resp.statusCode}');
// //   //     debugPrint('[_fetchEspPackets] body   = ${resp.body}');
// //
// //   //     if (resp.statusCode == 200) {
// //   //       final decoded = jsonDecode(resp.body);
// //
// //   //       // Allow two shapes:
// //   //       // 1) [ { ... }, { ... } ]
// //   //       // 2) { "history": [ { ... } ] }
// //   //       List<dynamic> rawList;
// //   //       if (decoded is List) {
// //   //         rawList = decoded;
// //   //       } else if (decoded is Map && decoded['history'] is List) {
// //   //         rawList = decoded['history'] as List;
// //   //       } else {
// //   //         setState(() {
// //   //           _espError =
// //   //               'Unexpected JSON (not a list/history): ${decoded.runtimeType}';
// //   //           _espPackets = [];
// //   //         });
// //   //         return;
// //   //       }
// //
// //   //       final packets = rawList.map<Map<String, dynamic>>((e) {
// //   //         if (e is Map) {
// //   //           return Map<String, dynamic>.from(e);
// //   //         } else {
// //   //           // if ESP32 ever returns plain strings, wrap them
// //   //           return <String, dynamic>{'raw': e.toString()};
// //   //         }
// //   //       }).toList();
// //
// //   //       debugPrint('[_fetchEspPackets] decoded ${packets.length} packets');
// //
// //   //       setState(() {
// //   //         _espPackets = packets;
// //   //       });
// //   //     } else {
// //   //       setState(() {
// //   //         _espError = 'HTTP error: ${resp.statusCode}';
// //   //         _espPackets = [];
// //   //       });
// //   //     }
// //   //   } catch (e) {
// //   //     setState(() {
// //   //       _espError = 'Request failed: $e';
// //   //       _espPackets = [];
// //   //     });
// //   //   } finally {
// //   //     if (mounted) {
// //   //       setState(() {
// //   //         _espLoading = false;
// //   //       });
// //   //     }
// //   //   }
// //   // }
// //
// //   // ========== Livestream / Livemap helpers ==========
// //
// //   String _buildSnapshotUrl() {
// //     final base = 'http://$_piStreamPath';
// //     final sep = base.contains('?') ? '&' : '?';
// //     final ts = DateTime.now().millisecondsSinceEpoch;
// //     return '$base${sep}ts=$ts';
// //   }
// //
// //   String _buildMapUrl() {
// //     final base = 'http://$_piLiveMapPath';
// //     final sep = base.contains('?') ? '&' : '?';
// //     final ts = DateTime.now().millisecondsSinceEpoch;
// //     return '$base${sep}ts=$ts';
// //   }
// //
// //   void _refreshStream() {
// //     setState(() {
// //       // Just forces rebuild; URLs get new ts
// //     });
// //   }
// //
// //   void _signOut() {
// //     if (!mounted) return;
// //     Navigator.of(context).pushReplacementNamed(PageRoutes.welcome);
// //   }
// //
// //   // ========== UI ==========
// //
// //   @override
// //   Widget build(BuildContext context) {
// //     return Scaffold(
// //       appBar: AppBar(
// //         title: const Text('PARCEL Dashboard'),
// //         actions: [
// //           IconButton(
// //             icon: const Icon(Icons.logout),
// //             onPressed: _signOut,
// //             tooltip: 'Sign out',
// //           ),
// //         ],
// //       ),
// //       body: SafeArea(
// //         child: Row(
// //           crossAxisAlignment: CrossAxisAlignment.stretch,
// //           children: [
// //             // -------- LEFT: Packages card (HTTP from ESP32) --------
// //             SizedBox(
// //               width: 260,
// //               child: _buildPackagesCard(),
// //             ),
// //
// //             // -------- CENTER: Livestream + Livemap --------
// //             Expanded(
// //               child: Column(
// //                 children: [
// //                   // --- Livestream (camera snapshots) ---
// //                   Expanded(
// //                     flex: 4,
// //                     child: Container(
// //                       margin: const EdgeInsets.symmetric(
// //                         horizontal: 8,
// //                         vertical: 4,
// //                       ),
// //                       decoration: _roundedBoxDecoration(),
// //                       child: Padding(
// //                         padding: const EdgeInsets.all(8.0),
// //                         child: Column(
// //                           crossAxisAlignment: CrossAxisAlignment.stretch,
// //                           children: [
// //                             Row(
// //                               children: [
// //                                 const Icon(Icons.videocam, size: 18),
// //                                 const SizedBox(width: 8),
// //                                 const Text(
// //                                   'Livestream (Camera Snapshots)',
// //                                   style: TextStyle(
// //                                     fontWeight: FontWeight.w600,
// //                                   ),
// //                                 ),
// //                                 const Spacer(),
// //                                 IconButton(
// //                                   icon: const Icon(Icons.refresh),
// //                                   onPressed: _refreshStream,
// //                                   tooltip: 'Refresh Snapshot',
// //                                 ),
// //                               ],
// //                             ),
// //                             const SizedBox(height: 8),
// //                             Card(
// //                               color: Colors.blue.shade50,
// //                               child: Padding(
// //                                 padding: const EdgeInsets.all(8.0),
// //                                 child: Column(
// //                                   crossAxisAlignment: CrossAxisAlignment.start,
// //                                   children: [
// //                                     const Text(
// //                                       'Livestream base URL:',
// //                                       style: TextStyle(
// //                                         fontWeight: FontWeight.w600,
// //                                         fontSize: 12,
// //                                       ),
// //                                     ),
// //                                     const SizedBox(height: 4),
// //                                     Text(
// //                                       'http://$_piStreamPath',
// //                                       style: const TextStyle(
// //                                         fontSize: 12,
// //                                         fontFamily: 'monospace',
// //                                       ),
// //                                     ),
// //                                   ],
// //                                 ),
// //                               ),
// //                             ),
// //                             const SizedBox(height: 8),
// //                             Expanded(
// //                               child: Card(
// //                                 elevation: 2,
// //                                 clipBehavior: Clip.antiAlias,
// //                                 child: Column(
// //                                   crossAxisAlignment:
// //                                       CrossAxisAlignment.stretch,
// //                                   children: [
// //                                     Container(
// //                                       color: Colors.black12,
// //                                       padding: const EdgeInsets.symmetric(
// //                                         horizontal: 12,
// //                                         vertical: 8,
// //                                       ),
// //                                       child: const Row(
// //                                         children: [
// //                                           Icon(Icons.camera_alt, size: 18),
// //                                           SizedBox(width: 8),
// //                                           Text(
// //                                             'Livestream',
// //                                             style: TextStyle(
// //                                               fontWeight: FontWeight.w600,
// //                                             ),
// //                                           ),
// //                                         ],
// //                                       ),
// //                                     ),
// //                                     Expanded(child: _buildStream()),
// //                                   ],
// //                                 ),
// //                               ),
// //                             ),
// //                           ],
// //                         ),
// //                       ),
// //                     ),
// //                   ),
// //
// //                   // --- Livemap ---
// //                   Expanded(
// //                     flex: 3,
// //                     child: Container(
// //                       margin: const EdgeInsets.symmetric(
// //                         horizontal: 8,
// //                         vertical: 4,
// //                       ),
// //                       decoration: _roundedBoxDecoration(),
// //                       child: Padding(
// //                         padding: const EdgeInsets.all(8.0),
// //                         child: Card(
// //                           elevation: 2,
// //                           clipBehavior: Clip.antiAlias,
// //                           child: Column(
// //                             crossAxisAlignment: CrossAxisAlignment.stretch,
// //                             children: [
// //                               Container(
// //                                 color: Colors.black12,
// //                                 padding: const EdgeInsets.symmetric(
// //                                   horizontal: 12,
// //                                   vertical: 8,
// //                                 ),
// //                                 child: const Row(
// //                                   children: [
// //                                     Icon(Icons.map, size: 18),
// //                                     SizedBox(width: 8),
// //                                     Text(
// //                                       'Livemap',
// //                                       style: TextStyle(
// //                                         fontWeight: FontWeight.w600,
// //                                       ),
// //                                     ),
// //                                   ],
// //                                 ),
// //                               ),
// //                               Padding(
// //                                 padding: const EdgeInsets.all(8.0),
// //                                 child: Text(
// //                                   'Livemap base URL: http://$_piLiveMapPath',
// //                                   style: const TextStyle(
// //                                     fontSize: 11,
// //                                     fontFamily: 'monospace',
// //                                   ),
// //                                 ),
// //                               ),
// //                               Expanded(child: _buildMapStream()),
// //                             ],
// //                           ),
// //                         ),
// //                       ),
// //                     ),
// //                   ),
// //                 ],
// //               ),
// //             ),
// //           ],
// //         ),
// //       ),
// //     );
// //   }
// //
// //   // ---------- UI helpers ----------
// //
// //   BoxDecoration _roundedBoxDecoration() {
// //     return BoxDecoration(
// //       borderRadius: BorderRadius.circular(18),
// //       border: Border.all(color: Colors.black54, width: 1.5),
// //     );
// //   }
// //
// //   // --- Packages card using _espPackets from /packets ---
// //   Widget _buildPackagesCard() {
// //   debugPrint(
// //     '[_buildPackagesCard] BUILD: packets=${_espPackets.length}, error=$_espError',
// //   );
// //
// //   final latest = _espPackets.isNotEmpty ? _espPackets.last : null;
// //
// //   return Card(
// //     margin: const EdgeInsets.all(8),
// //     color: const Color(0xFFF7F3FF),
// //     child: Column(
// //       crossAxisAlignment: CrossAxisAlignment.stretch,
// //       children: [
// //         // Header
// //         Container(
// //           padding: const EdgeInsets.all(8),
// //           color: Colors.black87,
// //           child: const Text(
// //             'Packages',
// //             style: TextStyle(
// //               fontSize: 14,
// //               fontWeight: FontWeight.bold,
// //               color: Colors.white,
// //             ),
// //           ),
// //         ),
// //
// //         // Status / error row + first-packet debug
// //         Padding(
// //           padding: const EdgeInsets.all(8.0),
// //           child: Column(
// //             crossAxisAlignment: CrossAxisAlignment.stretch,
// //             children: [
// //               Row(
// //                 children: [
// //                   if (_espLoading)
// //                     const SizedBox(
// //                       width: 16,
// //                       height: 16,
// //                       child: CircularProgressIndicator(strokeWidth: 2),
// //                     )
// //                   else
// //                     const Icon(Icons.cloud_download, size: 16),
// //                   const SizedBox(width: 8),
// //                   Expanded(
// //                     child: Text(
// //                       _espError ??
// //                           (_espPackets.isEmpty
// //                               ? 'Waiting for parcels...'
// //                               : 'Packets: ${_espPackets.length}'
// //                                 '${latest != null && latest["id"] != null ? " | Latest: ${latest["id"]}" : ""}'),
// //                       style: TextStyle(
// //                         fontSize: 11,
// //                         color: _espError == null ? Colors.black87 : Colors.red,
// //                       ),
// //                     ),
// //                   ),
// //                   IconButton(
// //                     icon: const Icon(Icons.refresh, size: 18),
// //                     tooltip: 'Refresh from ESP32',
// //                     onPressed: _espLoading ? null : _fetchEspPackets,
// //                   ),
// //                 ],
// //               ),
// //
// //               if (_espPackets.isNotEmpty) ...[
// //                 const SizedBox(height: 4),
// //                 Text(
// //                   'First packet raw: ${_espPackets.first}',
// //                   maxLines: 2,
// //                   overflow: TextOverflow.ellipsis,
// //                   style: const TextStyle(
// //                     fontSize: 10,
// //                     fontFamily: 'monospace',
// //                     color: Colors.black54,
// //                   ),
// //                 ),
// //               ],
// //             ],
// //           ),
// //         ),
// //
// //         const Divider(height: 1),
// //
// //         // Sequential list of messages
// //         Expanded(
// //           child: _espPackets.isEmpty
// //               ? const Center(
// //                   child: Text(
// //                     'Waiting for parcels...',
// //                     style: TextStyle(fontSize: 12),
// //                   ),
// //                 )
// //               : ListView.builder(
// //                   itemCount: _espPackets.length,
// //                   itemBuilder: (context, index) {
// //                     final packet = _espPackets[index];
// //
// //                     final id = packet['id']?.toString() ?? 'unknown';
// //                     final msg = (packet['msg'] ??
// //                             packet['message'] ??
// //                             packet['status'] ??
// //                             packet['raw'] ??
// //                             packet.toString())
// //                         .toString();
// //                     final ts = packet['timestamp']?.toString();
// //
// //                     return ListTile(
// //                       dense: true,
// //                       title: Text(
// //                         id,
// //                         style: const TextStyle(
// //                           fontSize: 12,
// //                           fontWeight: FontWeight.w600,
// //                         ),
// //                       ),
// //                       subtitle: Text(
// //                         ts != null ? '$msg\n$ts' : msg,
// //                         style: const TextStyle(fontSize: 11),
// //                       ),
// //                     );
// //                   },
// //                 ),
// //         ),
// //       ],
// //     ),
// //   );
// // }
// //
// // // Widget _buildPackagesCard() {
// // //   debugPrint(
// // //     '[_buildPackagesCard] packets=${_espPackets.length}, error=$_espError',
// // //   );
// //
// // //   final latest = _espPackets.isNotEmpty ? _espPackets.last : null;
// //
// // //   return Card(
// // //     margin: const EdgeInsets.all(8),
// // //     color: const Color(0xFFF7F3FF),
// // //     child: Column(
// // //       crossAxisAlignment: CrossAxisAlignment.stretch,
// // //       children: [
// // //         // Header
// // //         Container(
// // //           padding: const EdgeInsets.all(8),
// // //           color: Colors.black87,
// // //           child: const Text(
// // //             'Packages',
// // //             style: TextStyle(
// // //               fontSize: 14,
// // //               fontWeight: FontWeight.bold,
// // //               color: Colors.white,
// // //             ),
// // //           ),
// // //         ),
// //
// // //         // Status / error row + quick debug info
// // //         Padding(
// // //           padding: const EdgeInsets.all(8.0),
// // //           child: Column(
// // //             crossAxisAlignment: CrossAxisAlignment.stretch,
// // //             children: [
// // //               Row(
// // //                 children: [
// // //                   if (_espLoading)
// // //                     const SizedBox(
// // //                       width: 16,
// // //                       height: 16,
// // //                       child: CircularProgressIndicator(strokeWidth: 2),
// // //                     )
// // //                   else
// // //                     const Icon(Icons.cloud_download, size: 16),
// // //                   const SizedBox(width: 8),
// // //                   Expanded(
// // //                     child: Text(
// // //                       _espError ??
// // //                           (_espPackets.isEmpty
// // //                               ? 'Waiting for parcels...'
// // //                               : 'Packets: ${_espPackets.length}'
// // //                                 '${latest != null && latest["id"] != null ? " | Latest: ${latest["id"]}" : ""}'),
// // //                       style: TextStyle(
// // //                         fontSize: 11,
// // //                         color: _espError == null
// // //                             ? Colors.black87
// // //                             : Colors.red,
// // //                       ),
// // //                     ),
// // //                   ),
// // //                   IconButton(
// // //                     icon: const Icon(Icons.refresh, size: 18),
// // //                     tooltip: 'Refresh from ESP32',
// // //                     onPressed: _espLoading ? null : _fetchEspPackets,
// // //                   ),
// // //                 ],
// // //               ),
// //
// // //               // Optional: show first packet raw for debugging
// // //               if (_espPackets.isNotEmpty) ...[
// // //                 const SizedBox(height: 4),
// // //                 Text(
// // //                   'First packet (raw): ${_espPackets.first}',
// // //                   maxLines: 2,
// // //                   overflow: TextOverflow.ellipsis,
// // //                   style: const TextStyle(
// // //                     fontSize: 10,
// // //                     fontFamily: 'monospace',
// // //                     color: Colors.black54,
// // //                   ),
// // //                 ),
// // //               ],
// // //             ],
// // //           ),
// // //         ),
// //
// // //         const Divider(height: 1),
// //
// // //         // Sequential list of messages
// // //         Expanded(
// // //           child: _espPackets.isEmpty
// // //               ? const Center(
// // //                   child: Text(
// // //                     'Waiting for parcels...',
// // //                     style: TextStyle(fontSize: 12),
// // //                   ),
// // //                 )
// // //               : ListView.builder(
// // //                   itemCount: _espPackets.length,
// // //                   itemBuilder: (context, index) {
// // //                     // newest at bottom, oldest at top
// // //                     final packet = _espPackets[index];
// //
// // //                     final id = packet['id']?.toString() ?? 'unknown';
// // //                     // try a couple of common keys: msg, message, status, raw
// // //                     final msg = (packet['msg'] ??
// // //                             packet['message'] ??
// // //                             packet['status'] ??
// // //                             packet['raw'] ??
// // //                             packet.toString())
// // //                         .toString();
// // //                     final ts = packet['timestamp']?.toString();
// //
// // //                     return ListTile(
// // //                       dense: true,
// // //                       title: Text(
// // //                         id,
// // //                         style: const TextStyle(
// // //                           fontSize: 12,
// // //                           fontWeight: FontWeight.w600,
// // //                         ),
// // //                       ),
// // //                       subtitle: Text(
// // //                         ts != null ? '$msg\n$ts' : msg,
// // //                         style: const TextStyle(fontSize: 11),
// // //                       ),
// // //                     );
// // //                   },
// // //                 ),
// // //         ),
// // //       ],
// // //     ),
// // //   );
// // // }
// //
// //
// //   // // --- Packages card using _espPackets from /packets ---
// //   // Widget _buildPackagesCard() {
// //   //   final latest = _espPackets.isNotEmpty ? _espPackets.last : null;
// //
// //   //   return Card(
// //   //     margin: const EdgeInsets.all(8),
// //   //     color: const Color(0xFFF7F3FF),
// //   //     child: Column(
// //   //       crossAxisAlignment: CrossAxisAlignment.stretch,
// //   //       children: [
// //   //         // Header
// //   //         Container(
// //   //           padding: const EdgeInsets.all(8),
// //   //           color: Colors.black87,
// //   //           child: const Text(
// //   //             'Packages',
// //   //             style: TextStyle(
// //   //               fontSize: 14,
// //   //               fontWeight: FontWeight.bold,
// //   //               color: Colors.white,
// //   //             ),
// //   //           ),
// //   //         ),
// //
// //   //         // Status / error row
// //   //         Padding(
// //   //           padding: const EdgeInsets.all(8.0),
// //   //           child: Row(
// //   //             children: [
// //   //               if (_espLoading)
// //   //                 const SizedBox(
// //   //                   width: 16,
// //   //                   height: 16,
// //   //                   child: CircularProgressIndicator(strokeWidth: 2),
// //   //                 )
// //   //               else
// //   //                 const Icon(Icons.cloud_download, size: 16),
// //   //               const SizedBox(width: 8),
// //   //               Expanded(
// //   //                 child: Text(
// //   //                   _espError ??
// //   //                       (_espPackets.isEmpty
// //   //                           ? 'Waiting for parcels...'
// //   //                           : 'Packets: ${_espPackets.length}'
// //   //                             '${latest != null && latest["id"] != null ? " | Latest: ${latest["id"]}" : ""}'),
// //   //                   style: TextStyle(
// //   //                     fontSize: 11,
// //   //                     color: _espError == null ? Colors.black87 : Colors.red,
// //   //                   ),
// //   //                 ),
// //   //               ),
// //   //               IconButton(
// //   //                 icon: const Icon(Icons.refresh, size: 18),
// //   //                 tooltip: 'Refresh from ESP32',
// //   //                 onPressed: _espLoading ? null : _fetchEspPackets,
// //   //               ),
// //   //             ],
// //   //           ),
// //   //         ),
// //
// //   //         const Divider(height: 1),
// //
// //   //         // Sequential list of messages
// //   //         Expanded(
// //   //           child: _espPackets.isEmpty
// //   //               ? const Center(
// //   //                   child: Text(
// //   //                     'Waiting for parcels...',
// //   //                     style: TextStyle(fontSize: 12),
// //   //                   ),
// //   //                 )
// //   //               : ListView.builder(
// //   //                   itemCount: _espPackets.length,
// //   //                   itemBuilder: (context, index) {
// //   //                     // newest at bottom, oldest at top
// //   //                     final packet = _espPackets[index];
// //
// //   //                     final id = packet['id']?.toString() ?? 'unknown';
// //   //                     // try a couple of common keys: msg, message, status, raw
// //   //                     final msg = (packet['msg'] ??
// //   //                             packet['message'] ??
// //   //                             packet['status'] ??
// //   //                             packet['raw'] ??
// //   //                             packet.toString())
// //   //                         .toString();
// //   //                     final ts = packet['timestamp']?.toString();
// //
// //   //                     return ListTile(
// //   //                       dense: true,
// //   //                       title: Text(
// //   //                         id,
// //   //                         style: const TextStyle(
// //   //                           fontSize: 12,
// //   //                           fontWeight: FontWeight.w600,
// //   //                         ),
// //   //                       ),
// //   //                       subtitle: Text(
// //   //                         ts != null ? '$msg\n$ts' : msg,
// //   //                         style: const TextStyle(fontSize: 11),
// //   //                       ),
// //   //                     );
// //   //                   },
// //   //                 ),
// //   //         ),
// //   //       ],
// //   //     ),
// //   //   );
// //   // }
// //
// //   // --- Livestream (snapshot-based) ---
// //   Widget _buildStream() {
// //     final url = _buildSnapshotUrl();
// //     return Image.network(
// //       url,
// //       fit: BoxFit.cover,
// //       errorBuilder: (context, error, stackTrace) {
// //         return Center(
// //           child: Text(
// //             'Livestream failed to load.\nURL: $url\nError: $error',
// //             textAlign: TextAlign.center,
// //             style: const TextStyle(fontSize: 12, color: Colors.red),
// //           ),
// //         );
// //       },
// //     );
// //   }
// //
// //   // --- Livemap ---
// //   Widget _buildMapStream() {
// //     final url = _buildMapUrl();
// //     return Image.network(
// //       url,
// //       fit: BoxFit.cover,
// //       errorBuilder: (context, error, stackTrace) {
// //         return Center(
// //           child: Text(
// //             'Livemap failed to load.\nURL: $url\nError: $error',
// //             textAlign: TextAlign.center,
// //             style: const TextStyle(fontSize: 12, color: Colors.red),
// //           ),
// //         );
// //       },
// //     );
// //   }
// // }
//
// // // lib/pages/dashboard_page_route.dart
//
// // import 'dart:async';
// // import 'dart:convert';
// // import 'package:flutter/material.dart';
// // import 'package:http/http.dart' as http;
//
// // import '../routes.dart';
//
// // class DashboardPageRoute extends StatefulWidget {
// //   const DashboardPageRoute({super.key});
//
// //   @override
// //   State<DashboardPageRoute> createState() => _DashboardPageRouteState();
// // }
//
// // class _DashboardPageRouteState extends State<DashboardPageRoute> {
// //   // ---------- ESP32 mini-HTTP /packets ----------
//
// //   // Replace this with your ESP32 IP from Serial (WiFi.localIP())
// //   static const String _espBaseUrl = '172.20.10.9';
//
// //   bool _espLoading = false;
// //   String? _espError;
// //   List<Map<String, dynamic>> _espPackets = [];
//
// //   // ---------- Livestream / Livemap (Pi) ----------
//
// //   // Camera snapshots (MJPG-streamer or similar)
// //   final String _piStreamPath = '172.20.10.7:8080/?action=snapshot';
//
// //   // Live-Map images (fake_livemap_server.py or ESP32 map endpoint)
// //   final String _piLiveMapPath = '172.20.10.7:8000/frame/next';
//
// //   Timer? _refreshTimer;
//
// //   @override
// //   void initState() {
// //     super.initState();
//
// //     // Initial load from ESP32
// //     _fetchEspPackets();
//
// //     // Periodic refresh: packets + images cache-buster
// //     _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
// //       if (!mounted) return;
// //       _fetchEspPackets();
// //       setState(() {
// //         // rebuild so snapshot/map URLs get new timestamps
// //       });
// //     });
// //   }
//
// //   @override
// //   void dispose() {
// //     _refreshTimer?.cancel();
// //     super.dispose();
// //   }
//
//
// //   // ========== HTTP: fetch /packets from ESP32 ==========
// //   Future<void> _fetchEspPackets() async {
// //   setState(() {
// //     _espLoading = true;
// //     _espError = null;
// //   });
//
// //   try {
// //     final uri = Uri.parse('$_espBaseUrl/packets');
// //     debugPrint('[_fetchEspPackets] GET $uri');
//
// //     final resp = await http.get(uri).timeout(const Duration(seconds: 3));
//
// //     debugPrint('[_fetchEspPackets] status = ${resp.statusCode}');
// //     debugPrint('[_fetchEspPackets] body   = ${resp.body}');
//
// //     if (resp.statusCode == 200) {
// //       final decoded = jsonDecode(resp.body);
//
// //       // Try to handle both common shapes:
// //       // 1) [ { ... }, { ... } ]
// //       // 2) { "history": [ { ... } ] }
// //       List<dynamic> rawList;
// //       if (decoded is List) {
// //         rawList = decoded;
// //       } else if (decoded is Map && decoded['history'] is List) {
// //         rawList = decoded['history'] as List;
// //       } else {
// //         setState(() {
// //           _espError = 'Unexpected JSON (not a list/history): ${decoded.runtimeType}';
// //           _espPackets = [];
// //         });
// //         return;
// //       }
//
// //       final packets = rawList.map<Map<String, dynamic>>((e) {
// //         if (e is Map) {
// //           return Map<String, dynamic>.from(e);
// //         } else {
// //           // if ESP32 ever returns plain strings, wrap them
// //           return <String, dynamic>{'raw': e.toString()};
// //         }
// //       }).toList();
//
// //       debugPrint('[_fetchEspPackets] decoded ${packets.length} packets');
//
// //       setState(() {
// //         _espPackets = packets;
// //       });
// //     } else {
// //       setState(() {
// //         _espError = 'HTTP error: ${resp.statusCode}';
// //         _espPackets = [];
// //       });
// //     }
// //   } catch (e) {
// //     setState(() {
// //       _espError = 'Request failed: $e';
// //       _espPackets = [];
// //     });
// //   } finally {
// //     if (mounted) {
// //       setState(() {
// //         _espLoading = false;
// //       });
// //     }
// //   }
// // }
//
// //   // Future<void> _fetchEspPackets() async {
// //   //   setState(() {
// //   //     _espLoading = true;
// //   //     _espError = null;
// //   //   });
//
// //   //   try {
// //   //     final uri = Uri.parse('$_espBaseUrl/packets');
// //   //     final resp = await http.get(uri).timeout(const Duration(seconds: 3));
//
// //   //     if (resp.statusCode == 200) {
// //   //       final decoded = jsonDecode(resp.body);
//
// //   //       if (decoded is List) {
// //   //         final packets = decoded
// //   //             .map<Map<String, dynamic>>(
// //   //                 (e) => Map<String, dynamic>.from(e as Map))
// //   //             .toList();
//
// //   //         setState(() {
// //   //           _espPackets = packets;
// //   //         });
// //   //       } else {
// //   //         setState(() {
// //   //           _espError = 'Unexpected JSON format (expected list)';
// //   //         });
// //   //       }
// //   //     } else {
// //   //       setState(() {
// //   //         _espError = 'HTTP error: ${resp.statusCode}';
// //   //       });
// //   //     }
// //   //   } catch (e) {
// //   //     setState(() {
// //   //       _espError = 'Request failed: $e';
// //   //     });
// //   //   } finally {
// //   //     if (mounted) {
// //   //       setState(() {
// //   //         _espLoading = false;
// //   //       });
// //   //     }
// //   //   }
// //   // }
//
// //   // ========== Livestream / Livemap helpers ==========
//
// //   String _buildSnapshotUrl() {
// //     final base = 'http://$_piStreamPath';
// //     final sep = base.contains('?') ? '&' : '?';
// //     final ts = DateTime.now().millisecondsSinceEpoch;
// //     return '$base${sep}ts=$ts';
// //   }
//
// //   String _buildMapUrl() {
// //     final base = 'http://$_piLiveMapPath';
// //     final sep = base.contains('?') ? '&' : '?';
// //     final ts = DateTime.now().millisecondsSinceEpoch;
// //     return '$base${sep}ts=$ts';
// //   }
//
// //   void _refreshStream() {
// //     setState(() {
// //       // Just forces rebuild; URLs get new ts
// //     });
// //   }
//
// //   void _signOut() {
// //     if (!mounted) return;
// //     Navigator.of(context).pushReplacementNamed(PageRoutes.welcome);
// //   }
//
// //   // ========== UI ==========
//
// //   @override
// //   Widget build(BuildContext context) {
// //     return Scaffold(
// //       appBar: AppBar(
// //         title: const Text('PARCEL Dashboard'),
// //         actions: [
// //           IconButton(
// //             icon: const Icon(Icons.logout),
// //             onPressed: _signOut,
// //             tooltip: 'Sign out',
// //           ),
// //         ],
// //       ),
// //       body: SafeArea(
// //         child: Row(
// //           crossAxisAlignment: CrossAxisAlignment.stretch,
// //           children: [
// //             // -------- LEFT: Packages card (HTTP from ESP32) --------
// //             SizedBox(
// //               width: 260,
// //               child: _buildPackagesCard(),
// //             ),
//
// //             // -------- CENTER: Livestream + Livemap --------
// //             Expanded(
// //               child: Column(
// //                 children: [
// //                   // --- Livestream (camera snapshots) ---
// //                   Expanded(
// //                     flex: 4,
// //                     child: Container(
// //                       margin: const EdgeInsets.symmetric(
// //                         horizontal: 8,
// //                         vertical: 4,
// //                       ),
// //                       decoration: _roundedBoxDecoration(),
// //                       child: Padding(
// //                         padding: const EdgeInsets.all(8.0),
// //                         child: Column(
// //                           crossAxisAlignment: CrossAxisAlignment.stretch,
// //                           children: [
// //                             Row(
// //                               children: [
// //                                 const Icon(Icons.videocam, size: 18),
// //                                 const SizedBox(width: 8),
// //                                 const Text(
// //                                   'Livestream (Camera Snapshots)',
// //                                   style: TextStyle(
// //                                     fontWeight: FontWeight.w600,
// //                                   ),
// //                                 ),
// //                                 const Spacer(),
// //                                 IconButton(
// //                                   icon: const Icon(Icons.refresh),
// //                                   onPressed: _refreshStream,
// //                                   tooltip: 'Refresh Snapshot',
// //                                 ),
// //                               ],
// //                             ),
// //                             const SizedBox(height: 8),
// //                             Card(
// //                               color: Colors.blue.shade50,
// //                               child: Padding(
// //                                 padding: const EdgeInsets.all(8.0),
// //                                 child: Column(
// //                                   crossAxisAlignment: CrossAxisAlignment.start,
// //                                   children: [
// //                                     const Text(
// //                                       'Livestream base URL:',
// //                                       style: TextStyle(
// //                                         fontWeight: FontWeight.w600,
// //                                         fontSize: 12,
// //                                       ),
// //                                     ),
// //                                     const SizedBox(height: 4),
// //                                     Text(
// //                                       'http://$_piStreamPath',
// //                                       style: const TextStyle(
// //                                         fontSize: 12,
// //                                         fontFamily: 'monospace',
// //                                       ),
// //                                     ),
// //                                   ],
// //                                 ),
// //                               ),
// //                             ),
// //                             const SizedBox(height: 8),
// //                             Expanded(
// //                               child: Card(
// //                                 elevation: 2,
// //                                 clipBehavior: Clip.antiAlias,
// //                                 child: Column(
// //                                   crossAxisAlignment:
// //                                       CrossAxisAlignment.stretch,
// //                                   children: [
// //                                     Container(
// //                                       color: Colors.black12,
// //                                       padding: const EdgeInsets.symmetric(
// //                                         horizontal: 12,
// //                                         vertical: 8,
// //                                       ),
// //                                       child: const Row(
// //                                         children: [
// //                                           Icon(Icons.camera_alt, size: 18),
// //                                           SizedBox(width: 8),
// //                                           Text(
// //                                             'Livestream',
// //                                             style: TextStyle(
// //                                               fontWeight: FontWeight.w600,
// //                                             ),
// //                                           ),
// //                                         ],
// //                                       ),
// //                                     ),
// //                                     Expanded(child: _buildStream()),
// //                                   ],
// //                                 ),
// //                               ),
// //                             ),
// //                           ],
// //                         ),
// //                       ),
// //                     ),
// //                   ),
//
// //                   // --- Livemap ---
// //                   Expanded(
// //                     flex: 3,
// //                     child: Container(
// //                       margin: const EdgeInsets.symmetric(
// //                         horizontal: 8,
// //                         vertical: 4,
// //                       ),
// //                       decoration: _roundedBoxDecoration(),
// //                       child: Padding(
// //                         padding: const EdgeInsets.all(8.0),
// //                         child: Card(
// //                           elevation: 2,
// //                           clipBehavior: Clip.antiAlias,
// //                           child: Column(
// //                             crossAxisAlignment: CrossAxisAlignment.stretch,
// //                             children: [
// //                               Container(
// //                                 color: Colors.black12,
// //                                 padding: const EdgeInsets.symmetric(
// //                                   horizontal: 12,
// //                                   vertical: 8,
// //                                 ),
// //                                 child: const Row(
// //                                   children: [
// //                                     Icon(Icons.map, size: 18),
// //                                     SizedBox(width: 8),
// //                                     Text(
// //                                       'Livemap',
// //                                       style: TextStyle(
// //                                         fontWeight: FontWeight.w600,
// //                                       ),
// //                                     ),
// //                                   ],
// //                                 ),
// //                               ),
// //                               Padding(
// //                                 padding: const EdgeInsets.all(8.0),
// //                                 child: Text(
// //                                   'Livemap base URL: http://$_piLiveMapPath',
// //                                   style: const TextStyle(
// //                                     fontSize: 11,
// //                                     fontFamily: 'monospace',
// //                                   ),
// //                                 ),
// //                               ),
// //                               Expanded(child: _buildMapStream()),
// //                             ],
// //                           ),
// //                         ),
// //                       ),
// //                     ),
// //                   ),
// //                 ],
// //               ),
// //             ),
// //           ],
// //         ),
// //       ),
// //     );
// //   }
//
// //   // ---------- UI helpers ----------
//
// //   BoxDecoration _roundedBoxDecoration() {
// //     return BoxDecoration(
// //       borderRadius: BorderRadius.circular(18),
// //       border: Border.all(color: Colors.black54, width: 1.5),
// //     );
// //   }
//
// //   // --- Packages card using _espPackets from /packets ---
// //   // Widget _buildPackagesCard() {
// //   //   final latest =
// //   //       _espPackets.isNotEmpty ? _espPackets.last : null; // newest
//
// //   //   return Card(
// //   //     margin: const EdgeInsets.all(8),
// //   //     child: Column(
// //   //       crossAxisAlignment: CrossAxisAlignment.stretch,
// //   //       children: [
// //   //         // Header
// //   //         Container(
// //   //           padding: const EdgeInsets.all(8),
// //   //           color: Colors.deepPurple.shade700,
// //   //           child: const Text(
// //   //             'Packages (ESP32 /packets)',
// //   //             style: TextStyle(
// //   //               fontSize: 14,
// //   //               fontWeight: FontWeight.bold,
// //   //               color: Colors.white,
// //   //             ),
// //   //           ),
// //   //         ),
//
// //   //         // Status + refresh
// //   //         Padding(
// //   //           padding: const EdgeInsets.all(8.0),
// //   //           child: Row(
// //   //             children: [
// //   //               if (_espLoading)
// //   //                 const SizedBox(
// //   //                   width: 16,
// //   //                   height: 16,
// //   //                   child: CircularProgressIndicator(strokeWidth: 2),
// //   //                 )
// //   //               else
// //   //                 const Icon(Icons.cloud_download, size: 16),
// //   //               const SizedBox(width: 8),
// //   //               Expanded(
// //   //                 child: Text(
// //   //                   _espError ??
// //   //                       'Packets: ${_espPackets.length}'
// //   //                           '${latest != null ? " | Latest status: ${latest["status"] ?? "?"}" : ""}',
// //   //                   style: TextStyle(
// //   //                     fontSize: 11,
// //   //                     color: _espError == null ? Colors.black87 : Colors.red,
// //   //                   ),
// //   //                 ),
// //   //               ),
// //   //               IconButton(
// //   //                 icon: const Icon(Icons.refresh, size: 18),
// //   //                 tooltip: 'Refresh from ESP32',
// //   //                 onPressed: _espLoading ? null : _fetchEspPackets,
// //   //               ),
// //   //             ],
// //   //           ),
// //   //         ),
//
// //   //         const Divider(height: 1),
//
// //   //         // List of packets
// //   //         Expanded(
// //   //           child: _espPackets.isEmpty
// //   //               ? const Padding(
// //   //                   padding: EdgeInsets.all(8.0),
// //   //                   child: Text(
// //   //                     'No packets yet.\nCheck ESP32 /packets endpoint.',
// //   //                     style: TextStyle(fontSize: 11),
// //   //                   ),
// //   //                 )
// //   //               : ListView.builder(
// //   //                   itemCount: _espPackets.length,
// //   //                   itemBuilder: (context, index) {
// //   //                     // newest first
// //   //                     final p =
// //   //                         _espPackets[_espPackets.length - 1 - index];
// //   //                     final id = p['id'] ?? '?';
// //   //                     final status = p['status'] ?? 'unknown';
// //   //                     final value = p['value'] ?? '?';
// //   //                     final ts = p['timestamp']?.toString() ?? '?';
//
// //   //                     return ListTile(
// //   //                       dense: true,
// //   //                       title: Text(
// //   //                         'Packet #$id | status: $status',
// //   //                         style: const TextStyle(fontSize: 12),
// //   //                       ),
// //   //                       subtitle: Text(
// //   //                         'value: $value | ts: $ts',
// //   //                         style: const TextStyle(fontSize: 11),
// //   //                       ),
// //   //                     );
// //   //                   },
// //   //                 ),
// //   //         ),
// //   //       ],
// //   //     ),
// //   //   );
// //   // }
// //   Widget _buildPackagesCard() {
// //   final latest = _espPackets.isNotEmpty ? _espPackets.last : null;
//
// //   return Card(
// //     margin: const EdgeInsets.all(8),
// //     color: const Color(0xFFF7F3FF),
// //     child: Column(
// //       crossAxisAlignment: CrossAxisAlignment.stretch,
// //       children: [
// //         // Header
// //         Container(
// //           padding: const EdgeInsets.all(8),
// //           color: Colors.black87,
// //           child: const Text(
// //             'Packages',
// //             style: TextStyle(
// //               fontSize: 14,
// //               fontWeight: FontWeight.bold,
// //               color: Colors.white,
// //             ),
// //           ),
// //         ),
//
// //         // Status / error row
// //         Padding(
// //           padding: const EdgeInsets.all(8.0),
// //           child: Row(
// //             children: [
// //               if (_espLoading)
// //                 const SizedBox(
// //                   width: 16,
// //                   height: 16,
// //                   child: CircularProgressIndicator(strokeWidth: 2),
// //                 )
// //               else
// //                 const Icon(Icons.cloud_download, size: 16),
// //               const SizedBox(width: 8),
// //               Expanded(
// //                 child: Text(
// //                   _espError ??
// //                       (_espPackets.isEmpty
// //                           ? 'Waiting for parcels...'
// //                           : 'Packets: ${_espPackets.length}'
// //                             '${latest != null && latest["id"] != null ? " | Latest: ${latest["id"]}" : ""}'),
// //                   style: TextStyle(
// //                     fontSize: 11,
// //                     color: _espError == null ? Colors.black87 : Colors.red,
// //                   ),
// //                 ),
// //               ),
// //               IconButton(
// //                 icon: const Icon(Icons.refresh, size: 18),
// //                 tooltip: 'Refresh from ESP32',
// //                 onPressed: _espLoading ? null : _fetchEspPackets,
// //               ),
// //             ],
// //           ),
// //         ),
//
// //         const Divider(height: 1),
//
// //         // Sequential list of messages
// //         Expanded(
// //           child: _espPackets.isEmpty
// //               ? const Center(
// //                   child: Text(
// //                     'Waiting for parcels...',
// //                     style: TextStyle(fontSize: 12),
// //                   ),
// //                 )
// //               : ListView.builder(
// //                   itemCount: _espPackets.length,
// //                   itemBuilder: (context, index) {
// //                     // newest at bottom, oldest at top
// //                     final packet = _espPackets[index];
//
// //                     final id = packet['id']?.toString() ?? 'unknown';
// //                     // try a couple of common keys: msg, message, status, raw
// //                     final msg = (packet['msg'] ??
// //                             packet['message'] ??
// //                             packet['status'] ??
// //                             packet['raw'] ??
// //                             packet.toString())
// //                         .toString();
// //                     final ts = packet['timestamp']?.toString();
//
// //                     return ListTile(
// //                       dense: true,
// //                       title: Text(
// //                         id,
// //                         style: const TextStyle(
// //                           fontSize: 12,
// //                           fontWeight: FontWeight.w600,
// //                         ),
// //                       ),
// //                       subtitle: Text(
// //                         ts != null ? '$msg\n$ts' : msg,
// //                         style: const TextStyle(fontSize: 11),
// //                       ),
// //                     );
// //                   },
// //                 ),
// //         ),
// //       ],
// //     ),
// //   );
// // }
//
//
// //   // --- Livestream (snapshot-based) ---
// //   Widget _buildStream() {
// //     final url = _buildSnapshotUrl();
// //     return Image.network(
// //       url,
// //       fit: BoxFit.cover,
// //       errorBuilder: (context, error, stackTrace) {
// //         return Center(
// //           child: Text(
// //             'Livestream failed to load.\nURL: $url\nError: $error',
// //             textAlign: TextAlign.center,
// //             style: const TextStyle(fontSize: 12, color: Colors.red),
// //           ),
// //         );
// //       },
// //     );
// //   }
//
// //   // --- Livemap ---
// //   Widget _buildMapStream() {
// //     final url = _buildMapUrl();
// //     return Image.network(
// //       url,
// //       fit: BoxFit.cover,
// //       errorBuilder: (context, error, stackTrace) {
// //         return Center(
// //           child: Text(
// //             'Livemap failed to load.\nURL: $url\nError: $error',
// //             textAlign: TextAlign.center,
// //             style: const TextStyle(fontSize: 12, color: Colors.red),
// //           ),
// //         );
// //       },
// //     );
// //   }
// // }
//
// // // lib/pages/dashboard_page_route.dart
// // // or lib/pages/dashboard.dart – just be consistent with imports/routes.
//
// // import 'dart:async';
// // import 'package:flutter/material.dart';
//
// // import 'package:mqtt_client/mqtt_client.dart' as mqtt;
// // import 'package:mqtt_client/mqtt_server_client.dart';
//
// // import '../routes.dart';
// // import 'dart:convert';                // for jsonDecode
// // import 'package:http/http.dart' as http;  // HTTP client
//
//
// // enum ConnectionStatus { idle, connecting, ok, error }
//
// // class DashboardPageRoute extends StatefulWidget {
// //   const DashboardPageRoute({super.key});
//
// //   @override
// //   State<DashboardPageRoute> createState() => _DashboardPageRouteState();
// // }
//
// // class _DashboardPageRouteState extends State<DashboardPageRoute> {
// //   // ---------- MQTT (single-file, debug-oriented) ----------
//
// //   late MqttServerClient _mqttClient;
// //   bool _mqttClientInitialized = false;
//
// //   ConnectionStatus _mqttStatus = ConnectionStatus.idle;
// //   String? _mqttError;
// //   final List<String> _mqttMessages = [];
//
// //   // Adjust these to your broker:
// //   static const String _mqttHost = 'broker.emqx.io'; // or your Pi IP / EMQX host
// //   static const int _mqttPort = 1883;                // or your TLS port if needed
// //   static const String _mqttTopic = 'parcel/test';   // change to your topic
//
// //   // ---------- Livestream / Livemap ----------
//
// //   // Camera snapshots (MJPG-streamer or similar)
// //   final String _piStreamPath = '172.20.10.7:8080/?action=snapshot';
//
// //   // Live-Map fake images (served by fake_livemap_server.py)
// //   final String _piLiveMapPath = '172.20.10.7:8000/frame/next';
//
// //   Timer? _snapshotTimer;
//
// //   @override
// //   void initState() {
// //     super.initState();
//
// //     _initMqtt();
//
// //     // Periodic refresh for both camera + live-map
// //     _snapshotTimer = Timer.periodic(const Duration(seconds: 5), (_) {
// //       if (!mounted) return;
// //       setState(() {
// //         // Rebuild; URLs get new cache-busting timestamps.
// //       });
// //     });
// //   }
//
// //   @override
// //   void dispose() {
// //     _snapshotTimer?.cancel();
// //     if (_mqttClientInitialized) {
// //       _mqttClient.disconnect();
// //     }
// //     super.dispose();
// //   }
//
// //   // ========== MQTT logic (debug-focused) ==========
//
// //   Future<void> _initMqtt() async {
// //     // Avoid double-initialization if something calls this again.
// //     _mqttClientInitialized = true;
//
// //     final clientId = 'parcel-dashboard-${DateTime.now().millisecondsSinceEpoch}';
//
// //     setState(() {
// //       _mqttStatus = ConnectionStatus.connecting;
// //       _mqttError = null;
// //     });
//
// //     _mqttClient = MqttServerClient(_mqttHost, clientId);
// //     _mqttClient.port = _mqttPort;
// //     _mqttClient.keepAlivePeriod = 30;
// //     _mqttClient.logging(on: false);
// //     _mqttClient.secure = false; // set to true + configure security if you use TLS
// //     _mqttClient.setProtocolV311();
//
// //     _mqttClient.onConnected = _onMqttConnected;
// //     _mqttClient.onDisconnected = _onMqttDisconnected;
//
// //     final connMess = mqtt.MqttConnectMessage()
// //         .withClientIdentifier(clientId)
// //         .startClean()
// //         .withWillQos(mqtt.MqttQos.atLeastOnce);
//
// //     _mqttClient.connectionMessage = connMess;
//
// //     try {
// //       final result = await _mqttClient.connect();
//
// //       if (!mounted) return;
//
// //       if (result?.connectionStatus.state ==
// //           mqtt.MqttConnectionState.connected) {
// //         setState(() {
// //           _mqttStatus = ConnectionStatus.ok;
// //           _mqttError = null;
// //         });
// //         _subscribeToTopic(_mqttTopic);
// //       } else {
// //         setState(() {
// //           _mqttStatus = ConnectionStatus.error;
// //           _mqttError =
// //               'Connect failed: ${result?.connectionStatus.state.toString()}';
// //         });
// //         _mqttClient.disconnect();
// //       }
// //     } catch (e) {
// //       if (!mounted) return;
// //       setState(() {
// //         _mqttStatus = ConnectionStatus.error;
// //         _mqttError = 'Exception while connecting: $e';
// //       });
// //       _mqttClient.disconnect();
// //     }
// //   }
//
// //   void _onMqttConnected() {
// //     // Optional: log or SnackBar.
// //   }
//
// //   void _onMqttDisconnected() {
// //     if (!mounted) return;
// //     setState(() {
// //       _mqttStatus = ConnectionStatus.error;
// //       _mqttError ??= 'Disconnected from broker.';
// //     });
//
// //     // Very simple auto-reconnect after a delay
// //     Future.delayed(const Duration(seconds: 5), () {
// //       if (!mounted) return;
// //       _initMqtt();
// //     });
// //   }
//
// //   void _subscribeToTopic(String topic) {
// //     _mqttClient.subscribe(topic, mqtt.MqttQos.atMostOnce);
//
// //     _mqttClient.updates?.listen((events) {
// //       if (events.isEmpty) return;
// //       final recMess = events.first.payload as mqtt.MqttPublishMessage;
// //       final payload =
// //           mqtt.MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
//
// //       final msg = '[${events.first.topic}] $payload';
//
// //       if (!mounted) return;
// //       setState(() {
// //         _mqttMessages.insert(0, msg);
// //         if (_mqttMessages.length > 200) {
// //           _mqttMessages.removeLast();
// //         }
// //       });
// //     });
// //   }
//
// //   void _manualReconnect() {
// //     if (!_mqttClientInitialized) {
// //       _initMqtt();
// //       return;
// //     }
//
// //     try {
// //       _mqttClient.disconnect();
// //     } catch (_) {
// //       // ignore
// //     }
// //     _initMqtt();
// //   }
//
// //   // ========== Livestream / Livemap helpers ==========
//
// //   String _buildSnapshotUrl() {
// //     final base = 'http://$_piStreamPath';
// //     final sep = base.contains('?') ? '&' : '?';
// //     final ts = DateTime.now().millisecondsSinceEpoch;
// //     return '$base${sep}ts=$ts';
// //   }
//
// //   String _buildMapUrl() {
// //     final base = 'http://$_piLiveMapPath';
// //     final sep = base.contains('?') ? '&' : '?';
// //     final ts = DateTime.now().millisecondsSinceEpoch;
// //     return '$base${sep}ts=$ts';
// //   }
//
// //   void _refreshStream() {
// //     setState(() {
// //       // Just forces a rebuild; URLs get new ts values.
// //     });
// //   }
//
// //   void _signOut() {
// //     if (!mounted) return;
// //     Navigator.of(context).pushReplacementNamed(PageRoutes.welcome);
// //   }
//
// //   // ========== UI ==========
//
// //   @override
// //   Widget build(BuildContext context) {
// //     return Scaffold(
// //       appBar: AppBar(
// //         title: const Text('PARCEL Dashboard (Debug View)'),
// //         actions: [
// //           IconButton(
// //             icon: const Icon(Icons.logout),
// //             onPressed: _signOut,
// //             tooltip: 'Sign out',
// //           ),
// //         ],
// //       ),
// //       body: SafeArea(
// //         child: Row(
// //           crossAxisAlignment: CrossAxisAlignment.stretch,
// //           children: [
// //             // -------- LEFT: MQTT status + messages --------
// //             SizedBox(
// //               width: 260,
// //               child: _buildMqttDebugColumn(),
// //             ),
//
// //             // -------- CENTER: Livestream + Livemap --------
// //             Expanded(
// //               child: Column(
// //                 children: [
// //                   // --- Livestream (camera snapshots) ---
// //                   Expanded(
// //                     flex: 4,
// //                     child: Container(
// //                       margin: const EdgeInsets.symmetric(
// //                         horizontal: 8,
// //                         vertical: 4,
// //                       ),
// //                       decoration: _roundedBoxDecoration(),
// //                       child: Padding(
// //                         padding: const EdgeInsets.all(8.0),
// //                         child: Column(
// //                           crossAxisAlignment: CrossAxisAlignment.stretch,
// //                           children: [
// //                             Row(
// //                               children: [
// //                                 const Icon(Icons.videocam, size: 18),
// //                                 const SizedBox(width: 8),
// //                                 const Text(
// //                                   'Livestream (Camera Snapshots)',
// //                                   style: TextStyle(
// //                                     fontWeight: FontWeight.w600,
// //                                   ),
// //                                 ),
// //                                 const Spacer(),
// //                                 IconButton(
// //                                   icon: const Icon(Icons.refresh),
// //                                   onPressed: _refreshStream,
// //                                   tooltip: 'Refresh Snapshot',
// //                                 ),
// //                               ],
// //                             ),
// //                             const SizedBox(height: 8),
//
// //                             Card(
// //                               color: Colors.blue.shade50,
// //                               child: Padding(
// //                                 padding: const EdgeInsets.all(8.0),
// //                                 child: Column(
// //                                   crossAxisAlignment: CrossAxisAlignment.start,
// //                                   children: [
// //                                     const Text(
// //                                       'Livestream base URL:',
// //                                       style: TextStyle(
// //                                         fontWeight: FontWeight.w600,
// //                                         fontSize: 12,
// //                                       ),
// //                                     ),
// //                                     const SizedBox(height: 4),
// //                                     Text(
// //                                       'http://$_piStreamPath',
// //                                       style: const TextStyle(
// //                                         fontSize: 12,
// //                                         fontFamily: 'monospace',
// //                                       ),
// //                                     ),
// //                                     const SizedBox(height: 4),
// //                                     const Text(
// //                                       'Polled every 5 seconds with a ts cache-buster.\n'
// //                                       'If this fails: check Pi IP, port 8080, and MJPG-streamer.',
// //                                       style: TextStyle(fontSize: 11),
// //                                     ),
// //                                   ],
// //                                 ),
// //                               ),
// //                             ),
// //                             const SizedBox(height: 8),
//
// //                             Expanded(
// //                               child: Card(
// //                                 elevation: 2,
// //                                 clipBehavior: Clip.antiAlias,
// //                                 child: Column(
// //                                   crossAxisAlignment:
// //                                       CrossAxisAlignment.stretch,
// //                                   children: [
// //                                     Container(
// //                                       color: Colors.black12,
// //                                       padding: const EdgeInsets.symmetric(
// //                                         horizontal: 12,
// //                                         vertical: 8,
// //                                       ),
// //                                       child: const Row(
// //                                         children: [
// //                                           Icon(Icons.camera_alt, size: 18),
// //                                           SizedBox(width: 8),
// //                                           Text(
// //                                             'Livestream',
// //                                             style: TextStyle(
// //                                               fontWeight: FontWeight.w600,
// //                                             ),
// //                                           ),
// //                                         ],
// //                                       ),
// //                                     ),
// //                                     Expanded(
// //                                       child: _buildStream(),
// //                                     ),
// //                                   ],
// //                                 ),
// //                               ),
// //                             ),
// //                           ],
// //                         ),
// //                       ),
// //                     ),
// //                   ),
//
// //                   // --- Livemap (fake images) ---
// //                   Expanded(
// //                     flex: 3,
// //                     child: Container(
// //                       margin: const EdgeInsets.symmetric(
// //                         horizontal: 8,
// //                         vertical: 4,
// //                       ),
// //                       decoration: _roundedBoxDecoration(),
// //                       child: Padding(
// //                         padding: const EdgeInsets.all(8.0),
// //                         child: Card(
// //                           elevation: 2,
// //                           clipBehavior: Clip.antiAlias,
// //                           child: Column(
// //                             crossAxisAlignment: CrossAxisAlignment.stretch,
// //                             children: [
// //                               Container(
// //                                 color: Colors.black12,
// //                                 padding: const EdgeInsets.symmetric(
// //                                   horizontal: 12,
// //                                   vertical: 8,
// //                                 ),
// //                                 child: const Row(
// //                                   children: [
// //                                     Icon(Icons.map, size: 18),
// //                                     SizedBox(width: 8),
// //                                     Text(
// //                                       'Livemap (Fake Images)',
// //                                       style: TextStyle(
// //                                         fontWeight: FontWeight.w600,
// //                                       ),
// //                                     ),
// //                                   ],
// //                                 ),
// //                               ),
// //                               Padding(
// //                                 padding: const EdgeInsets.all(8.0),
// //                                 child: Text(
// //                                   'Livemap base URL: http://$_piLiveMapPath\n'
// //                                   'If this fails: check Pi IP and fake_livemap_server.py on port 8000.',
// //                                   style: const TextStyle(
// //                                     fontSize: 11,
// //                                     fontFamily: 'monospace',
// //                                   ),
// //                                 ),
// //                               ),
// //                               Expanded(
// //                                 child: _buildMapStream(),
// //                               ),
// //                             ],
// //                           ),
// //                         ),
// //                       ),
// //                     ),
// //                   ),
// //                 ],
// //               ),
// //             ),
// //           ],
// //         ),
// //       ),
// //     );
// //   }
//
// //   // ---------- UI helpers ----------
//
// //   BoxDecoration _roundedBoxDecoration() {
// //     return BoxDecoration(
// //       borderRadius: BorderRadius.circular(18),
// //       border: Border.all(color: Colors.black54, width: 1.5),
// //     );
// //   }
//
// //   Color _statusColor(ConnectionStatus status) {
// //     switch (status) {
// //       case ConnectionStatus.idle:
// //         return Colors.grey;
// //       case ConnectionStatus.connecting:
// //         return Colors.orange;
// //       case ConnectionStatus.ok:
// //         return Colors.green;
// //       case ConnectionStatus.error:
// //         return Colors.red;
// //     }
// //   }
//
// //   String _statusLabel(ConnectionStatus status) {
// //     switch (status) {
// //       case ConnectionStatus.idle:
// //         return 'Idle';
// //       case ConnectionStatus.connecting:
// //         return 'Connecting';
// //       case ConnectionStatus.ok:
// //         return 'Connected';
// //       case ConnectionStatus.error:
// //         return 'Error';
// //     }
// //   }
//
// //   Widget _buildMqttDebugColumn() {
// //     return Card(
// //       margin: const EdgeInsets.all(8),
// //       child: Column(
// //         crossAxisAlignment: CrossAxisAlignment.stretch,
// //         children: [
// //           Container(
// //             padding: const EdgeInsets.all(8),
// //             color: Colors.blueGrey.shade900,
// //             child: const Text(
// //               'MQTT Debug',
// //               style: TextStyle(
// //                 fontSize: 16,
// //                 fontWeight: FontWeight.bold,
// //                 color: Colors.white,
// //               ),
// //             ),
// //           ),
//
// //           // Status row
// //           Padding(
// //             padding: const EdgeInsets.all(8.0),
// //             child: Row(
// //               children: [
// //                 const Text(
// //                   'Status: ',
// //                   style: TextStyle(fontWeight: FontWeight.w600),
// //                 ),
// //                 Container(
// //                   padding:
// //                       const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
// //                   decoration: BoxDecoration(
// //                     color: _statusColor(_mqttStatus).withOpacity(0.15),
// //                     borderRadius: BorderRadius.circular(12),
// //                     border: Border.all(color: _statusColor(_mqttStatus)),
// //                   ),
// //                   child: Text(
// //                     _statusLabel(_mqttStatus),
// //                     style: TextStyle(
// //                       fontSize: 12,
// //                       color: _statusColor(_mqttStatus),
// //                     ),
// //                   ),
// //                 ),
// //                 const Spacer(),
// //                 IconButton(
// //                   icon: const Icon(Icons.refresh),
// //                   onPressed: _manualReconnect,
// //                   tooltip: 'Reconnect MQTT',
// //                 ),
// //               ],
// //             ),
// //           ),
//
// //           // Host info
// //           Padding(
// //             padding: const EdgeInsets.symmetric(horizontal: 8.0),
// //             child: Text(
// //               'Broker: $_mqttHost:$_mqttPort\nTopic: $_mqttTopic',
// //               style: const TextStyle(
// //                 fontSize: 11,
// //                 fontFamily: 'monospace',
// //               ),
// //             ),
// //           ),
//
// //           if (_mqttError != null)
// //             Padding(
// //               padding:
// //                   const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
// //               child: Text(
// //                 'Error: $_mqttError',
// //                 style: const TextStyle(
// //                   fontSize: 11,
// //                   color: Colors.red,
// //                 ),
// //               ),
// //             ),
//
// //           const Divider(),
//
// //           const Padding(
// //             padding: EdgeInsets.all(8.0),
// //             child: Text(
// //               'Recent Messages:',
// //               style: TextStyle(fontWeight: FontWeight.w600),
// //             ),
// //           ),
//
// //           Expanded(
// //             child: _mqttMessages.isEmpty
// //                 ? const Center(
// //                     child: Text(
// //                       'No messages yet.\nCheck publisher & topic.',
// //                       textAlign: TextAlign.center,
// //                       style: TextStyle(fontSize: 12),
// //                     ),
// //                   )
// //                 : ListView.builder(
// //                     itemCount: _mqttMessages.length,
// //                     itemBuilder: (context, index) {
// //                       final msg = _mqttMessages[index];
// //                       return ListTile(
// //                         dense: true,
// //                         title: Text(
// //                           msg,
// //                           maxLines: 3,
// //                           overflow: TextOverflow.ellipsis,
// //                           style: const TextStyle(fontSize: 12),
// //                         ),
// //                       );
// //                     },
// //                   ),
// //           ),
// //         ],
// //       ),
// //     );
// //   }
//
// //   // --- Livestream (snapshot-based) ---
// //   Widget _buildStream() {
// //     final url = _buildSnapshotUrl();
// //     return Image.network(
// //       url,
// //       fit: BoxFit.cover,
// //       errorBuilder: (context, error, stackTrace) {
// //         return Center(
// //           child: Text(
// //             'Livestream failed to load.\n'
// //             'URL: $url\n'
// //             'Error: $error',
// //             textAlign: TextAlign.center,
// //             style: const TextStyle(fontSize: 12, color: Colors.red),
// //           ),
// //         );
// //       },
// //     );
// //   }
//
// //   // --- Livemap (fake images) ---
// //   Widget _buildMapStream() {
// //     final url = _buildMapUrl();
// //     return Image.network(
// //       url,
// //       fit: BoxFit.cover,
// //       errorBuilder: (context, error, stackTrace) {
// //         return Center(
// //           child: Text(
// //             'Livemap failed to load.\n'
// //             'URL: $url\n'
// //             'Error: $error',
// //             textAlign: TextAlign.center,
// //             style: const TextStyle(fontSize: 12, color: Colors.red),
// //           ),
// //         );
// //       },
// //     );
// //   }
// // }
//
// // // lib/pages/dashboard.dart
//
// // import 'dart:async';
// // import 'package:flutter/material.dart';
//
// // import 'package:mqtt_client/mqtt_client.dart' as mqtt;
// // import 'package:mqtt_client/mqtt_server_client.dart';
//
// // import '../routes.dart';
//
// // class DashboardPageRoute extends StatefulWidget {
// //   const DashboardPageRoute({super.key});
//
// //   @override
// //   State<DashboardPageRoute> createState() => _DashboardPageRouteState();
// // }
//
// // class _DashboardPageRouteState extends State<DashboardPageRoute> {
// //   // -------- MQTT (self-contained) --------
// //   late MqttServerClient _mqttClient;
// //   bool _isMqttConnected = false;
//
// //   // Very simple: keep recent messages in memory and show them in the left column.
// //   final List<String> _mqttMessages = [];
//
// //   // Configure your broker here.
// //   static const String _mqttHost = 'r38d6e25.ala.us-east-1.emqxsl.com';
// //   static const int _mqttPort = 8883;
// //   static const String _mqttTopic = 'parcel/test'; // change as needed
//
// //   // --------- snapshot-based pseudo livestream / Pi camera ----------
// //   // Camera snapshots (MJPG-streamer or similar)
// //   final String _piStreamPath = '172.20.10.7:8080/?action=snapshot';
//
// //   // Live-Map fake images (served by your fake_livemap_server.py on the Pi)
// //   final String _piLiveMapPath = '172.20.10.7:8000/frame/next';
//
// //   Timer? _snapshotTimer;
//
// //   @override
// //   void initState() {
// //     super.initState();
//
// //     _initMqtt();
//
// //     // Periodic refresh for both camera + live-map
// //     _snapshotTimer = Timer.periodic(const Duration(seconds: 5), (_) {
// //       if (!mounted) return;
// //       setState(() {
// //         // triggers new URLs with fresh ts cache-buster
// //       });
// //     });
// //   }
//
// //   @override
// //   void dispose() {
// //     _snapshotTimer?.cancel();
// //     if (_isMqttConnected) {
// //       _mqttClient.disconnect();
// //     }
// //     super.dispose();
// //   }
//
// //   // ---------- MQTT setup (single-file, minimal) ----------
//
// //   Future<void> _initMqtt() async {
// //     final clientId = 'parcel-dashboard-${DateTime.now().millisecondsSinceEpoch}';
//
// //     _mqttClient = MqttServerClient(_mqttHost, clientId);
// //     _mqttClient.port = _mqttPort;
// //     _mqttClient.keepAlivePeriod = 30;
// //     _mqttClient.logging(on: false);
// //     _mqttClient.secure = false; // set true + configure security if you use TLS
// //     _mqttClient.setProtocolV311();
//
// //     _mqttClient.onConnected = _onMqttConnected;
// //     _mqttClient.onDisconnected = _onMqttDisconnected;
//
// //     final connMess = mqtt.MqttConnectMessage()
// //         .withClientIdentifier(clientId)
// //         .startClean()
// //         .withWillQos(mqtt.MqttQos.atLeastOnce);
//
// //     _mqttClient.connectionMessage = connMess;
//
// //     try {
// //       final result = await _mqttClient.connect();
// //       if (result?.connectionStatus.state ==
// //           mqtt.MqttConnectionState.connected) {
// //         setState(() {
// //           _isMqttConnected = true;
// //         });
// //         _subscribeToTopic(_mqttTopic);
// //       } else {
// //         _mqttClient.disconnect();
// //       }
// //     } catch (e) {
// //       // Connection failed; keep _isMqttConnected = false
// //       _mqttClient.disconnect();
// //     }
// //   }
//
// //   void _onMqttConnected() {
// //     // You can log or show a snack bar here if you want.
// //   }
//
// //   void _onMqttDisconnected() {
// //     if (!mounted) return;
// //     setState(() {
// //       _isMqttConnected = false;
// //     });
// //     // Optionally, try to reconnect after a delay
// //     Future.delayed(const Duration(seconds: 5), () {
// //       if (!mounted) return;
// //       _initMqtt();
// //     });
// //   }
//
// //   void _subscribeToTopic(String topic) {
// //     _mqttClient.subscribe(topic, mqtt.MqttQos.atMostOnce);
//
// //     _mqttClient.updates?.listen((events) {
// //       if (events.isEmpty) return;
// //       final recMess = events.first.payload as mqtt.MqttPublishMessage;
// //       final payload =
// //           mqtt.MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
//
// //       final msg = '[${events.first.topic}] $payload';
//
// //       if (!mounted) return;
// //       setState(() {
// //         _mqttMessages.insert(0, msg);
// //         // limit list length if you want
// //         if (_mqttMessages.length > 100) {
// //           _mqttMessages.removeLast();
// //         }
// //       });
// //     });
// //   }
//
// //   // ---------- Livestream / Livemap helpers ----------
//
// //   /// Build a camera snapshot URL with cache-busting timestamp.
// //   String _buildSnapshotUrl() {
// //     final base = 'http://$_piStreamPath';
// //     final sep = base.contains('?') ? '&' : '?';
// //     final ts = DateTime.now().millisecondsSinceEpoch;
// //     return '$base${sep}ts=$ts';
// //   }
//
// //   /// Build a Live-Map snapshot URL (fake images) with cache-busting timestamp.
// //   String _buildMapUrl() {
// //     final base = 'http://$_piLiveMapPath';
// //     final sep = base.contains('?') ? '&' : '?';
// //     final ts = DateTime.now().millisecondsSinceEpoch;
// //     return '$base${sep}ts=$ts';
// //   }
//
// //   /// Manual soft refresh of the snapshot widgets.
// //   void _refreshStream() {
// //     setState(() {
// //       // Just forces a rebuild; URLs get new ts values.
// //     });
// //   }
//
// //   void _signOut() {
// //     if (!mounted) return;
// //     Navigator.of(context).pushReplacementNamed(PageRoutes.welcome);
// //   }
//
// //   // ---------- UI ----------
//
// //   @override
// //   Widget build(BuildContext context) {
// //     return Scaffold(
// //       appBar: AppBar(
// //         title: const Text('PARCEL Dashboard'),
// //         actions: [
// //           IconButton(
// //             icon: const Icon(Icons.logout),
// //             onPressed: _signOut,
// //             tooltip: 'Sign out',
// //           ),
// //         ],
// //       ),
// //       body: SafeArea(
// //         child: Stack(
// //           children: [
// //             Row(
// //               crossAxisAlignment: CrossAxisAlignment.stretch,
// //               children: [
// //                 // -------- Left column: MQTT messages (instead of parcels) --------
// //                 SizedBox(
// //                   width: 220,
// //                   child: _buildMqttColumn(
// //                     title: 'MQTT Messages',
// //                   ),
// //                 ),
//
// //                 // -------- Center column (Livestream + Livemap) --------
// //                 Expanded(
// //                   child: Column(
// //                     children: [
// //                       // -------- Camera snapshot pseudo-livestream section ----------
// //                       Expanded(
// //                         flex: 4,
// //                         child: Container(
// //                           margin: const EdgeInsets.symmetric(
// //                             horizontal: 8,
// //                             vertical: 4,
// //                           ),
// //                           decoration: _roundedBoxDecoration(),
// //                           child: Padding(
// //                             padding: const EdgeInsets.all(8.0),
// //                             child: Column(
// //                               crossAxisAlignment: CrossAxisAlignment.stretch,
// //                               children: [
// //                                 Row(
// //                                   children: [
// //                                     const Icon(Icons.videocam, size: 18),
// //                                     const SizedBox(width: 8),
// //                                     const Text(
// //                                       'Live Camera Feed (Snapshots)',
// //                                       style: TextStyle(
// //                                         fontWeight: FontWeight.w600,
// //                                       ),
// //                                     ),
// //                                     const Spacer(),
// //                                     IconButton(
// //                                       icon: const Icon(Icons.refresh),
// //                                       onPressed: _refreshStream,
// //                                       tooltip: 'Refresh Snapshot',
// //                                     ),
// //                                   ],
// //                                 ),
// //                                 const SizedBox(height: 8),
//
// //                                 // Connection info (camera)
// //                                 Card(
// //                                   color: Colors.blue.shade50,
// //                                   child: Padding(
// //                                     padding: const EdgeInsets.all(8.0),
// //                                     child: Column(
// //                                       crossAxisAlignment:
// //                                           CrossAxisAlignment.start,
// //                                       children: [
// //                                         const Text(
// //                                           'Camera snapshot base URL:',
// //                                           style: TextStyle(
// //                                             fontWeight: FontWeight.w600,
// //                                             fontSize: 12,
// //                                           ),
// //                                         ),
// //                                         const SizedBox(height: 4),
// //                                         Text(
// //                                           'http://$_piStreamPath',
// //                                           style: const TextStyle(
// //                                             fontSize: 12,
// //                                             fontFamily: 'monospace',
// //                                           ),
// //                                         ),
// //                                         const SizedBox(height: 4),
// //                                         const Text(
// //                                           'Polled every 5 seconds with a ts cache-buster.',
// //                                           style: TextStyle(fontSize: 11),
// //                                         ),
// //                                       ],
// //                                     ),
// //                                   ),
// //                                 ),
// //                                 const SizedBox(height: 8),
//
// //                                 // Camera snapshot card
// //                                 Expanded(
// //                                   child: Card(
// //                                     elevation: 2,
// //                                     clipBehavior: Clip.antiAlias,
// //                                     child: Column(
// //                                       crossAxisAlignment:
// //                                           CrossAxisAlignment.stretch,
// //                                       children: [
// //                                         Container(
// //                                           color: Colors.black12,
// //                                           padding: const EdgeInsets.symmetric(
// //                                             horizontal: 12,
// //                                             vertical: 8,
// //                                           ),
// //                                           child: const Row(
// //                                             children: [
// //                                               Icon(Icons.camera_alt, size: 18),
// //                                               SizedBox(width: 8),
// //                                               Text(
// //                                                 'Camera Snapshot Stream',
// //                                                 style: TextStyle(
// //                                                   fontWeight: FontWeight.w600,
// //                                                 ),
// //                                               ),
// //                                             ],
// //                                           ),
// //                                         ),
// //                                         Expanded(
// //                                           child: _buildStream(),
// //                                         ),
// //                                       ],
// //                                     ),
// //                                   ),
// //                                 ),
// //                               ],
// //                             ),
// //                           ),
// //                         ),
// //                       ),
//
// //                       // -------- Live-Map section ----------
// //                       Expanded(
// //                         flex: 3,
// //                         child: Container(
// //                           margin: const EdgeInsets.symmetric(
// //                             horizontal: 8,
// //                             vertical: 4,
// //                           ),
// //                           decoration: _roundedBoxDecoration(),
// //                           child: Padding(
// //                             padding: const EdgeInsets.all(8.0),
// //                             child: Card(
// //                               elevation: 2,
// //                               clipBehavior: Clip.antiAlias,
// //                               child: Column(
// //                                 crossAxisAlignment:
// //                                     CrossAxisAlignment.stretch,
// //                                 children: [
// //                                   Container(
// //                                     color: Colors.black12,
// //                                     padding: const EdgeInsets.symmetric(
// //                                       horizontal: 12,
// //                                       vertical: 8,
// //                                     ),
// //                                     child: const Row(
// //                                       children: [
// //                                         Icon(Icons.map, size: 18),
// //                                         SizedBox(width: 8),
// //                                         Text(
// //                                           'Live-Map (Fake Images)',
// //                                           style: TextStyle(
// //                                             fontWeight: FontWeight.w600,
// //                                           ),
// //                                         ),
// //                                       ],
// //                                     ),
// //                                   ),
//
// //                                   // Optional: map connection info
// //                                   Padding(
// //                                     padding: const EdgeInsets.all(8.0),
// //                                     child: Text(
// //                                       'Map snapshot base URL: http://$_piLiveMapPath',
// //                                       style: const TextStyle(
// //                                         fontSize: 11,
// //                                         fontFamily: 'monospace',
// //                                       ),
// //                                     ),
// //                                   ),
//
// //                                   Expanded(
// //                                     child: _buildMapStream(),
// //                                   ),
// //                                 ],
// //                               ),
// //                             ),
// //                           ),
// //                         ),
// //                       ),
// //                     ],
// //                   ),
// //                 ),
// //               ],
// //             ),
// //           ],
// //         ),
// //       ),
// //     );
// //   }
//
// //   // ---------- helpers / sub-widgets -------------
//
// //   BoxDecoration _roundedBoxDecoration() {
// //     return BoxDecoration(
// //       borderRadius: BorderRadius.circular(18),
// //       border: Border.all(color: Colors.black54, width: 1.5),
// //     );
// //   }
//
// //   // Left column now shows MQTT messages instead of parcels.
// //   Widget _buildMqttColumn({
// //     required String title,
// //   }) {
// //     return Card(
// //       margin: const EdgeInsets.all(8),
// //       child: Column(
// //         crossAxisAlignment: CrossAxisAlignment.stretch,
// //         children: [
// //           Container(
// //             padding: const EdgeInsets.all(8),
// //             color: Colors.blueGrey.shade900,
// //             child: Text(
// //               title,
// //               style: const TextStyle(
// //                 fontSize: 16,
// //                 fontWeight: FontWeight.bold,
// //                 color: Colors.white,
// //               ),
// //             ),
// //           ),
// //           if (!_isMqttConnected)
// //             const Expanded(
// //               child: Center(
// //                 child: Text('Connecting to MQTT...'),
// //               ),
// //             )
// //           else if (_mqttMessages.isEmpty)
// //             const Expanded(
// //               child: Center(
// //                 child: Text('No messages yet'),
// //               ),
// //             )
// //           else
// //             Expanded(
// //               child: ListView.builder(
// //                 itemCount: _mqttMessages.length,
// //                 itemBuilder: (context, index) {
// //                   final msg = _mqttMessages[index];
// //                   return ListTile(
// //                     dense: true,
// //                     title: Text(
// //                       msg,
// //                       maxLines: 3,
// //                       overflow: TextOverflow.ellipsis,
// //                       style: const TextStyle(fontSize: 12),
// //                     ),
// //                   );
// //                 },
// //               ),
// //             ),
// //         ],
// //       ),
// //     );
// //   }
//
// //   // --- Livestream (snapshot-based) ---
// //   Widget _buildStream() {
// //     final url = _buildSnapshotUrl();
// //     return Image.network(
// //       url,
// //       fit: BoxFit.cover,
// //       errorBuilder: (context, error, stackTrace) {
// //         return const Center(
// //           child: Text(
// //             'Unable to load camera snapshot',
// //             textAlign: TextAlign.center,
// //           ),
// //         );
// //       },
// //     );
// //   }
//
// //   // --- Livemap (fake images) ---
// //   Widget _buildMapStream() {
// //     final url = _buildMapUrl();
// //     return Image.network(
// //       url,
// //       fit: BoxFit.cover,
// //       errorBuilder: (context, error, stackTrace) {
// //         return const Center(
// //           child: Text(
// //             'Unable to load map snapshot',
// //             textAlign: TextAlign.center,
// //           ),
// //         );
// //       },
// //     );
// //   }
// // }
//
// // // lib/pages/dashboard_page_route.dart
//
// // import 'dart:async';
// // import 'package:flutter/material.dart';
//
// // import '../models/parcel_model.dart';
// // import '../services/parcel_service.dart';
// // import '../routes.dart';
//
// // class DashboardPageRoute extends StatefulWidget {
// //   const DashboardPageRoute({super.key});
//
// //   @override
// //   State<DashboardPageRoute> createState() => _DashboardPageRouteState();
// // }
//
// // class _DashboardPageRouteState extends State<DashboardPageRoute> {
// //   // MQTT / parcel manager (no Firebase inside anymore).
// //   final ParcelService _parcelSvc = ParcelService.instance;
//
// //   // --------- snapshot-based pseudo livestream / Pi camera ----------
// //   // Camera snapshots (MJPG-streamer or similar)
// //   final String _piStreamPath = '172.20.10.7:8080/?action=snapshot';
//
// //   // Live-Map fake images (served by your fake_livemap_server.py on the Pi)
// //   // TODO: replace this with the actual endpoint your Python server exposes,
// //   // e.g. '172.20.10.7:8000/map' or '172.20.10.7:8000/frame'
// //   final String _piLiveMapPath = '172.20.10.7:8000/frame/next';
//
// //   Timer? _snapshotTimer;
//
// //   @override
// //   void initState() {
// //     super.initState();
//
// //     // Start MQTT connection & subscriptions (RFID/status events).
// //     _parcelSvc.init();
//
// //     // Periodic refresh for both camera + live-map
// //     _snapshotTimer = Timer.periodic(const Duration(seconds: 5), (_) {
// //       if (!mounted) return;
// //       setState(() {
// //         // triggers new URLs with fresh ts cache-buster
// //       });
// //     });
// //   }
//
// //   @override
// //   void dispose() {
// //     _snapshotTimer?.cancel();
// //     super.dispose();
// //   }
//
// //   /// Build a camera snapshot URL with cache-busting timestamp.
// //   String _buildSnapshotUrl() {
// //     final base = 'http://$_piStreamPath';
// //     final sep = base.contains('?') ? '&' : '?';
// //     final ts = DateTime.now().millisecondsSinceEpoch;
// //     return '$base${sep}ts=$ts';
// //   }
//
// //   /// Build a Live-Map snapshot URL (fake images) with cache-busting timestamp.
// //   String _buildMapUrl() {
// //     final base = 'http://$_piLiveMapPath';
// //     final sep = base.contains('?') ? '&' : '?';
// //     final ts = DateTime.now().millisecondsSinceEpoch;
// //     return '$base${sep}ts=$ts';
// //   }
//
// //   /// Manual soft refresh of the snapshot widgets.
// //   void _refreshStream() {
// //     setState(() {
// //       // Just forces a rebuild; URLs get new ts values.
// //     });
// //   }
//
// //   void _signOut() {
// //     if (!mounted) return;
// //     Navigator.of(context).pushReplacementNamed(PageRoutes.welcome);
// //   }
//
// //   @override
// //   Widget build(BuildContext context) {
// //     return Scaffold(
// //       appBar: AppBar(title: const Text('PARCEL Dashboard')),
// //       body: SafeArea(
// //         child: Stack(
// //           children: [
// //             Row(
// //               crossAxisAlignment: CrossAxisAlignment.stretch,
// //               children: [
// //                 // -------- Left column: Packages to be delivered --------
// //                 SizedBox(
// //                   width: 220,
// //                   child: _buildParcelColumn(
// //                     title: 'Packages',
// //                     // stream: _parcelSvc.streamByStatus(ParcelStatus.queued),
// //                     status: ParcelStatus.queued
// //                   ),
// //                 ),
//
// //                 // -------- Center column (flexible) --------
// //                 Expanded(
// //                   child: Column(
// //                     children: [
// //                       // -------- Camera snapshot pseudo-livestream section ----------
// //                       Expanded(
// //                         flex: 4,
// //                         child: Container(
// //                           margin: const EdgeInsets.symmetric(
// //                             horizontal: 8,
// //                             vertical: 4,
// //                           ),
// //                           decoration: _roundedBoxDecoration(),
// //                           child: Padding(
// //                             padding: const EdgeInsets.all(8.0),
// //                             child: Column(
// //                               crossAxisAlignment: CrossAxisAlignment.stretch,
// //                               children: [
// //                                 Row(
// //                                   children: [
// //                                     const Icon(Icons.videocam, size: 18),
// //                                     const SizedBox(width: 8),
// //                                     const Text(
// //                                       'Live Camera Feed (Snapshots)',
// //                                       style: TextStyle(
// //                                         fontWeight: FontWeight.w600,
// //                                       ),
// //                                     ),
// //                                     const Spacer(),
// //                                     IconButton(
// //                                       icon: const Icon(Icons.refresh),
// //                                       onPressed: _refreshStream,
// //                                       tooltip: 'Refresh Snapshot',
// //                                     ),
// //                                   ],
// //                                 ),
// //                                 const SizedBox(height: 8),
//
// //                                 // Connection info (camera)
// //                                 Card(
// //                                   color: Colors.blue.shade50,
// //                                   child: Padding(
// //                                     padding: const EdgeInsets.all(8.0),
// //                                     child: Column(
// //                                       crossAxisAlignment:
// //                                       CrossAxisAlignment.start,
// //                                       children: [
// //                                         const Text(
// //                                           'Camera snapshot base URL:',
// //                                           style: TextStyle(
// //                                             fontWeight: FontWeight.w600,
// //                                             fontSize: 12,
// //                                           ),
// //                                         ),
// //                                         const SizedBox(height: 4),
// //                                         Text(
// //                                           'http://$_piStreamPath',
// //                                           style: const TextStyle(
// //                                             fontSize: 12,
// //                                             fontFamily: 'monospace',
// //                                           ),
// //                                         ),
// //                                         const SizedBox(height: 4),
// //                                         const Text(
// //                                           'Polled every 5 seconds with a ts cache-buster.',
// //                                           style: TextStyle(fontSize: 11),
// //                                         ),
// //                                       ],
// //                                     ),
// //                                   ),
// //                                 ),
// //                                 const SizedBox(height: 8),
//
// //                                 // Camera snapshot card
// //                                 Expanded(
// //                                   child: Card(
// //                                     elevation: 2,
// //                                     clipBehavior: Clip.antiAlias,
// //                                     child: Column(
// //                                       crossAxisAlignment:
// //                                       CrossAxisAlignment.stretch,
// //                                       children: [
// //                                         Container(
// //                                           color: Colors.black12,
// //                                           padding: const EdgeInsets.symmetric(
// //                                             horizontal: 12,
// //                                             vertical: 8,
// //                                           ),
// //                                           child: const Row(
// //                                             children: [
// //                                               Icon(Icons.camera_alt, size: 18),
// //                                               SizedBox(width: 8),
// //                                               Text(
// //                                                 'Camera Snapshot Stream',
// //                                                 style: TextStyle(
// //                                                   fontWeight: FontWeight.w600,
// //                                                 ),
// //                                               ),
// //                                             ],
// //                                           ),
// //                                         ),
// //                                         Expanded(
// //                                           child: _buildStream(),
// //                                         ),
// //                                       ],
// //                                     ),
// //                                   ),
// //                                 ),
// //                               ],
// //                             ),
// //                           ),
// //                         ),
// //                       ),
//
// //                       // -------- Live-Map section ----------
// //                       Expanded(
// //                         flex: 3,
// //                         child: Container(
// //                           margin: const EdgeInsets.symmetric(
// //                             horizontal: 8,
// //                             vertical: 4,
// //                           ),
// //                           decoration: _roundedBoxDecoration(),
// //                           child: Padding(
// //                             padding: const EdgeInsets.all(8.0),
// //                             child: Card(
// //                               elevation: 2,
// //                               clipBehavior: Clip.antiAlias,
// //                               child: Column(
// //                                 crossAxisAlignment:
// //                                 CrossAxisAlignment.stretch,
// //                                 children: [
// //                                   Container(
// //                                     color: Colors.black12,
// //                                     padding: const EdgeInsets.symmetric(
// //                                       horizontal: 12,
// //                                       vertical: 8,
// //                                     ),
// //                                     child: const Row(
// //                                       children: [
// //                                         Icon(Icons.map, size: 18),
// //                                         SizedBox(width: 8),
// //                                         Text(
// //                                           'Live-Map (Fake Images)',
// //                                           style: TextStyle(
// //                                             fontWeight: FontWeight.w600,
// //                                           ),
// //                                         ),
// //                                       ],
// //                                     ),
// //                                   ),
//
// //                                   // Optional: map connection info
// //                                   Padding(
// //                                     padding: const EdgeInsets.all(8.0),
// //                                     child: Text(
// //                                       'Map snapshot base URL: http://$_piLiveMapPath',
// //                                       style: const TextStyle(
// //                                         fontSize: 11,
// //                                         fontFamily: 'monospace',
// //                                       ),
// //                                     ),
// //                                   ),
//
// //                                   Expanded(
// //                                     child: _buildMapStream(),
// //                                   ),
// //                                 ],
// //                               ),
// //                             ),
// //                           ),
// //                         ),
// //                       ),
// //                     ],
// //                   ),
// //                 ),
// //               ],
// //             ),
// //           ],
// //         ),
// //       ),
// //     );
// //   }
//
// //   // ---------- helpers / sub-widgets -------------
//
// //   BoxDecoration _roundedBoxDecoration() {
// //     return BoxDecoration(
// //       borderRadius: BorderRadius.circular(18),
// //       border: Border.all(color: Colors.black54, width: 1.5),
// //     );
// //   }
// //   Widget _buildParcelColumn({
// //     required String title,
// //     required ParcelStatus status,
// //   }) {
// //     return Card( // you *can* wrap it in a Card if you want visuals
// //       margin: const EdgeInsets.all(8),
// //       child: Column(
// //         crossAxisAlignment: CrossAxisAlignment.stretch,
// //         children: [
// //           Container(
// //             padding: const EdgeInsets.all(8),
// //             color: Colors.blueGrey.shade900,
// //             child: Text(
// //               title,
// //               style: const TextStyle(
// //                 fontSize: 16,
// //                 fontWeight: FontWeight.bold,
// //                 color: Colors.white,
// //               ),
// //             ),
// //           ),
// //           Expanded(
// //             child: StreamBuilder<List<Parcel>>(
// //               stream: _parcelSvc.streamByStatus(status),
// //               builder: (context, snapshot) {
// //                 if (!snapshot.hasData) {
// //                   return const Center(child: Text('Waiting for parcels...'));
// //                 }
//
// //                 final parcels = snapshot.data!;
// //                 if (parcels.isEmpty) {
// //                   return const Center(child: Text('No parcels'));
// //                 }
//
// //                 return ListView.builder(
// //                   itemCount: parcels.length,
// //                   itemBuilder: (context, index) {
// //                     final p = parcels[index];
// //                     return ListTile(
// //                       dense: true,
// //                       title: Text(p.rfidTag),
// //                       subtitle: Text(
// //                         'id: ${p.id}\nupdated: ${p.updatedAt}',
// //                         maxLines: 2,
// //                         overflow: TextOverflow.ellipsis,
// //                       ),
// //                     );
// //                   },
// //                 );
// //               },
// //             ),
// //           ),
// //         ],
// //       ),
// //     );
// //   }
//
//   // Widget _buildParcelColumn({
//   //   required String title,
//   //   // required Stream<List<Parcel>> stream,
//   //   required ParcelStatus status,
//   // }) {
//   //   return Container(
//   //     margin: const EdgeInsets.all(8),
//   //     decoration: _roundedBoxDecoration(),
//   //     child: Column(
//   //       children: [
//   //         Padding(
//   //           padding: const EdgeInsets.symmetric(vertical: 12.0),
//   //           child: Text(
//   //             title,
//   //             style: const TextStyle(fontWeight: FontWeight.bold),
//   //           ),
//   //         ),
//   //         const Divider(height: 1),
//   //         Expanded(
//   //           child: StreamBuilder<List<Parcel>>(
//   //             stream: stream,
//   //             builder: (context, snapshot) {
//   //               if (snapshot.hasError) {
//   //                 return Center(
//   //                   child: Text(
//   //                     'Error: ${snapshot.error}',
//   //                     style: const TextStyle(
//   //                       color: Colors.red,
//   //                       fontSize: 12,
//   //                     ),
//   //                   ),
//   //                 );
//   //               }
//   //               if (snapshot.connectionState == ConnectionState.waiting) {
//   //                 return const Center(child: CircularProgressIndicator());
//   //               }
//   //               final parcels = snapshot.data ?? [];
//   //
//   //               if (parcels.isEmpty) {
//   //                 return const Center(
//   //                   child: Text(
//   //                     'No packages',
//   //                     style: TextStyle(color: Colors.grey),
//   //                   ),
//   //                 );
//   //               }
//   //
//   //               return ListView.builder(
//   //                 itemCount: parcels.length,
//   //                 itemBuilder: (context, index) {
//   //                   final parcel = parcels[index];
//   //                   return ListTile(
//   //                     dense: true,
//   //                     title: Text(parcel.rfidTag),
//   //                     subtitle: Text(
//   //                       parcelStatusToString(parcel.status),
//   //                     ),
//   //                   );
//   //                 },
//   //               );
//   //             },
//   //           ),
//   //         ),
//   //       ],
//   //     ),
//   //   );
//   // }
//
//   /// Build the camera snapshot widget using Image.network.
//   Widget _buildStream() {
//     final streamUrl = _buildSnapshotUrl();
//
//     return Image.network(
//       streamUrl,
//       fit: BoxFit.contain,
//       gaplessPlayback: true,
//       loadingBuilder: (context, child, loadingProgress) {
//         if (loadingProgress == null) {
//           return child;
//         }
//         return const Center(
//           child: CircularProgressIndicator(),
//         );
//       },
//       errorBuilder: (context, error, stackTrace) {
//         return Center(
//           child: Padding(
//             padding: const EdgeInsets.all(16),
//             child: Column(
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 const Icon(Icons.error_outline,
//                     color: Colors.red, size: 48),
//                 const SizedBox(height: 12),
//                 const Text(
//                   'Cannot load camera snapshot',
//                   style: TextStyle(fontWeight: FontWeight.bold),
//                 ),
//                 const SizedBox(height: 8),
//                 Text(
//                   'URL: $streamUrl',
//                   textAlign: TextAlign.center,
//                   style: const TextStyle(
//                     fontSize: 11,
//                     fontFamily: 'monospace',
//                   ),
//                 ),
//                 const SizedBox(height: 8),
//                 Text(
//                   'Error: ${error.toString()}',
//                   textAlign: TextAlign.center,
//                   style: const TextStyle(
//                     fontSize: 10,
//                     color: Colors.red,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         );
//       },
//     );
//   }
//
//   /// Live-Map snapshot widget (fake images from Pi5).
//   Widget _buildMapStream() {
//     final streamUrl = _buildMapUrl();
//
//     return Image.network(
//       streamUrl,
//       fit: BoxFit.contain,
//       gaplessPlayback: true,
//       loadingBuilder: (context, child, loadingProgress) {
//         if (loadingProgress == null) {
//           return child;
//         }
//         return const Center(
//           child: CircularProgressIndicator(),
//         );
//       },
//       errorBuilder: (context, error, stackTrace) {
//         return Center(
//           child: Padding(
//             padding: const EdgeInsets.all(16),
//             child: Column(
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 const Icon(Icons.error_outline,
//                     color: Colors.red, size: 48),
//                 const SizedBox(height: 12),
//                 const Text(
//                   'Cannot load Live-Map snapshot',
//                   style: TextStyle(fontWeight: FontWeight.bold),
//                 ),
//                 const SizedBox(height: 8),
//                 Text(
//                   'URL: $streamUrl',
//                   textAlign: TextAlign.center,
//                   style: const TextStyle(
//                     fontSize: 11,
//                     fontFamily: 'monospace',
//                   ),
//                 ),
//                 const SizedBox(height: 8),
//                 Text(
//                   'Error: ${error.toString()}',
//                   textAlign: TextAlign.center,
//                   style: const TextStyle(
//                     fontSize: 10,
//                     color: Colors.red,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         );
//       },
//     );
//   }