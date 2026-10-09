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

    def _escape_avec_reponse(self, answer_type, attendue, alt=None):
        escape = EscapeGame.objects.create(
            title=f"Escape {answer_type} {attendue}", city="Paris",
            latitude=48.85, longitude=2.35, status="published",
        )
        GameStep.objects.create(
            escape=escape, order=1, title="Étape", text="?",
            answer_type=answer_type, answer_text=attendue,
            answer_text_alt=list(alt or []),
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


@override_settings(RATELIMIT_ENABLE=False)
class PlusieursReponsesAccepteesTests(ReponseParLEndpointTests):
    """Le créateur peut déclarer des formulations alternatives.

    La normalisation rattrape les différences de forme ; cette liste
    rattrape les différences de formulation, qu'aucune normalisation ne
    peut deviner.
    """

    def test_la_reponse_canonique_passe_toujours(self):
        escape = self._escape_avec_reponse(
            GameStep.ANSWER_TEXT, "La tour Eiffel", ["tour Eiffel", "Eiffel"],
        )
        self.assertTrue(self._soumettre(escape, "La tour Eiffel"))

    def test_chaque_alternative_est_acceptee(self):
        for saisie in ("tour Eiffel", "Eiffel", "TOUR EIFFEL", "eiffel"):
            escape = self._escape_avec_reponse(
                GameStep.ANSWER_TEXT, "La tour Eiffel", ["tour Eiffel", "Eiffel"],
            )
            self.assertTrue(
                self._soumettre(escape, saisie),
                f"« {saisie} » figure parmi les réponses acceptées",
            )

    def test_les_alternatives_beneficient_de_la_meme_normalisation(self):
        """Une alternative accentuée doit s'accepter sans accents, comme
        la réponse canonique."""
        escape = self._escape_avec_reponse(
            GameStep.ANSWER_TEXT, "Le phare", ["La jetée de l'Ouest"],
        )
        self.assertTrue(self._soumettre(escape, "la jetee de l ouest"))

    def test_une_reponse_hors_liste_reste_refusee(self):
        escape = self._escape_avec_reponse(
            GameStep.ANSWER_TEXT, "La tour Eiffel", ["tour Eiffel"],
        )
        self.assertFalse(self._soumettre(escape, "le Trocadéro"))

    def test_une_faute_de_frappe_sur_une_alternative_reste_refusee(self):
        escape = self._escape_avec_reponse(
            GameStep.ANSWER_TEXT, "La tour Eiffel", ["tour Eiffel"],
        )
        self.assertFalse(self._soumettre(escape, "tour Eifel"))

    def test_cesar_ignore_les_alternatives(self):
        """Une énigme à chiffre n'a qu'une seule réponse juste. L'interface
        créateur ne permet pas d'en déclarer, mais une étape créée par
        l'admin ou un import pourrait en porter : elles sont ignorées."""
        escape = self._escape_avec_reponse(
            GameStep.ANSWER_CAESAR, "Les étoiles", ["la lune"],
        )
        self.assertFalse(self._soumettre(escape, "la lune"))
        self.assertTrue(self._soumettre(escape, "les etoiles"))

    def test_une_saisie_vide_ne_valide_jamais_une_etape_sans_reponse(self):
        """Garde-fou : deux chaînes vides se normalisent pareil. Sans lui,
        une étape dont la réponse attendue est vide — impossible via
        l'interface créateur, pas via l'admin — validerait n'importe quoi."""
        escape = self._escape_avec_reponse(GameStep.ANSWER_TEXT, "")
        self.assertFalse(self._soumettre(escape, ""))
        self.assertFalse(self._soumettre(escape, "   "))
        self.assertFalse(self._soumettre(escape, "n importe quoi"))


class ValidationDesReponsesAccepteesTests(TestCase):
    """Ce que l'API créateur accepte d'enregistrer."""

    def setUp(self):
        self.createur = User.objects.create_user(username="createur_alt", password="pw")
        self.client = APIClient()
        self.client.credentials(
            HTTP_AUTHORIZATION=f"Token {Token.objects.create(user=self.createur).key}"
        )
        self.escape = EscapeGame.objects.create(
            title="Escape du créateur", city="Lyon", latitude=45.76, longitude=4.83,
            status="draft", owner=self.createur,
        )

    def _creer_etape(self, **champs):
        corps = dict(
            order=1, title="Étape", text="?",
            answer_type=GameStep.ANSWER_TEXT, answer_text="La tour Eiffel",
        )
        corps.update(champs)
        return self.client.post(
            f"/api/creator/escapes/{self.escape.id}/steps", corps, format="json",
        )

    def test_la_liste_est_enregistree_et_nettoyee(self):
        r = self._creer_etape(
            answer_text_alt=["  tour Eiffel  ", "", "Eiffel", "eiffel", "   "],
        )
        self.assertIn(r.status_code, (200, 201), r.content)
        etape = GameStep.objects.get(id=r.json()["id"])
        # Espaces rognés, entrées vides retirées, doublon insensible à la
        # casse écarté.
        self.assertEqual(etape.answer_text_alt, ["tour Eiffel", "Eiffel"])

    def test_une_enigme_cesar_ne_garde_aucune_alternative(self):
        r = self._creer_etape(
            answer_type=GameStep.ANSWER_CAESAR, answer_text="Les étoiles",
            answer_text_alt=["la lune"],
        )
        self.assertIn(r.status_code, (200, 201), r.content)
        self.assertEqual(GameStep.objects.get(id=r.json()["id"]).answer_text_alt, [])

    def test_un_qcm_ne_garde_aucune_alternative(self):
        r = self._creer_etape(
            answer_type=GameStep.ANSWER_MCQ, answer_text="",
            options=["Paris", "Lyon"], correct_index=0,
            answer_text_alt=["Paris"],
        )
        self.assertIn(r.status_code, (200, 201), r.content)
        self.assertEqual(GameStep.objects.get(id=r.json()["id"]).answer_text_alt, [])

    def test_changer_de_type_vide_la_liste(self):
        r = self._creer_etape(answer_text_alt=["tour Eiffel"])
        step_id = r.json()["id"]
        r2 = self.client.patch(
            f"/api/creator/escapes/{self.escape.id}/steps/{step_id}",
            {"answer_type": GameStep.ANSWER_MCQ, "options": ["A", "B"], "correct_index": 1},
            format="json",
        )
        self.assertEqual(r2.status_code, 200, r2.content)
        self.assertEqual(GameStep.objects.get(id=step_id).answer_text_alt, [])

    def test_un_client_qui_ignore_le_champ_ne_l_efface_pas(self):
        """Compatibilite avec les versions deja publiees de l'app mobile.

        La 0.3.30 ne connait pas ce champ et ne l'envoie donc pas. Un
        createur qui retouche une etape depuis son telephone ne doit pas
        effacer les reponses qu'il a saisies depuis le web."""
        r = self._creer_etape(answer_text_alt=["tour Eiffel", "Eiffel"])
        step_id = r.json()["id"]

        # Une mise a jour qui ne mentionne pas le champ, comme le fait un
        # client plus ancien.
        r2 = self.client.patch(
            f"/api/creator/escapes/{self.escape.id}/steps/{step_id}",
            {"title": "Titre retouche depuis le mobile"},
            format="json",
        )
        self.assertEqual(r2.status_code, 200, r2.content)

        etape = GameStep.objects.get(id=step_id)
        self.assertEqual(etape.title, "Titre retouche depuis le mobile")
        self.assertEqual(
            etape.answer_text_alt, ["tour Eiffel", "Eiffel"],
            "les reponses acceptees ne doivent pas disparaitre",
        )

    def test_une_liste_vide_explicite_efface_bien(self):
        """A l'inverse, un client a jour qui envoie une liste vide veut
        vraiment effacer : il ne faut pas confondre « absent » et « vide »."""
        r = self._creer_etape(answer_text_alt=["tour Eiffel"])
        step_id = r.json()["id"]
        r2 = self.client.patch(
            f"/api/creator/escapes/{self.escape.id}/steps/{step_id}",
            {"answer_text_alt": []}, format="json",
        )
        self.assertEqual(r2.status_code, 200, r2.content)
        self.assertEqual(GameStep.objects.get(id=step_id).answer_text_alt, [])

    def test_une_liste_trop_longue_est_refusee(self):
        r = self._creer_etape(answer_text_alt=[f"variante {i}" for i in range(21)])
        self.assertEqual(r.status_code, 400, r.content)
        self.assertIn("answer_text_alt", r.json())

    def test_une_reponse_trop_longue_est_refusee(self):
        r = self._creer_etape(answer_text_alt=["x" * 256])
        self.assertEqual(r.status_code, 400, r.content)
        self.assertIn("answer_text_alt", r.json())

    def test_une_valeur_qui_n_est_pas_une_liste_est_refusee(self):
        r = self._creer_etape(answer_text_alt="tour Eiffel")
        self.assertEqual(r.status_code, 400, r.content)
