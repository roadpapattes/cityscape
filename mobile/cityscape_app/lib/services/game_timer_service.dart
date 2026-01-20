// lib/services/game_timer_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';

class GameTimer extends ChangeNotifier {
  static final GameTimer instance = GameTimer._();
  GameTimer._();

  DateTime? _startAt;
  Duration _penalties = Duration.zero;
  Timer? _ticker;

  bool get isRunning => _startAt != null;

  /// Temps écoulé + pénalités
  Duration get elapsed {
    if (_startAt == null) return _penalties;
    final base = DateTime.now().difference(_startAt!);
    return base + _penalties;
  }

  String get elapsedText {
    final d = elapsed;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '${_2(h)}:${_2(m)}:${_2(s)}' : '${_2(m)}:${_2(s)}';
  }

  /// Démarre si pas déjà en cours (idempotent). Ne réinitialise PAS si déjà démarré.
  void start() {
    if (isRunning) return;
    _startAt = DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    notifyListeners(); // tick immédiat
  }

  /// Démarre (ou reprend) depuis une date de départ spécifique (ex: started_at du serveur).
  /// Permet de conserver le temps écoulé même après fermeture de l'app.
  void startFrom(DateTime startedAt) {
    _startAt = startedAt;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    notifyListeners();
  }

  /// Met en pause sans remettre les pénalités à zéro.
  void pause() {
    _ticker?.cancel();
    _ticker = null;
    _startAt = null;
    notifyListeners();
  }

  /// Stoppe et remet à zéro.
  void stop() {
    _ticker?.cancel();
    _ticker = null;
    _startAt = null;
    _penalties = Duration.zero;
    notifyListeners();
  }

  /// Ajoute une pénalité en secondes (appliquée immédiatement à l'affichage).
  void addPenaltySeconds(int seconds) {
    if (seconds <= 0) return;
    _penalties += Duration(seconds: seconds);
    notifyListeners();
  }

  /// Pratique : pénalité en minutes.
  void addPenaltyMinutes(int minutes) {
    if (minutes <= 0) return;
    _penalties += Duration(minutes: minutes);
    notifyListeners();
  }

  /// Force la pénalité courante à une valeur en minutes (depuis le serveur).
  void syncPenaltyMinutes(int minutes) {
    final m = minutes < 0 ? 0 : minutes;
    _penalties = Duration(minutes: m);
    notifyListeners();
  }

  /// Alias pratique si un jour tu veux sync en secondes.
  void syncPenaltySeconds(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    _penalties = Duration(seconds: s);
    notifyListeners();
  }

  /// Renvoie le texte final et remet à zéro.
  String finishAndGetResult() {
    final txt = elapsedText;
    stop();
    return txt;
  }

  String _2(int n) => n.toString().padLeft(2, '0');
}
