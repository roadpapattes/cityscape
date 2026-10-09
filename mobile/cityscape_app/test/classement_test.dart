// Modèle de classement : lecture de la réponse serveur et formatage.
//
// Le serveur calcule les rangs ; l'application ne fait que lire et afficher.
// Ces tests portent donc sur la robustesse de la lecture - une réponse
// tronquée ou un champ absent ne doit pas faire planter l'écran - et sur le
// formatage des durées, seul calcul fait côté application.

import 'package:flutter_test/flutter_test.dart';
import 'package:cityscape/models/classement.dart';

void main() {
  group('formaterDuree', () {
    test('affiche les secondes seules sous la minute', () {
      expect(formaterDuree(0), '0 s');
      expect(formaterDuree(45), '45 s');
    });

    test('affiche minutes et secondes, secondes sur deux chiffres', () {
      expect(formaterDuree(60), '1 min 00 s');
      expect(formaterDuree(432), '7 min 12 s');
    });

    test('bascule en heures au-dela de 3600 s', () {
      expect(formaterDuree(3600), '1 h 00 min');
      expect(formaterDuree(3780), '1 h 03 min');
    });

    test('une duree negative vaut zero plutot que de produire du charabia', () {
      expect(formaterDuree(-10), '0 s');
    });
  });

  group('EntreeClassement.fromJson', () {
    test('lit une entree complete', () {
      final e = EntreeClassement.fromJson({
        'rang': 3,
        'joueur': 'marie',
        'temps_s': 420,
        'penalite_s': 300,
        'score_s': 720,
        'termine_le': '2026-10-09T14:30:00Z',
      });
      expect(e.rang, 3);
      expect(e.joueur, 'marie');
      expect(e.tempsSecondes, 420);
      expect(e.penaliteSecondes, 300);
      expect(e.scoreSecondes, 720);
      expect(e.aUnePenalite, isTrue);
      expect(e.termineLe, isNotNull);
    });

    test('survit a des champs absents', () {
      final e = EntreeClassement.fromJson(const {});
      expect(e.rang, 0);
      expect(e.joueur, '—');
      expect(e.scoreSecondes, 0);
      expect(e.aUnePenalite, isFalse);
      expect(e.termineLe, isNull);
    });

    test('survit a une date illisible', () {
      final e = EntreeClassement.fromJson(const {'termine_le': 'pas une date'});
      expect(e.termineLe, isNull);
    });
  });

  group('Classement.fromJson', () {
    test('lit un classement avec la place du joueur', () {
      final c = Classement.fromJson({
        'escape_id': 12,
        'total_classes': 47,
        'entrees': [
          {'rang': 1, 'joueur': 'rapide', 'temps_s': 300, 'penalite_s': 0, 'score_s': 300},
          {'rang': 2, 'joueur': 'moyen', 'temps_s': 600, 'penalite_s': 0, 'score_s': 600},
        ],
        'moi': {'rang': 9, 'joueur': 'moi', 'temps_s': 900, 'penalite_s': 60, 'score_s': 960},
      });
      expect(c.escapeId, 12);
      expect(c.totalClasses, 47);
      expect(c.entrees, hasLength(2));
      expect(c.estVide, isFalse);
      expect(c.moi?.rang, 9);
      expect(c.moiDejaDansLaListe, isFalse,
          reason: 'le joueur est 9e, hors des deux entrees affichees');
    });

    test('reconnait que le joueur figure deja dans la liste affichee', () {
      final c = Classement.fromJson({
        'entrees': [
          {'rang': 1, 'joueur': 'moi', 'score_s': 300},
        ],
        'moi': {'rang': 1, 'joueur': 'moi', 'score_s': 300},
      });
      expect(c.moiDejaDansLaListe, isTrue,
          reason: 'sa ligne ne doit pas etre repetee en bas de l ecran');
    });

    test('un classement vide est une reponse normale, pas une erreur', () {
      final c = Classement.fromJson(const {
        'escape_id': 5, 'total_classes': 0, 'entrees': [], 'moi': null,
      });
      expect(c.estVide, isTrue);
      expect(c.moi, isNull);
      expect(c.moiDejaDansLaListe, isFalse);
    });

    test('survit a une reponse vide', () {
      final c = Classement.fromJson(const {});
      expect(c.estVide, isTrue);
      expect(c.totalClasses, 0);
      expect(c.moi, isNull);
    });
  });
}
