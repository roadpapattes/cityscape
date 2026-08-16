// lib/services/audio_service.dart
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'preferences_service.dart';

/// Fond sonore d'escape, joué en boucle pendant la partie.
/// Le mute est persisté (PreferencesService) : le choix du joueur est
/// mémorisé d'une partie à l'autre.
class AudioService extends ChangeNotifier {
  static final AudioService instance = AudioService._();
  AudioService._();

  final AudioPlayer _player = AudioPlayer();
  String? _currentUrl;

  bool get isMuted => PreferencesService.instance.currentPreferences.audioMuted;

  Future<void> _applyVolume() async {
    await _player.setVolume(isMuted ? 0 : 1);
  }

  /// Démarre (ou reprend) la lecture en boucle du fond sonore de l'escape.
  /// Ne relance pas la lecture si la même URL est déjà en cours.
  Future<void> playLoop(String? url) async {
    final u = url?.trim();
    if (u == null || u.isEmpty) {
      await stop();
      return;
    }
    if (u == _currentUrl) return;

    _currentUrl = u;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _applyVolume();
      await _player.play(UrlSource(u));
    } catch (_) {
      // Fond sonore facultatif : on n'interrompt jamais la partie pour ça.
    }
  }

  Future<void> stop() async {
    _currentUrl = null;
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (_) {}
  }

  Future<void> resume() async {
    if (_currentUrl == null) return;
    try {
      await _player.resume();
    } catch (_) {}
  }

  Future<void> toggleMute() async {
    await PreferencesService.instance.setAudioMuted(!isMuted);
    await _applyVolume();
    notifyListeners();
  }
}
