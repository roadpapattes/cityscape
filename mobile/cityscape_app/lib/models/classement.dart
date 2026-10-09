// lib/models/classement.dart
//
// Classement des meilleurs temps sur une escape.
//
// Le rang est calculé par le serveur à partir du temps qu'il a lui-même
// mesuré, plus les pénalités. L'application ne recalcule rien : elle affiche.

/// Une ligne de classement.
class EntreeClassement {
  final int rang;
  final String joueur;

  /// Temps de jeu mesuré par le serveur, en secondes.
  final int tempsSecondes;

  /// Pénalités cumulées, converties en secondes par le serveur.
  final int penaliteSecondes;

  /// Ce qui détermine le rang : temps + pénalités.
  final int scoreSecondes;

  final DateTime? termineLe;

  const EntreeClassement({
    required this.rang,
    required this.joueur,
    required this.tempsSecondes,
    required this.penaliteSecondes,
    required this.scoreSecondes,
    this.termineLe,
  });

  factory EntreeClassement.fromJson(Map<String, dynamic> j) {
    return EntreeClassement(
      rang: (j['rang'] as num?)?.toInt() ?? 0,
      joueur: (j['joueur'] ?? '—') as String,
      tempsSecondes: (j['temps_s'] as num?)?.toInt() ?? 0,
      penaliteSecondes: (j['penalite_s'] as num?)?.toInt() ?? 0,
      scoreSecondes: (j['score_s'] as num?)?.toInt() ?? 0,
      termineLe: j['termine_le'] == null
          ? null
          : DateTime.tryParse('${j['termine_le']}'),
    );
  }

  bool get aUnePenalite => penaliteSecondes > 0;
}

/// Le haut du tableau, et la place du joueur qui consulte.
class Classement {
  final int escapeId;

  /// Nombre total de parties classées, qui peut dépasser le nombre d'entrées
  /// renvoyées : c'est ce qui permet d'écrire « 3e sur 47 ».
  final int totalClasses;

  final List<EntreeClassement> entrees;

  /// La place du joueur qui consulte, même s'il est hors du haut du tableau.
  /// Vaut null s'il n'a pas terminé l'escape.
  final EntreeClassement? moi;

  const Classement({
    required this.escapeId,
    required this.totalClasses,
    required this.entrees,
    this.moi,
  });

  factory Classement.fromJson(Map<String, dynamic> j) {
    final brut = (j['entrees'] as List?) ?? const [];
    return Classement(
      escapeId: (j['escape_id'] as num?)?.toInt() ?? 0,
      totalClasses: (j['total_classes'] as num?)?.toInt() ?? 0,
      entrees: brut
          .whereType<Map<String, dynamic>>()
          .map(EntreeClassement.fromJson)
          .toList(),
      moi: j['moi'] == null
          ? null
          : EntreeClassement.fromJson(j['moi'] as Map<String, dynamic>),
    );
  }

  bool get estVide => entrees.isEmpty;

  /// Le joueur figure-t-il déjà dans la portion affichée ? Si oui, inutile de
  /// répéter sa ligne en bas de l'écran.
  bool get moiDejaDansLaListe =>
      moi != null && entrees.any((e) => e.rang == moi!.rang);
}

/// Formate une durée en secondes pour l'affichage : « 7 min 12 s », ou
/// « 1 h 03 min » au-delà de l'heure.
String formaterDuree(int secondes) {
  if (secondes < 0) secondes = 0;
  final h = secondes ~/ 3600;
  final m = (secondes % 3600) ~/ 60;
  final s = secondes % 60;
  if (h > 0) {
    return '$h h ${m.toString().padLeft(2, '0')} min';
  }
  if (m > 0) {
    return '$m min ${s.toString().padLeft(2, '0')} s';
  }
  return '$s s';
}
