# -*- coding: utf-8 -*-
"""Classement par escape : ordre, exclusions, acces.

Le classement est la premiere fonctionnalite qui donne une valeur au temps
de jeu. Ces tests portent donc autant sur ce qui est classe que sur ce qui
ne doit pas l'etre.
"""

from datetime import timedelta

from django.contrib.auth import get_user_model
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from engagement.anonymisation import anonymiser_compte
from engagement.classement import (
    LIBELLE_COMPTE_ANONYMISE, LIMITE_MAX, classement_escape, nom_affiche,
)
from engagement.models import PlaySession
from games.models import EscapeGame, GameStep

User = get_user_model()


class ClassementTestCase(TestCase):
    def setUp(self):
        self.proprietaire = User.objects.create_user(username="createur", password="pw")
        self.escape = EscapeGame.objects.create(
            title="Escape classee", city="Paris", latitude=48.85, longitude=2.35,
            status="published", owner=self.proprietaire,
        )
        GameStep.objects.create(
            escape=self.escape, order=1, title="Etape", text="?",
            answer_type="text", answer_text="reponse",
        )

    def _session(self, username, temps, penalite=0, terminee=True, decalage_min=0):
        """Une session terminee avec un temps mesure et une penalite donnes."""
        user = User.objects.create_user(username=username, password="pw")
        sess = PlaySession.objects.create(
            user=user, escape=self.escape,
            server_play_seconds=temps, penalty=penalite,
        )
        if terminee:
            PlaySession.objects.filter(id=sess.id).update(
                completed_at=timezone.now() + timedelta(minutes=decalage_min),
            )
            sess.refresh_from_db()
        return sess

    def _noms(self, resultat):
        return [e["joueur"] for e in resultat["entrees"]]


class OrdreDuClassementTests(ClassementTestCase):
    def test_les_temps_les_plus_courts_passent_devant(self):
        self._session("lent", 900)
        self._session("rapide", 300)
        self._session("moyen", 600)

        r = classement_escape(self.escape)
        self.assertEqual(self._noms(r), ["rapide", "moyen", "lent"])
        self.assertEqual([e["rang"] for e in r["entrees"]], [1, 2, 3])

    def test_les_penalites_comptent_dans_le_rang(self):
        """Le coeur de la decision : un temps brut plus court ne suffit pas
        si le joueur a force les reponses ou consomme les indices."""
        # 300 s de jeu, mais 10 minutes de penalite -> score 900 s.
        propre = self._session("propre", 600, penalite=0)       # score 600
        brouillon = self._session("brouillon", 300, penalite=10)  # score 900

        r = classement_escape(self.escape)
        self.assertEqual(self._noms(r), ["propre", "brouillon"])
        self.assertEqual(r["entrees"][0]["score_s"], 600)
        self.assertEqual(r["entrees"][1]["score_s"], 900)
        self.assertEqual(r["entrees"][1]["temps_s"], 300)
        self.assertEqual(r["entrees"][1]["penalite_s"], 600)
        self.assertEqual(propre.user.username, "propre")
        self.assertEqual(brouillon.user.username, "brouillon")

    def test_a_egalite_le_premier_a_avoir_termine_passe_devant(self):
        """L'ordre doit etre total : sans cela, deux lectures du classement
        pourraient renvoyer des rangs differents."""
        self._session("second", 600, decalage_min=10)
        self._session("premier", 600, decalage_min=1)

        r = classement_escape(self.escape)
        self.assertEqual(self._noms(r), ["premier", "second"])
        # Et l'ordre ne varie pas d'une lecture a l'autre.
        self.assertEqual(self._noms(classement_escape(self.escape)), ["premier", "second"])


class ExclusionsDuClassementTests(ClassementTestCase):
    def test_une_session_non_terminee_n_est_pas_classee(self):
        self._session("fini", 600)
        self._session("en_cours", 120, terminee=False)

        r = classement_escape(self.escape)
        self.assertEqual(self._noms(r), ["fini"])
        self.assertEqual(r["total_classes"], 1)

    def test_les_sessions_sans_temps_mesure_sont_ecartees(self):
        """Les parties anterieures au chronometrage serveur valent 0 : elles
        apparaitraient en tete avec un temps nul, ce qui serait faux."""
        self._session("ancienne", 0)
        self._session("mesuree", 600)

        r = classement_escape(self.escape)
        self.assertEqual(self._noms(r), ["mesuree"])

    def test_une_autre_escape_n_interfere_pas(self):
        autre = EscapeGame.objects.create(
            title="Autre escape", city="Lyon", latitude=45.76, longitude=4.83,
            status="published",
        )
        intrus = User.objects.create_user(username="intrus", password="pw")
        s = PlaySession.objects.create(
            user=intrus, escape=autre, server_play_seconds=10,
        )
        PlaySession.objects.filter(id=s.id).update(completed_at=timezone.now())

        self._session("bon", 600)
        self.assertEqual(self._noms(classement_escape(self.escape)), ["bon"])


class LimiteEtRangPersonnelTests(ClassementTestCase):
    def test_la_limite_tronque_sans_fausser_le_total(self):
        for i in range(5):
            self._session(f"joueur{i}", 100 + i * 10)

        r = classement_escape(self.escape, limite=2)
        self.assertEqual(len(r["entrees"]), 2)
        self.assertEqual(r["total_classes"], 5, "le total doit rester celui du classement entier")

    def test_la_limite_est_bornee(self):
        self._session("seul", 600)
        for demande in (0, -5, 10 ** 6, None):
            r = classement_escape(self.escape, limite=demande)
            self.assertLessEqual(len(r["entrees"]), LIMITE_MAX)

    def test_le_joueur_connait_son_rang_meme_hors_du_haut_du_tableau(self):
        """C'est l'information qui l'interesse ; la chercher dans une liste
        tronquee serait impossible."""
        for i in range(10):
            self._session(f"devant{i}", 100 + i)
        moi = self._session("moi", 5000)

        r = classement_escape(self.escape, limite=3, pour_utilisateur=moi.user)
        self.assertEqual(len(r["entrees"]), 3)
        self.assertIsNotNone(r["moi"])
        self.assertEqual(r["moi"]["rang"], 11)
        self.assertEqual(r["moi"]["joueur"], "moi")

    def test_sans_partie_terminee_le_joueur_n_a_pas_de_rang(self):
        self._session("autre", 600)
        curieux = User.objects.create_user(username="curieux", password="pw")
        r = classement_escape(self.escape, pour_utilisateur=curieux)
        self.assertIsNone(r["moi"])


class ComptesAnonymisesTests(ClassementTestCase):
    def test_anonymiser_un_compte_retire_ses_temps_du_classement(self):
        """Consequence directe de l'anonymisation, qui supprime les sessions
        de jeu : un record peut s'effacer, et la place se liberer.

        C'est voulu - l'historique de jeu est une donnee personnelle, et la
        page de suppression annonce sa perte - mais il faut le savoir, parce
        que cela fait bouger un classement deja publie.
        """
        record = self._session("recordman", 100)
        self._session("suivant", 500)
        self.assertEqual(self._noms(classement_escape(self.escape)), ["recordman", "suivant"])

        anonymiser_compte(record.user)

        r = classement_escape(self.escape)
        self.assertEqual(self._noms(r), ["suivant"])
        self.assertEqual(r["total_classes"], 1)
        # Le suivant remonte a la premiere place.
        self.assertEqual(r["entrees"][0]["rang"], 1)

    def test_un_compte_anonymise_ne_serait_jamais_nomme(self):
        """Filet de securite teste a l'unite, faute de scenario qui
        l'atteigne : si la regle de suppression des sessions changeait un
        jour, l'invariant doit tenir."""
        user = User.objects.create_user(username="partant", password="pw")
        self.assertEqual(nom_affiche(user), "partant")

        anonymiser_compte(user)
        user.refresh_from_db()
        self.assertEqual(nom_affiche(user), LIBELLE_COMPTE_ANONYMISE)
        self.assertNotIn("partant", nom_affiche(user))


@override_settings(RATELIMIT_ENABLE=False)
class EndpointClassementTests(ClassementTestCase):
    def setUp(self):
        super().setUp()
        self.joueur = User.objects.create_user(username="lecteur", password="pw")
        self.client = APIClient()
        self.client.credentials(
            HTTP_AUTHORIZATION=f"Token {Token.objects.create(user=self.joueur).key}"
        )

    def _lire(self, escape=None, **params):
        cible = escape or self.escape
        q = "&".join(f"{k}={v}" for k, v in params.items())
        url = f"/api/escapes/{cible.id}/leaderboard"
        if q:
            url += f"?{q}"
        return self.client.get(url)

    def test_le_classement_est_lisible(self):
        self._session("rapide", 300)
        self._session("lent", 900)

        r = self._lire()
        self.assertEqual(r.status_code, 200, r.content)
        corps = r.json()
        self.assertEqual(corps["escape_id"], self.escape.id)
        self.assertEqual([e["joueur"] for e in corps["entrees"]], ["rapide", "lent"])

    def test_une_limite_illisible_ne_fait_pas_echouer_la_requete(self):
        self._session("un", 300)
        r = self._lire(limite="beaucoup")
        self.assertEqual(r.status_code, 200, r.content)
        self.assertEqual(len(r.json()["entrees"]), 1)

    def test_aucun_identifiant_d_utilisateur_n_est_divulgue(self):
        """Un identifiant numerique stable est une prise pour correler des
        comptes entre eux d'une escape a l'autre."""
        self._session("rapide", 300)
        corps = self._lire().json()
        for entree in corps["entrees"]:
            self.assertNotIn("user_id", entree)
            self.assertNotIn("user", entree)
            self.assertNotIn("id", entree)

    def test_le_classement_d_un_brouillon_d_autrui_est_refuse(self):
        brouillon = EscapeGame.objects.create(
            title="Brouillon", city="Paris", latitude=48.85, longitude=2.35,
            status="draft", owner=self.proprietaire,
        )
        self.assertIn(self._lire(brouillon).status_code, (403, 404))

    def test_le_classement_d_une_escape_privee_est_refuse_sans_invitation(self):
        privee = EscapeGame.objects.create(
            title="Privee", city="Paris", latitude=48.85, longitude=2.35,
            status="published", owner=self.proprietaire, is_private=True,
        )
        self.assertIn(self._lire(privee).status_code, (403, 404))

        # Invite, le meme joueur y a droit.
        privee.allowed_users.add(self.joueur)
        self.assertEqual(self._lire(privee).status_code, 200)

    def test_l_acces_anonyme_est_refuse(self):
        anonyme = APIClient()
        r = anonyme.get(f"/api/escapes/{self.escape.id}/leaderboard")
        self.assertEqual(r.status_code, 401)
