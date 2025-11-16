import 'package:flutter_vlc_player/flutter_vlc_player.dart';

class RtspService {
  VlcPlayerController? _ctrl;

  VlcPlayerController? get controller => _ctrl;
  bool get isAttached => _ctrl != null;

  Future<void> attach(String url) async {
    if (_ctrl == null) {
      _ctrl = VlcPlayerController.network(url, hwAcc: HwAcc.full, autoPlay: true);
    } else {
      await _ctrl!.setMediaFromNetwork(url, autoPlay: true);
    }
  }

  Future<void> stop() async => _ctrl?.stop();

  Future<void> dispose() async {
    await _ctrl?.dispose();
    _ctrl = null;
  }
}
