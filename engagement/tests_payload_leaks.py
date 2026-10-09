"""Ce que le serveur envoie vraiment à l'app, pour une étape non résolue.

Surface D de l'audit : plutôt que de relire _step_payload, on inspecte le
JSON réellement transmis. Chaque test cherche le secret dans la réponse
entière sérialisée, pas seulement dans les champs attendus — une fuite
passe souvent par un nom de champ auquel on n'a pas pensé.

Note : les étapes DÉJÀ résolues exposent volontairement leur configuration
dans past_steps (c'est l'historique de fin de partie). Ces tests portent
donc sur l'étape courante, la seule qui doive garder ses secrets.
"""

import json

from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from games.models import EscapeGame, GameStep

User = get_user_model()


class PayloadLeakTestCase(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(username="joueur_fuite", password="pw")
        self.client = APIClient()
        self.client.credentials(
            HTTP_AUTHORIZATION=f"Token {Token.objects.create(user=self.user).key}"
        )
        self.escape = EscapeGame.objects.create(
            title="Escape test", city="Paris", latitude=48.85, longitude=2.35,
            status="published",
        )

    def _current_step_payload(self):
        r = self.client.post(f"/api/escapes/{self.escape.id}/sessions/start")
        self.assertIn(r.status_code, (200, 201))
        step = r.json()["step"]
        self.assertIsNotNone(step, "l'étape courante doit être renvoyée")

        # Témoin positif : sans lui, un test d'absence passerait tout aussi
        # bien sur une charge utile vide, sans rien prouver.
        self.assertTrue(
            step.get("title"), "charge utile vide : le test d'absence ne prouverait rien",
        )
        return step

    def _assert_absent(self, payload, secret, label):
        """Cherche le secret partout dans la réponse, pas juste là où on
        l'attendrait."""
        serialise = json.dumps(payload, ensure_ascii=False).lower()
        self.assertNotIn(
            str(secret).lower(), serialise,
            f"{label} ne doit jamais être transmis au client : {payload}",
        )


class TextAnswerLeakTests(PayloadLeakTestCase):
    def test_free_text_answer_is_never_sent(self):
        GameStep.objects.create(
            escape=self.escape, order=1, title="Énigme", text="Quelle ville ?",
            answer_type="text", answer_text="Carcassonne",
        )
        self._assert_absent(self._current_step_payload(), "Carcassonne", "la réponse")

    def test_alternative_answers_are_never_sent(self):
        """Les formulations alternatives sont des réponses : les livrer
        reviendrait à donner la solution, et en plusieurs exemplaires."""
        GameStep.objects.create(
            escape=self.escape, order=1, title="Énigme", text="Quel monument ?",
            answer_type="text", answer_text="La tour Eiffel",
            answer_text_alt=["tour Eiffel", "Carcassonne"],
        )
        payload = self._current_step_payload()
        self._assert_absent(payload, "La tour Eiffel", "la réponse")
        self._assert_absent(payload, "Carcassonne", "une réponse acceptée")
        self.assertNotIn("answer_text_alt", payload)

    def test_caesar_answer_is_never_sent(self):
        GameStep.objects.create(
            escape=self.escape, order=1, title="César", text="Fxufxvrqqh",
            answer_type="cesar", answer_text="Carcassonne",
        )
        self._assert_absent(self._current_step_payload(), "Carcassonne", "la réponse déchiffrée")

    def test_numeric_answer_is_never_sent(self):
        GameStep.objects.create(
            escape=self.escape, order=1, title="Compte", text="Combien ?",
            answer_type="numeric", answer_text="1789",
        )
        self._assert_absent(self._current_step_payload(), "1789", "la réponse numérique")


class McqLeakTests(PayloadLeakTestCase):
    def test_options_are_sent_but_not_the_correct_index(self):
        GameStep.objects.create(
            escape=self.escape, order=1, title="QCM", text="Laquelle ?",
            answer_type="mcq", options=["Paris", "Lyon", "Marseille"], correct_index=2,
        )
        payload = self._current_step_payload()

        # Les options sont nécessaires pour jouer...
        self.assertEqual(payload.get("options"), ["Paris", "Lyon", "Marseille"])
        # ...mais pas la bonne réponse.
        self.assertNotIn("correct_index", payload)
        self.assertNotIn("correct", json.dumps(payload).lower())


class MatchingLeakTests(PayloadLeakTestCase):
    def test_pairs_solution_is_never_sent(self):
        GameStep.objects.create(
            escape=self.escape, order=1, title="Association", text="Associez",
            answer_type="matching",
            match_left=["France", "Italie"], match_right=["Paris", "Rome"],
            match_pairs=[[0, 0], [1, 1]],
        )
        payload = self._current_step_payload()

        # Les deux colonnes sont nécessaires...
        self.assertEqual(payload.get("matching_left"), ["France", "Italie"])
        self.assertEqual(payload.get("matching_right"), ["Paris", "Rome"])
        # ...mais jamais la solution.
        for champ in ("match_pairs", "matching_pairs", "pairs"):
            self.assertNotIn(champ, payload)


class HintLeakTests(PayloadLeakTestCase):
    def test_unrevealed_hints_are_never_sent(self):
        GameStep.objects.create(
            escape=self.escape, order=1, title="Énigme", text="Trouvez",
            answer_type="text", answer_text="reponse",
            hints=["Premier indice tres revelateur", "Second indice decisif"],
            hint_penalty=5,
        )
        payload = self._current_step_payload()

        # Le joueur sait qu'il existe des indices, sans en voir le contenu.
        self.assertEqual(payload.get("hints_total"), 2)
        self.assertEqual(payload.get("revealed_hints"), [])
        self._assert_absent(payload, "Premier indice tres revelateur", "un indice non débloqué")
        self._assert_absent(payload, "Second indice decisif", "un indice non débloqué")


class LocationTargetLeakTests(PayloadLeakTestCase):
    """Anti-triche GPS : en chaud/froid et en aveugle, la cible ne doit
    jamais transiter, sinon un client modifié l'affiche directement."""

    def _location_step(self, reveal_mode):
        GameStep.objects.create(
            escape=self.escape, order=1, title="Point", text="Rejoignez le point",
            answer_type="location", latitude=43.6047, longitude=1.4442,
            radius_m=30, reveal_mode=reveal_mode, auto_validate=True,
        )

    def test_hotcold_never_reveals_the_target(self):
        self._location_step("hotcold")
        payload = self._current_step_payload()
        self.assertIsNone(payload.get("latitude"))
        self.assertIsNone(payload.get("longitude"))
        self._assert_absent(payload, "43.6047", "la latitude de la cible")
        self._assert_absent(payload, "1.4442", "la longitude de la cible")

    def test_blind_never_reveals_the_target(self):
        self._location_step("blind")
        payload = self._current_step_payload()
        self.assertIsNone(payload.get("latitude"))
        self.assertIsNone(payload.get("longitude"))
        self._assert_absent(payload, "43.6047", "la latitude de la cible")

    def test_guided_does_reveal_the_target_on_purpose(self):
        """Contrôle inverse : en mode guidé, la carte doit afficher le point."""
        self._location_step("guided")
        payload = self._current_step_payload()
        self.assertAlmostEqual(payload.get("latitude"), 43.6047, places=4)
        self.assertAlmostEqual(payload.get("longitude"), 1.4442, places=4)
        self.assertTrue(payload.get("show_location"))


class FutureStepsLeakTests(PayloadLeakTestCase):
    """Les étapes suivantes ne doivent pas être pré-chargées : sinon tout
    l'escape se lit d'un coup au premier appel."""

    def test_only_the_current_step_is_sent(self):
        GameStep.objects.create(
            escape=self.escape, order=1, title="Etape 1", text="Premiere",
            answer_type="text", answer_text="reponse1",
        )
        GameStep.objects.create(
            escape=self.escape, order=2, title="Etape secrete", text="Enonce futur",
            answer_type="text", answer_text="reponse2",
        )

        r = self.client.post(f"/api/escapes/{self.escape.id}/sessions/start")
        entier = json.dumps(r.json(), ensure_ascii=False)

        self.assertIn("Premiere", entier)
        for secret in ("Etape secrete", "Enonce futur", "reponse1", "reponse2"):
            self.assertNotIn(
                secret, entier,
                f"« {secret} » ne doit pas être transmis avant d'avoir atteint l'étape",
            )
