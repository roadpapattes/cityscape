"""Tests de non-régression sécurité (voir l'audit de surface d'attaque).

Les limites de débit s'appuyant sur le cache Django, chaque test qui en
dépend bascule sur un cache local isolé et le vide au démarrage : sinon
l'ordre d'exécution des tests suffirait à les faire échouer.
"""

from datetime import timedelta

from django.contrib.auth import get_user_model
from django.core import mail
from django.core.cache import cache
from django.test import TestCase, override_settings
from django.utils import timezone
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
class PasswordResetRevokesTokensTests(TestCase):
    """Un jeton DRF n'expire jamais : si la reinitialisation du mot de passe
    ne le revoque pas, la victime d'un vol de jeton ne peut pas evincer
    l'attaquant — alors que c'est exactement le geste qu'elle fera."""

    def setUp(self):
        cache.clear()
        mail.outbox = []
        self.user = User.objects.create_user(
            username="victime", email="victime@example.com", password="ancien-mdp",
        )
        self.token = Token.objects.create(user=self.user)

    def _reset(self):
        """Parcours complet : demande du code, puis confirmation."""
        from engagement.models import PasswordResetToken
        self.client.post(
            "/api/auth/password-reset/request", {"email": "victime@example.com"},
            content_type="application/json",
        )
        code = PasswordResetToken.objects.filter(user=self.user, used=False).latest("created_at").code
        return self.client.post(
            "/api/auth/password-reset/confirm",
            {"email": "victime@example.com", "code": code, "new_password": "nouveau-mdp-solide-42"},
            content_type="application/json",
        )

    def test_stolen_token_stops_working_after_reset(self):
        pirate = APIClient()
        pirate.credentials(HTTP_AUTHORIZATION=f"Token {self.token.key}")
        self.assertEqual(pirate.get("/api/auth/me").status_code, 200)

        r = self._reset()
        self.assertEqual(r.status_code, 200, r.content)

        # L'attaquant doit etre evince, sans avoir rien fait entre-temps.
        self.assertEqual(pirate.get("/api/auth/me").status_code, 401)
        self.assertFalse(Token.objects.filter(user=self.user).exists())

    def test_other_users_tokens_are_untouched(self):
        """Controle inverse : on ne deconnecte que le compte concerne."""
        autre = User.objects.create_user(username="autre", email="autre@example.com", password="pw")
        jeton_autre = Token.objects.create(user=autre)

        self._reset()

        self.assertTrue(Token.objects.filter(key=jeton_autre.key).exists())


class SlidingTokenExpiryTests(TestCase):
    """90 jours depuis la DERNIERE utilisation : un joueur regulier n'est
    jamais deconnecte, un jeton oublie ou derobe finit par expirer."""

    def setUp(self):
        from engagement.models import UserProfile
        self.user = User.objects.create_user(username="joueur_exp", password="pw")
        self.profil, _ = UserProfile.objects.get_or_create(user=self.user)
        self.token = Token.objects.create(user=self.user)
        self.client = APIClient()
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {self.token.key}")

    def _vieillir(self, jours):
        from engagement.models import UserProfile
        UserProfile.objects.filter(pk=self.profil.pk).update(
            token_last_used=timezone.now() - timedelta(days=jours)
        )

    def test_un_jeton_recemment_utilise_reste_valide(self):
        self._vieillir(30)
        self.assertEqual(self.client.get("/api/auth/me").status_code, 200)

    def test_chaque_usage_repousse_l_echeance(self):
        """Le coeur du caractere glissant : 89 jours puis usage, et on
        repart pour 90 jours."""
        self._vieillir(89)
        self.assertEqual(self.client.get("/api/auth/me").status_code, 200)

        self.profil.refresh_from_db()
        age = timezone.now() - self.profil.token_last_used
        self.assertLess(age, timedelta(minutes=1),
                        "l'usage doit avoir reporte la date de derniere utilisation")

    def test_un_jeton_abandonne_expire_et_est_supprime(self):
        self._vieillir(91)
        self.assertEqual(self.client.get("/api/auth/me").status_code, 401)
        self.assertFalse(Token.objects.filter(pk=self.token.pk).exists(),
                         "un jeton expire ne doit pas rester en base")

    def test_le_deploiement_ne_deconnecte_personne(self):
        """Controle inverse decisif : les jetons anterieurs a cette
        fonctionnalite n'ont pas de date de derniere utilisation. Se fier a
        leur date de creation deconnecterait d'un coup tous les joueurs dont
        le jeton a plus de 90 jours."""
        from engagement.models import UserProfile
        ancien = User.objects.create_user(username="ancien_joueur", password="pw")
        jeton = Token.objects.create(user=ancien)
        Token.objects.filter(pk=jeton.pk).update(
            created=timezone.now() - timedelta(days=400)
        )
        UserProfile.objects.filter(user=ancien).update(token_last_used=None)

        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION=f"Token {jeton.key}")
        self.assertEqual(client.get("/api/auth/me").status_code, 200,
                         "un jeton de 400 jours doit survivre au deploiement")

        profil = UserProfile.objects.get(user=ancien)
        self.assertIsNotNone(profil.token_last_used,
                             "sa fenetre doit demarrer a cette premiere utilisation")

    def test_l_ecriture_est_limitee_pour_ne_pas_marteler_la_base(self):
        """Sans palier, chaque requete authentifiee serait une ecriture."""
        from engagement.models import UserProfile
        UserProfile.objects.filter(pk=self.profil.pk).update(
            token_last_used=timezone.now() - timedelta(hours=2)  # palier : 24 h
        )
        self.profil.refresh_from_db()
        avant = self.profil.token_last_used

        self.client.get("/api/auth/me")

        self.profil.refresh_from_db()
        self.assertEqual(self.profil.token_last_used, avant,
                         "pas de reecriture a l'interieur du palier")


@override_settings(CACHES=LOCMEM_CACHE)
class ChangePasswordTests(TestCase):
    """L'app appelait cet endpoint depuis le depart alors qu'il n'existait
    pas : Django repondait une page 404 en HTML, que l'app tentait de lire
    comme du JSON."""

    URL = "/api/auth/change-password"

    def setUp(self):
        cache.clear()
        self.user = User.objects.create_user(username="bob_mdp", password="ancien-mdp-solide")
        self.token = Token.objects.create(user=self.user)
        self.client = APIClient()
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {self.token.key}")

    def test_la_reponse_est_du_json_pas_une_page_html(self):
        r = self.client.post(
            self.URL,
            {"old_password": "ancien-mdp-solide", "new_password": "nouveau-mdp-solide-42"},
            format="json",
        )
        self.assertEqual(r.status_code, 200)
        self.assertIn("application/json", r["Content-Type"])

    def test_le_mot_de_passe_est_effectivement_change(self):
        self.client.post(
            self.URL,
            {"old_password": "ancien-mdp-solide", "new_password": "nouveau-mdp-solide-42"},
            format="json",
        )
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password("nouveau-mdp-solide-42"))

    def test_l_ancien_mot_de_passe_est_exige(self):
        r = self.client.post(
            self.URL,
            {"old_password": "pas-le-bon", "new_password": "nouveau-mdp-solide-42"},
            format="json",
        )
        self.assertEqual(r.status_code, 400)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password("ancien-mdp-solide"))

    def test_un_mot_de_passe_faible_est_refuse(self):
        r = self.client.post(
            self.URL,
            {"old_password": "ancien-mdp-solide", "new_password": "1234"},
            format="json",
        )
        self.assertEqual(r.status_code, 400)

    def test_l_ancien_jeton_est_revoque_et_un_neuf_est_renvoye(self):
        """Un attaquant partage exactement le meme jeton que la victime :
        le conserver viderait l'operation de son sens."""
        ancien_jeton = self.token.key
        r = self.client.post(
            self.URL,
            {"old_password": "ancien-mdp-solide", "new_password": "nouveau-mdp-solide-42"},
            format="json",
        )
        nouveau_jeton = r.json().get("token")

        self.assertIsNotNone(nouveau_jeton, "l'app doit recevoir un jeton de remplacement")
        self.assertNotEqual(nouveau_jeton, ancien_jeton)

        pirate = APIClient()
        pirate.credentials(HTTP_AUTHORIZATION=f"Token {ancien_jeton}")
        self.assertEqual(pirate.get("/api/auth/me").status_code, 401)

        legitime = APIClient()
        legitime.credentials(HTTP_AUTHORIZATION=f"Token {nouveau_jeton}")
        self.assertEqual(legitime.get("/api/auth/me").status_code, 200)


@override_settings(CACHES=LOCMEM_CACHE)
class ConnexionApresLongueAbsenceTests(TestCase):
    """Cas limite introduit par l'expiration glissante : la connexion ne
    passe pas par l'authentification par jeton, donc sans remise a zero de
    la fenetre, le joueur se connecte puis est ejecte a sa requete
    suivante."""

    def setUp(self):
        cache.clear()
        self.user = User.objects.create_user(username="revenant", password="mdp-de-test-42")
        Token.objects.create(user=self.user)

    def test_un_joueur_absent_depuis_plus_de_90_jours_peut_revenir(self):
        from engagement.models import UserProfile
        profil, _ = UserProfile.objects.get_or_create(user=self.user)
        UserProfile.objects.filter(pk=profil.pk).update(
            token_last_used=timezone.now() - timedelta(days=200)
        )

        r = self.client.post(
            "/api/auth/login",
            {"username": "revenant", "password": "mdp-de-test-42"},
            content_type="application/json",
        )
        self.assertEqual(r.status_code, 200)
        jeton = r.json()["token"]

        # Le jeton remis doit fonctionner immediatement, sans boucle.
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION=f"Token {jeton}")
        self.assertEqual(client.get("/api/auth/me").status_code, 200)


class ClientIpResolutionTests(TestCase):
    """Derrière nginx, REMOTE_ADDR vaut 127.0.0.1 pour tout le monde : sans
    résolveur, toutes les limites par IP partagent un compteur global."""

    def _request(self, **meta):
        from django.test import RequestFactory
        request = RequestFactory().post("/")
        request.META.update(meta)
        return request

    def test_prefers_the_header_nginx_overwrites(self):
        from .ratelimit_ip import client_ip
        request = self._request(HTTP_X_REAL_IP="203.0.113.7", REMOTE_ADDR="127.0.0.1")
        self.assertEqual(client_ip(request), "203.0.113.7")

    def test_falls_back_to_remote_addr_without_proxy(self):
        from .ratelimit_ip import client_ip
        request = self._request(REMOTE_ADDR="198.51.100.4")
        self.assertEqual(client_ip(request), "198.51.100.4")

    def test_spoofable_forwarded_for_is_ignored(self):
        from .ratelimit_ip import client_ip
        request = self._request(
            HTTP_X_FORWARDED_FOR="1.2.3.4", HTTP_X_REAL_IP="203.0.113.7",
            REMOTE_ADDR="127.0.0.1",
        )
        self.assertEqual(client_ip(request), "203.0.113.7")

    def test_garbage_never_raises(self):
        """django_ratelimit._get_ip lève sur une valeur illisible, ce qui
        transformerait la page de connexion en erreur 500."""
        from .ratelimit_ip import client_ip
        for junk in ("", "pas-une-ip", "999.999.999.999", "<script>"):
            request = self._request(HTTP_X_REAL_IP=junk, REMOTE_ADDR="")
            self.assertEqual(client_ip(request), "0.0.0.0")


@override_settings(CACHES=LOCMEM_CACHE)
class PerClientRateLimitTests(TestCase):
    """Le test qui compte : deux clients distincts doivent avoir des
    compteurs indépendants."""

    URL = "/api/auth/delete-account-request"

    def setUp(self):
        cache.clear()
        mail.outbox = []

    def _post(self, ip):
        return self.client.post(
            self.URL, {"email": "inconnu@example.com"},
            content_type="application/json", HTTP_X_REAL_IP=ip,
        )

    def test_one_client_exhausting_its_quota_does_not_block_another(self):
        for _ in range(4):
            self._post("203.0.113.7")
        self.assertEqual(self._post("203.0.113.7").status_code, 429)

        # Un second client, parfaitement légitime, ne doit pas payer pour le
        # premier — c'était le cas avant ce correctif.
        self.assertEqual(self._post("198.51.100.4").status_code, 200)


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
