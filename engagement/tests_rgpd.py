"""Minimisation des donnees de localisation.

Les etapes « Point a atteindre » conservaient la position exacte du
joueur, horodatee et sans limite de duree, alors qu'aucun code ne la
lisait. Ces tests verrouillent le fait qu'on ne la stocke plus.
"""

from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from engagement.models import PlaySession
from games.models import EscapeGame, GameStep

User = get_user_model()


class PositionNonConserveeTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(username="marcheur", password="pw")
        self.client = APIClient()
        self.client.credentials(
            HTTP_AUTHORIZATION=f"Token {Token.objects.create(user=self.user).key}"
        )
        self.escape = EscapeGame.objects.create(
            title="Parcours", city="Toulouse",
            latitude=43.6047, longitude=1.4442, status="published",
        )
        GameStep.objects.create(
            escape=self.escape, order=1, title="Point", text="Rejoignez le point",
            answer_type="location", latitude=43.6047, longitude=1.4442,
            radius_m=50, reveal_mode="guided", auto_validate=True,
        )

    def test_la_position_du_joueur_n_est_pas_conservee(self):
        self.client.post(f"/api/escapes/{self.escape.id}/sessions/start")

        # Le joueur valide en etant sur place : la position transite pour
        # etre verifiee, mais ne doit pas etre gardee.
        r = self.client.post(
            f"/api/escapes/{self.escape.id}/sessions/answer",
            {"latitude": 43.6047, "longitude": 1.4442}, format="json",
        )
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.json().get("correct"), "l'etape doit bien etre validee")

        session = PlaySession.objects.get(user=self.user, escape=self.escape)
        trace = str(session.answers)
        self.assertNotIn("latitude", trace)
        self.assertNotIn("longitude", trace)
        self.assertNotIn("43.6047", trace)

    def test_la_validation_reste_tracee(self):
        """Controle inverse : on minimise, on ne perd pas l'information
        utile — savoir que l'etape a ete franchie."""
        self.client.post(f"/api/escapes/{self.escape.id}/sessions/start")
        self.client.post(
            f"/api/escapes/{self.escape.id}/sessions/answer",
            {"latitude": 43.6047, "longitude": 1.4442}, format="json",
        )

        session = PlaySession.objects.get(user=self.user, escape=self.escape)
        entree = list(session.answers.values())[0]
        self.assertEqual(entree["type"], "location")
        self.assertEqual(entree["value"], "location")
        self.assertIn("ts", entree)


class PurgeHistoriqueTests(TestCase):
    """La migration doit effacer ce qui a deja ete accumule."""

    def test_la_purge_retire_les_coordonnees_existantes(self):
        from engagement.migrations import (
            __name__ as _,  # noqa: F401  (garde le package importable)
        )
        from importlib import import_module

        user = User.objects.create_user(username="ancien_marcheur", password="pw")
        escape = EscapeGame.objects.create(
            title="Ancien", city="Lyon", latitude=45.76, longitude=4.83,
            status="published",
        )
        session = PlaySession.objects.create(
            user=user, escape=escape,
            answers={
                "12": {"type": "location", "value": "location",
                       "latitude": 45.764, "longitude": 4.835, "ts": "2026-01-01"},
                "13": {"type": "text", "value": "une reponse", "ts": "2026-01-01"},
            },
        )

        module = import_module("engagement.migrations.0015_purge_positions_gps_historiques")
        from django.apps import apps
        module.purger_positions(apps, None)

        session.refresh_from_db()
        etape_location = session.answers["12"]
        self.assertNotIn("latitude", etape_location)
        self.assertNotIn("longitude", etape_location)
        # Le reste de l'historique est intact.
        self.assertEqual(etape_location["value"], "location")
        self.assertEqual(session.answers["13"]["value"], "une reponse")
