# -*- coding: utf-8 -*-
"""Chronometrage : ce que le client declare, et ce que le serveur mesure.

Le temps de jeu etait entierement declare par le client. Ces tests fixent la
propriete qui rendra un classement defendable : le temps mesure par le
serveur ne depend d'aucune valeur envoyee par le client.
"""

from datetime import timedelta

from django.contrib.auth import get_user_model
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from engagement.chronometrage import (
    ECART_ACTIVITE_MAX, ECART_MIN_ECRITURE, cumuler_temps_client,
    ecoule_serveur, enregistrer_activite,
)
from engagement.models import PlaySession
from games.models import EscapeGame, GameStep

User = get_user_model()


class ChronoTestCase(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(username="chrono", password="pw")
        self.escape = EscapeGame.objects.create(
            title="Escape chrono", city="Paris", latitude=48.85, longitude=2.35,
            status="published",
        )
        GameStep.objects.create(
            escape=self.escape, order=1, title="Etape 1", text="?",
            answer_type="text", answer_text="reponse un",
        )
        GameStep.objects.create(
            escape=self.escape, order=2, title="Etape 2", text="?",
            answer_type="text", answer_text="reponse deux",
        )
        self.sess = PlaySession.objects.create(user=self.user, escape=self.escape)

    def _vieillir_session(self, secondes):
        """Recule started_at, auto_now_add empechant de le fixer a la creation.

        Renvoie le started_at obtenu : les tests qui enchainent des instants
        doivent partir de cette valeur et non d'un timezone.now() pris a
        cote, sans quoi les quelques millisecondes d'ecart faussent les
        comparaisons a la seconde.
        """
        PlaySession.objects.filter(id=self.sess.id).update(
            started_at=timezone.now() - timedelta(seconds=secondes),
        )
        self.sess.refresh_from_db()
        return self.sess.started_at


class MesureServeurTests(ChronoTestCase):
    def test_la_premiere_action_compte_depuis_le_debut_de_la_session(self):
        """Le temps passe entre le lancement et la premiere reponse est du
        jeu : le joueur lit l'enonce, se deplace, cherche."""
        self._vieillir_session(60)
        ajout = enregistrer_activite(self.sess)
        self.assertEqual(ajout, 60)
        self.sess.refresh_from_db()
        self.assertEqual(self.sess.server_play_seconds, 60)

    def test_les_ecarts_successifs_s_additionnent(self):
        debut = self._vieillir_session(0)
        enregistrer_activite(self.sess, maintenant=debut + timedelta(seconds=30))
        enregistrer_activite(self.sess, maintenant=debut + timedelta(seconds=50))
        enregistrer_activite(self.sess, maintenant=debut + timedelta(seconds=90))
        self.sess.refresh_from_db()
        # 30 depuis le depart, puis 20, puis 40.
        self.assertEqual(self.sess.server_play_seconds, 90)

    def test_une_pause_longue_n_est_pas_comptee_comme_du_jeu(self):
        debut = self._vieillir_session(0)
        enregistrer_activite(self.sess, maintenant=debut + timedelta(seconds=30))

        # Le joueur revient le lendemain : l'ecart depasse le plafond.
        ajout = enregistrer_activite(
            self.sess, maintenant=debut + timedelta(seconds=30 + ECART_ACTIVITE_MAX + 1),
        )
        self.assertEqual(ajout, 0)
        self.sess.refresh_from_db()
        self.assertEqual(self.sess.server_play_seconds, 30)

    def test_un_ecart_juste_sous_le_plafond_compte_entierement(self):
        debut = self._vieillir_session(0)
        enregistrer_activite(self.sess, maintenant=debut)
        enregistrer_activite(
            self.sess, maintenant=debut + timedelta(seconds=ECART_ACTIVITE_MAX),
        )
        self.sess.refresh_from_db()
        self.assertEqual(self.sess.server_play_seconds, ECART_ACTIVITE_MAX)

    def test_un_ecart_tres_court_n_est_pas_perdu_mais_differe(self):
        """Les pings de proximite arrivent jusqu'a 60 fois par minute : on
        n'ecrit pas a chaque fois, mais le temps ne doit pas disparaitre."""
        debut = self._vieillir_session(0)
        enregistrer_activite(self.sess, maintenant=debut)

        # Deux pings rapproches : rien n'est enregistre.
        for i in (1, 2):
            ajout = enregistrer_activite(
                self.sess, maintenant=debut + timedelta(seconds=i),
            )
            self.assertEqual(ajout, 0)
        self.sess.refresh_from_db()
        self.assertEqual(self.sess.server_play_seconds, 0)

        # Le ping suivant, au-dela du seuil, compte tout l'ecart depuis la
        # derniere action retenue.
        ajout = enregistrer_activite(
            self.sess, maintenant=debut + timedelta(seconds=ECART_MIN_ECRITURE + 5),
        )
        self.assertEqual(ajout, ECART_MIN_ECRITURE + 5)

    def test_la_mesure_serveur_ne_depend_d_aucune_valeur_du_client(self):
        """La propriete qui rend un classement defendable."""
        self._vieillir_session(120)
        enregistrer_activite(self.sess)
        self.sess.refresh_from_db()
        mesure = self.sess.server_play_seconds

        # Le client declare ce qu'il veut : la mesure serveur ne bouge pas.
        cumuler_temps_client(self.sess, 0)
        cumuler_temps_client(self.sess, -9999)
        cumuler_temps_client(self.sess, 10 ** 9)
        self.sess.refresh_from_db()
        self.assertEqual(self.sess.server_play_seconds, mesure)


class TempsDeclareParLeClientTests(ChronoTestCase):
    def test_le_temps_declare_est_borne_par_l_ecoule_reel(self):
        """On ne peut pas avoir joue deux heures dans une fenetre de dix
        minutes."""
        self._vieillir_session(600)
        total = cumuler_temps_client(self.sess, 7200)
        self.assertLessEqual(total, 600)
        self.sess.refresh_from_db()
        self.assertLessEqual(self.sess.play_time_seconds, 600)

    def test_un_temps_plausible_est_accepte_tel_quel(self):
        self._vieillir_session(600)
        self.assertEqual(cumuler_temps_client(self.sess, 300), 300)

    def test_les_valeurs_invalides_valent_zero(self):
        self._vieillir_session(600)
        for valeur in (None, "", "abc", -42, [1, 2]):
            self.assertEqual(
                cumuler_temps_client(self.sess, valeur), 0,
                f"{valeur!r} ne doit rien ajouter",
            )

    def test_l_ecoule_s_arrete_a_la_fin_de_la_partie(self):
        """Sinon le plafond grandirait indefiniment apres la fin, et une
        session terminee pourrait se voir rajouter du temps."""
        self._vieillir_session(600)
        self.sess.completed_at = self.sess.started_at + timedelta(seconds=120)
        self.sess.save(update_fields=["completed_at"])
        self.assertEqual(ecoule_serveur(self.sess), 120)
        self.assertLessEqual(cumuler_temps_client(self.sess, 7200), 120)


@override_settings(RATELIMIT_ENABLE=False)
class ChronoParLEndpointTests(ChronoTestCase):
    """Le serveur mesure-t-il vraiment quand on joue pour de bon ?"""

    def setUp(self):
        super().setUp()
        self.client = APIClient()
        self.client.credentials(
            HTTP_AUTHORIZATION=f"Token {Token.objects.create(user=self.user).key}"
        )

    def test_repondre_alimente_la_mesure_serveur_sans_rien_declarer(self):
        """Le cas du tricheur : il n'envoie aucun temps. Le serveur compte
        quand meme."""
        self._vieillir_session(90)
        r = self.client.post(
            f"/api/escapes/{self.escape.id}/sessions/answer",
            {"answer": "reponse un"}, format="json",
        )
        self.assertEqual(r.status_code, 200, r.content)

        self.sess.refresh_from_db()
        self.assertEqual(self.sess.play_time_seconds, 0, "il n'a rien declare")
        self.assertGreaterEqual(
            self.sess.server_play_seconds, 89, "le serveur a mesure malgre tout",
        )

    def test_declarer_un_temps_absurde_ne_passe_pas(self):
        self._vieillir_session(60)
        r = self.client.post(
            f"/api/escapes/{self.escape.id}/sessions/answer",
            {"answer": "reponse un", "session_seconds": 999999}, format="json",
        )
        self.assertEqual(r.status_code, 200, r.content)
        self.sess.refresh_from_db()
        self.assertLessEqual(self.sess.play_time_seconds, 61)

    def test_le_endpoint_de_synchronisation_borne_aussi(self):
        self._vieillir_session(60)
        r = self.client.post(
            f"/api/escapes/{self.escape.id}/sessions/sync_time",
            {"additional_seconds": 999999}, format="json",
        )
        self.assertEqual(r.status_code, 200, r.content)
        self.assertLessEqual(r.json()["play_time_seconds"], 61)

    def test_demander_un_indice_alimente_la_mesure(self):
        GameStep.objects.filter(escape=self.escape, order=1).update(
            hints=["un indice"],
        )
        self._vieillir_session(45)
        r = self.client.post(f"/api/escapes/{self.escape.id}/sessions/hint")
        self.assertEqual(r.status_code, 200, r.content)
        self.sess.refresh_from_db()
        self.assertGreaterEqual(self.sess.server_play_seconds, 44)

    def test_le_temps_mesure_n_est_pas_divulgue_au_joueur(self):
        """Lui montrer la mesure serveur reviendrait a lui indiquer
        exactement ce qu'il doit declarer pour rester credible."""
        self._vieillir_session(90)
        r = self.client.post(
            f"/api/escapes/{self.escape.id}/sessions/answer",
            {"answer": "reponse un"}, format="json",
        )
        self.assertNotIn("server_play_seconds", r.json())
        self.assertNotIn("last_activity_at", str(r.json()))
