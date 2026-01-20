// lib/services/game_timer_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';

class GameTimer extends ChangeNotifier {
  static final GameTimer instance = GameTimer._();
  GameTimer._();

  DateTime? _sessionStartAt;  // Quand cette session de jeu a commencé
  Duration _baseTime = Duration.zero;  // Temps cumulé des sessions précédentes
  Duration _penalties = Duration.zero;
  Timer? _ticker;

  bool get isRunning => _sessionStartAt != null;

  /// Temps de la session courante (depuis _sessionStartAt)
  Duration get _currentSessionTime {
    if (_sessionStartAt == null) return Duration.zero;
    return DateTime.now().difference(_sessionStartAt!);
  }

  /// Temps total = base + session courante + pénalités
  Duration get elapsed => _baseTime + _currentSessionTime + _penalties;

  /// Temps écoulé en secondes (pour sync avec serveur)
  int get elapsedSeconds => (_baseTime + _currentSessionTime).inSeconds;

  /// Temps de la session courante en secondes (pour envoyer au serveur quand on quitte)
  int get currentSessionSeconds => _currentSessionTime.inSeconds;

  String get elapsedText {
    final d = elapsed;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '${_2(h)}:${_2(m)}:${_2(s)}' : '${_2(m)}:${_2(s)}';
  }

  /// Démarre une nouvelle session de jeu avec un temps de base (cumul précédent).
  /// baseSeconds = temps déjà joué lors des sessions précédentes (depuis le serveur)
  void startWithBase(int baseSeconds) {
    _baseTime = Duration(seconds: baseSeconds < 0 ? 0 : baseSeconds);
    _sessionStartAt = DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    notifyListeners();
  }

  /// Démarre si pas déjà en cours (idempotent). Ne réinitialise PAS si déjà démarré.
  void start() {
    if (isRunning) return;
    _sessionStartAt = DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    notifyListeners();
  }

  /// Démarre (ou reprend) depuis une date de départ spécifique.
  /// DEPRECATED: utiliser startWithBase à la place
  void startFrom(DateTime startedAt) {
    _sessionStartAt = startedAt;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    notifyListeners();
  }

  /// Met en pause sans remettre les pénalités à zéro.
  /// Retourne le temps de la session courante en secondes (à envoyer au serveur)
  int pause() {
    final sessionTime = currentSessionSeconds;
    _ticker?.cancel();
    _ticker = null;
    // Ajouter le temps de la session courante au temps de base
    _baseTime += _currentSessionTime;
    _sessionStartAt = null;
    notifyListeners();
    return sessionTime;
  }

  /// Récupère le temps de session courant et continue à compter.
  /// Utilisé pour sync le temps à chaque réponse sans interrompre le timer.
  /// Retourne le temps de la session courante en secondes.
  int syncAndContinue() {
    if (!isRunning) return 0;
    final sessionTime = currentSessionSeconds;
    // Ajouter le temps de la session courante au temps de base
    _baseTime += _currentSessionTime;
    // Redémarrer la session immédiatement
    _sessionStartAt = DateTime.now();
    return sessionTime;
  }

  /// Stoppe et remet tout à zéro.
  void stop() {
    _ticker?.cancel();
    _ticker = null;
    _sessionStartAt = null;
    _baseTime = Duration.zero;
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
