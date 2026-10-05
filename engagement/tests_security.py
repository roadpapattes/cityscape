"""Tests de non-régression sécurité (voir l'audit de surface d'attaque).

Les limites de débit s'appuyant sur le cache Django, chaque test qui en
dépend bascule sur un cache local isolé et le vide au démarrage : sinon
l'ordre d'exécution des tests suffirait à les faire échouer.
"""

from django.contrib.auth import get_user_model
from django.core import mail
from django.core.cache import cache
from django.test import TestCase, override_settings
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from games.models import EscapeGame

User = get_user_model()

LOCMEM_CACHE = {
    "default": {
        "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
        "LOCATION": "security-tests",
    }
}


@override_settings(CACHES=LOCMEM_CACHE)
class AccountDeletionHardeningTests(TestCase):
    """Faiblesse 01 : relais d'email ouvert, non limité, et oracle
    d'énumération d'adresses."""

    URL = "/api/auth/delete-account-request"

    def setUp(self):
        cache.clear()
        mail.outbox = []
        self.user = User.objects.create_user(
            username="victime", email="victime@example.com", password="pw",
        )

    def test_response_is_identical_whether_the_account_exists_or_not(self):
        known = self.client.post(
            self.URL, {"email": "victime@example.com"}, content_type="application/json",
        )
        cache.clear()  # ne pas se faire bloquer par la limite de débit
        unknown = self.client.post(
            self.URL, {"email": "inconnu@example.com"}, content_type="application/json",
        )

        self.assertEqual(known.status_code, unknown.status_code)
        self.assertEqual(known.json(), unknown.json())

    def test_user_supplied_reason_is_not_relayed_to_the_account_holder(self):
        phishing = "URGENT cliquez sur https://evil.example pour conserver votre compte"
        r = self.client.post(
            self.URL,
            {"email": "victime@example.com", "reason": phishing},
            content_type="application/json",
        )
        self.assertEqual(r.status_code, 200)

        to_user = [m for m in mail.outbox if "victime@example.com" in m.to]
        self.assertTrue(to_user, "l'email au titulaire du compte doit bien partir")
        for message in to_user:
            self.assertNotIn("evil.example", message.body)
            self.assertNotIn(phishing, message.body)

    def test_rate_limit_blocks_mail_flooding(self):
        last = None
        for _ in range(5):
            last = self.client.post(
                self.URL, {"email": "victime@example.com"}, content_type="application/json",
            )
        self.assertEqual(last.status_code, 429)


@override_settings(CACHES=LOCMEM_CACHE)
class AnswerSubmissionRateLimitTests(TestCase):
    """Faiblesse 04 : sans borne sur les tentatives, la cible d'une étape
    « Point à atteindre » se triangule par dichotomie, même en mode blind."""

    def setUp(self):
        cache.clear()
        self.user = User.objects.create_user(username="tricheur", password="pw")
        self.token = Token.objects.create(user=self.user)
        self.client = APIClient()
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {self.token.key}")
        self.escape = EscapeGame.objects.create(
            title="Cible", city="X", latitude=48.85, longitude=2.35, status="published",
        )

    def test_answer_submissions_are_eventually_blocked(self):
        url = f"/api/escapes/{self.escape.id}/sessions/answer"
        statuses = []
        for i in range(35):
            statuses.append(
                self.client.post(url, {"answer": f"essai-{i}"}, format="json").status_code
            )

        # La limite doit mordre, mais pas dès les premières tentatives :
        # un joueur légitime se trompe plusieurs fois sans être bloqué.
        self.assertNotIn(429, statuses[:10])
        self.assertIn(429, statuses)

    def test_proximity_pings_are_eventually_blocked(self):
        url = f"/api/escapes/{self.escape.id}/sessions/proximity"
        statuses = []
        for _ in range(65):
            statuses.append(
                self.client.post(
                    url, {"latitude": 48.85, "longitude": 2.35}, format="json",
                ).status_code
            )

        # L'app interroge la proximité toutes les ~3 s, soit ~20/min : la
        # limite doit laisser passer confortablement ce rythme.
        self.assertNotIn(429, statuses[:25])
        self.assertIn(429, statuses)
