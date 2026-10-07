"""Parcours IDOR : un utilisateur B peut-il atteindre les données de A ?

Méthode : pour chaque endpoint prenant un identifiant d'objet, on rejoue
l'appel avec le jeton d'un utilisateur qui n'a aucun droit dessus. Tout ce
qui répond autre chose qu'un refus est une faille.
"""

from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from games.models import EscapeGame, GameStep

User = get_user_model()

REFUS = (401, 403, 404)


def _escape(owner, **kwargs):
    defaults = dict(
        title="Escape de A", city="Paris", latitude=48.85, longitude=2.35,
        status="published", owner=owner,
    )
    defaults.update(kwargs)
    return EscapeGame.objects.create(**defaults)


def _step(escape, order=1):
    return GameStep.objects.create(
        escape=escape, order=order, title="Étape secrète",
        text="Contenu réservé", answer_type="text", answer_text="reponse",
    )


class IdorTestCase(TestCase):
    """Deux comptes sans aucun lien : A possède, B tente."""

    def setUp(self):
        self.alice = User.objects.create_user(username="alice_idor", password="pw")
        self.bob = User.objects.create_user(username="bob_idor", password="pw")

        self.bob_client = APIClient()
        self.bob_client.credentials(
            HTTP_AUTHORIZATION=f"Token {Token.objects.create(user=self.bob).key}"
        )
        self.alice_client = APIClient()
        self.alice_client.credentials(
            HTTP_AUTHORIZATION=f"Token {Token.objects.create(user=self.alice).key}"
        )


class CreatorOwnershipTests(IdorTestCase):
    """Le flanc créateur : get_queryset() filtre sur owner."""

    def setUp(self):
        super().setUp()
        self.escape = _escape(self.alice, status="draft")
        self.step = _step(self.escape)

    def test_bob_cannot_read_alices_escape(self):
        r = self.bob_client.get(f"/api/creator/escapes/{self.escape.id}")
        self.assertIn(r.status_code, REFUS)

    def test_bob_cannot_modify_alices_escape(self):
        r = self.bob_client.patch(
            f"/api/creator/escapes/{self.escape.id}", {"title": "Détourné"}, format="json",
        )
        self.assertIn(r.status_code, REFUS)
        self.escape.refresh_from_db()
        self.assertEqual(self.escape.title, "Escape de A")

    def test_bob_cannot_delete_alices_escape(self):
        r = self.bob_client.delete(f"/api/creator/escapes/{self.escape.id}")
        self.assertIn(r.status_code, REFUS)
        self.assertTrue(EscapeGame.objects.filter(pk=self.escape.pk).exists())

    def test_bob_cannot_list_alices_steps(self):
        r = self.bob_client.get(f"/api/creator/escapes/{self.escape.id}/steps")
        self.assertIn(r.status_code, REFUS)

    def test_bob_cannot_read_alices_step(self):
        r = self.bob_client.get(
            f"/api/creator/escapes/{self.escape.id}/steps/{self.step.id}"
        )
        self.assertIn(r.status_code, REFUS)

    def test_bob_cannot_modify_alices_step(self):
        r = self.bob_client.patch(
            f"/api/creator/escapes/{self.escape.id}/steps/{self.step.id}",
            {"title": "Détourné"}, format="json",
        )
        self.assertIn(r.status_code, REFUS)

    def test_bob_cannot_delete_alices_step(self):
        r = self.bob_client.delete(
            f"/api/creator/escapes/{self.escape.id}/steps/{self.step.id}"
        )
        self.assertIn(r.status_code, REFUS)
        self.assertTrue(GameStep.objects.filter(pk=self.step.pk).exists())

    def test_bob_cannot_reorder_alices_step(self):
        r = self.bob_client.post(
            f"/api/creator/escapes/{self.escape.id}/steps/{self.step.id}/move",
            {"direction": "up"}, format="json",
        )
        self.assertIn(r.status_code, REFUS)

    def test_bob_cannot_submit_alices_escape_for_review(self):
        r = self.bob_client.post(f"/api/creator/escapes/{self.escape.id}/submit")
        self.assertIn(r.status_code, REFUS)

    def test_bob_does_not_see_alices_escape_in_his_list(self):
        r = self.bob_client.get("/api/creator/escapes")
        self.assertEqual(r.status_code, 200)
        ids = [e["id"] for e in r.json()]
        self.assertNotIn(self.escape.id, ids)


class PrivateEscapeAccessTests(IdorTestCase):
    """Une escape privée n'est jouable que par son propriétaire ou un invité."""

    def setUp(self):
        super().setUp()
        self.private = _escape(self.alice, is_private=True, title="Escape privée de A")
        _step(self.private)

    def test_private_escape_is_absent_from_the_public_catalogue(self):
        r = self.bob_client.get("/api/escapes")
        self.assertEqual(r.status_code, 200)
        ids = [e["id"] for e in r.json()]
        self.assertNotIn(self.private.id, ids)

    def test_bob_cannot_start_a_session_on_a_private_escape(self):
        r = self.bob_client.post(f"/api/escapes/{self.private.id}/sessions/start")
        self.assertIn(r.status_code, REFUS)

    def test_an_invited_player_can_still_play(self):
        """Contrôle inverse : la restriction ne doit pas casser l'invitation."""
        self.private.allowed_users.add(self.bob)
        r = self.bob_client.post(f"/api/escapes/{self.private.id}/sessions/start")
        self.assertIn(r.status_code, (200, 201))

    def test_owner_can_still_play_her_own_private_escape(self):
        r = self.alice_client.post(f"/api/escapes/{self.private.id}/sessions/start")
        self.assertIn(r.status_code, (200, 201))


class UnpublishedEscapeAccessTests(IdorTestCase):
    """Le travail non publié d'un créateur ne doit pas fuiter par devinette
    d'identifiant."""

    def test_bob_cannot_start_a_session_on_a_draft(self):
        draft = _escape(self.alice, status="draft")
        _step(draft)
        r = self.bob_client.post(f"/api/escapes/{draft.id}/sessions/start")
        self.assertIn(r.status_code, REFUS)

    def test_bob_cannot_start_a_session_on_a_rejected_escape(self):
        rejected = _escape(self.alice, status="rejected")
        _step(rejected)
        r = self.bob_client.post(f"/api/escapes/{rejected.id}/sessions/start")
        self.assertIn(r.status_code, REFUS)

    def test_creator_can_still_test_her_own_draft(self):
        """Contrôle inverse : un créateur doit pouvoir jouer son brouillon."""
        draft = _escape(self.alice, status="draft")
        _step(draft)
        r = self.alice_client.post(f"/api/escapes/{draft.id}/sessions/start")
        self.assertIn(r.status_code, (200, 201))


class RatingIntegrityTests(IdorTestCase):
    """CanRateView annonce la règle (« avoir terminé l'escape ») mais le POST
    ne l'appliquait pas : le contrôle n'existait que côté client."""

    def setUp(self):
        super().setUp()
        self.escape = _escape(self.alice)
        _step(self.escape)

    def _rate(self, stars=1):
        return self.bob_client.post(
            f"/api/escapes/{self.escape.id}/ratings",
            {"stars": stars, "comment": "nul"}, format="json",
        )

    def test_rating_without_playing_is_refused(self):
        from engagement.models import Rating
        r = self._rate()
        self.assertEqual(r.status_code, 403)
        self.assertEqual(Rating.objects.count(), 0)

    def test_rating_after_finishing_still_works(self):
        """Contrôle inverse : le parcours légitime ne doit pas être cassé."""
        from django.utils import timezone
        from engagement.models import PlaySession
        PlaySession.objects.create(
            user=self.bob, escape=self.escape, completed_at=timezone.now(),
        )
        r = self._rate(stars=5)
        self.assertIn(r.status_code, (200, 201))


class AdminSurfaceTests(IdorTestCase):
    """Les endpoints d'administration refusent un joueur ordinaire."""

    def test_regular_user_is_refused_on_admin_endpoints(self):
        for url in ("/api/admin/users", "/api/admin/stats", "/api/admin/sessions"):
            with self.subTest(url=url):
                r = self.bob_client.get(url)
                self.assertIn(r.status_code, REFUS)
