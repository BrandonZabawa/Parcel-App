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

  // ------------ Livemap (Pi) ----------

  // Livemap ip-addr
  static const String _piLiveMapHost = '172.20.10.3'; // <-- your Pi's IP
  static const int _piLiveMapPort = 8000;
  static const String _piLiveMapHttpPath = '/frame/next';


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

      final resp = await http.get(uri).timeout(const Duration(seconds: 1));

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
  String _buildMapUrl() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return 'http://$_piLiveMapHost:$_piLiveMapPort$_piLiveMapHttpPath?ts=$ts';
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
        title: const Text('Dashboard'),
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
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Center(
                                      child: Text("Livemap & Livestream")
                                    ),
                                    SizedBox(width: 8),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  'Livemap base URL: http://$_piLiveMapHost:$_piLiveMapPort$_piLiveMapHttpPath',
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
                  )
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

                final id = packet['id']?.toString() ?? 'unknown'; // id of packet
                final msg = (packet['msg'] ?? // message of packet (this stuff below)
                    packet['value'] ?? // value of packet
                    packet['status'] ?? // status of packet
                    packet['raw'] ??
                    packet.toString())
                    .toString();
                final ts = packet['timestamp']?.toString(); // timestamp

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

  /// Live-Map snapshot widget (fake images from Pi5).
  Widget _buildMapStream() {
    final streamUrl = _buildMapUrl();

    return Image.network(
      streamUrl,
      fit: BoxFit.coverg,
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