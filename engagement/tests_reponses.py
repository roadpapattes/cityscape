# -*- coding: utf-8 -*-
"""Tolérance de la comparaison des réponses en texte libre et en chiffre de César.

Ces tests verrouillent un contrat volontaire : un joueur qui a trouvé la
réponse ne doit pas se la voir refuser pour une différence de forme
(casse, accents, espaces, ponctuation), mais une faute de frappe reste
une mauvaise réponse.

Le contrat tenait jusqu'ici dans une fonction qu'une seconde définition
du même nom écrasait silencieusement dans le module. Rien ne le
vérifiait, donc rien n'empêchait de le perdre : d'où ce fichier.
"""

from django.contrib.auth import get_user_model
from django.test import TestCase, override_settings
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from engagement.views import _normalize
from games.models import EscapeGame, GameStep

User = get_user_model()


class NormalisationTests(TestCase):
    """La fonction de comparaison, isolée du reste."""

    def _accepte(self, attendue, saisie):
        return _normalize(saisie) == _normalize(attendue)

    def test_la_casse_est_ignoree(self):
        for saisie in ("les etoiles", "LES ETOILES", "Les Etoiles", "lEs EtOiLeS"):
            self.assertTrue(
                self._accepte("Les étoiles", saisie),
                f"« {saisie} » devrait être acceptée pour « Les étoiles »",
            )

    def test_les_accents_sont_ignores(self):
        for attendue, saisie in (
            ("Les étoiles", "les etoiles"),
            ("les etoiles", "Les étoiles"),
            ("La forêt", "la foret"),
            ("Noël", "noel"),
            ("Çà et là", "ca et la"),
        ):
            self.assertTrue(
                self._accepte(attendue, saisie),
                f"« {saisie} » devrait être acceptée pour « {attendue} »",
            )

    def test_espaces_ponctuation_et_traits_dunion_sont_ignores(self):
        for saisie in (
            "les-etoiles", "les étoiles !", "  les   etoiles  ", "LesEtoiles",
            "les, etoiles.", "«les étoiles»",
        ):
            self.assertTrue(
                self._accepte("Les étoiles", saisie),
                f"« {saisie} » devrait être acceptée pour « Les étoiles »",
            )

    def test_l_apostrophe_droite_ou_courbe_est_indifferente(self):
        for saisie in ("l'eglise", "l’église", "l eglise", "leglise"):
            self.assertTrue(
                self._accepte("L'église", saisie),
                f"« {saisie} » devrait être acceptée pour « L'église »",
            )

    def test_une_faute_de_frappe_reste_une_mauvaise_reponse(self):
        """La limite explicite du contrat : aucune tolérance d'édition."""
        for saisie in ("les etoils", "les etoile", "les etoilles", "lesetoilez", "etoiles"):
            self.assertFalse(
                self._accepte("Les étoiles", saisie),
                f"« {saisie} » ne doit PAS être acceptée pour « Les étoiles »",
            )

    def test_une_autre_reponse_reste_refusee(self):
        self.assertFalse(self._accepte("Les étoiles", "la lune"))
        self.assertFalse(self._accepte("Les étoiles", ""))
        self.assertFalse(self._accepte("Les étoiles", "   "))

    def test_la_reponse_vide_ne_vaut_jamais_bonne_reponse(self):
        """Garde-fou : deux chaînes vides sont égales, mais une étape sans
        réponse attendue ne doit pas valider n'importe quelle saisie vide."""
        self.assertEqual(_normalize(""), _normalize("   "))
        self.assertEqual(_normalize(None), "")


@override_settings(RATELIMIT_ENABLE=False)
class ReponseParLEndpointTests(TestCase):
    """Le même contrat, mais à travers l'API réellement appelée par l'app.

    Les tests unitaires ci-dessus prouvent la fonction ; celui-ci prouve
    qu'elle est bien celle que le moteur de jeu utilise.
    """

    def setUp(self):
        self.user = User.objects.create_user(username="joueuse_reponses", password="pw")
        self.client = APIClient()
        self.client.credentials(
            HTTP_AUTHORIZATION=f"Token {Token.objects.create(user=self.user).key}"
        )

    def _escape_avec_reponse(self, answer_type, attendue):
        escape = EscapeGame.objects.create(
            title=f"Escape {answer_type} {attendue}", city="Paris",
            latitude=48.85, longitude=2.35, status="published",
        )
        GameStep.objects.create(
            escape=escape, order=1, title="Étape", text="?",
            answer_type=answer_type, answer_text=attendue,
        )
        r = self.client.post(f"/api/escapes/{escape.id}/sessions/start")
        self.assertIn(r.status_code, (200, 201))
        return escape

    def _soumettre(self, escape, saisie):
        r = self.client.post(
            f"/api/escapes/{escape.id}/sessions/answer", {"answer": saisie}, format="json",
        )
        self.assertEqual(r.status_code, 200, r.content)
        return r.json().get("correct")

    def test_texte_libre_accepte_sans_accents_ni_casse(self):
        escape = self._escape_avec_reponse(GameStep.ANSWER_TEXT, "Les étoiles")
        self.assertTrue(self._soumettre(escape, "les etoiles"))

    def test_texte_libre_refuse_une_faute_de_frappe(self):
        escape = self._escape_avec_reponse(GameStep.ANSWER_TEXT, "Les étoiles")
        self.assertFalse(self._soumettre(escape, "les etoils"))

    def test_cesar_accepte_sans_accents_ni_casse(self):
        escape = self._escape_avec_reponse(GameStep.ANSWER_CAESAR, "Les étoiles")
        self.assertTrue(self._soumettre(escape, "les etoiles"))

    def test_cesar_refuse_une_faute_de_frappe(self):
        escape = self._escape_avec_reponse(GameStep.ANSWER_CAESAR, "Les étoiles")
        self.assertFalse(self._soumettre(escape, "les etoils"))
