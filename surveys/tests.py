import json

from django.test import TestCase, override_settings
from django.core import mail
from django.core.cache import cache

from .models import SurveyResponse
from .schema import validate_submission, SurveyValidationError, get_survey

LOCMEM = {"default": {"BACKEND": "django.core.cache.backends.locmem.LocMemCache"}}


class SchemaValidationTests(TestCase):
    def test_unknown_survey_rejected(self):
        with self.assertRaises(SurveyValidationError):
            validate_submission("inconnu", {})

    def test_unknown_qid_rejected(self):
        with self.assertRaises(SurveyValidationError):
            validate_submission("parcours", {"pas_une_question": 3})

    def test_likert_out_of_range_rejected(self):
        with self.assertRaises(SurveyValidationError):
            validate_submission("parcours", {"bon_moment": 9})

    def test_nps_out_of_range_rejected(self):
        with self.assertRaises(SurveyValidationError):
            validate_submission("parcours", {"note": 11})

    def test_single_bad_option_rejected(self):
        with self.assertRaises(SurveyValidationError):
            validate_submission("parcours", {"meteo": "Neige"})

    def test_bool_not_accepted_as_likert(self):
        with self.assertRaises(SurveyValidationError):
            validate_submission("parcours", {"bon_moment": True})

    def test_hidden_answer_is_dropped(self):
        # bloque_quoi n'est visible que si bloque == "Oui"
        cleaned = validate_submission("parcours", {
            "escape": "Parc du Poutyl (Olivet)", "fini": "Oui, entièrement",
            "note": 8, "reco_parcours": 9, "difficulte": "Bien dosée",
            "bloque": "Non", "bloque_quoi": "ne devrait pas rester",
        })
        self.assertNotIn("bloque_quoi", cleaned)

    def test_required_missing_rejected(self):
        with self.assertRaises(SurveyValidationError):
            validate_submission("parcours", {"fini": "Oui, entièrement"})  # manque escape/note/...

    def test_indices_moved_to_parcours(self):
        # « Les indices » est désormais rattaché au questionnaire parcours.
        cleaned = validate_submission("parcours", {
            "escape": "Parc du Poutyl (Olivet)", "fini": "Oui, entièrement",
            "note": 8, "reco_parcours": 9, "difficulte": "Bien dosée",
            "indice_facile": 4,
        })
        self.assertEqual(cleaned["indice_facile"], 4)

    def test_indices_no_longer_in_application(self):
        # …et n'appartient plus au questionnaire application (q.id inconnu → 400).
        with self.assertRaises(SurveyValidationError):
            validate_submission("application", {"reco_app": 8, "indice_facile": 4})

    def test_hidden_question_accepted_but_not_required(self):
        # `appareil` est masqué : accepté s'il est envoyé, mais son absence ne
        # bloque pas un envoi application par ailleurs valide.
        cleaned = validate_submission("application", {
            "nb_parcours": "1", "reco_app": 8,
        })
        self.assertNotIn("appareil", cleaned)

    def test_escape_options_resolved_from_schema(self):
        q = next(x for s in get_survey("parcours")["sections"] for x in s["questions"] if x["id"] == "escape")
        self.assertIn("Parc du Poutyl (Olivet)", q["options"])


def _valid_parcours(**over):
    payload = {
        "survey": "parcours",
        "session": "web-abc123",
        "form_version": "1.0.0",
        "version": "1.4.0", "os": "Android", "duree": "62", "indices": "4",
        "reponses": {
            "escape": "Le Testament du Dernier Maître (Paris)",
            "fini": "Oui, entièrement",
            "note": 8, "reco_parcours": 9, "difficulte": "Bien dosée",
        },
    }
    payload.update(over)
    return payload


@override_settings(CACHES=LOCMEM)
class SubmitEndpointTests(TestCase):
    def setUp(self):
        cache.clear()  # évite que le compteur de rate-limit ne fuite entre tests

    def post(self, payload):
        return self.client.post("/api/survey", data=json.dumps(payload),
                                content_type="application/json")

    def test_valid_submission_created(self):
        r = self.post(_valid_parcours())
        self.assertEqual(r.status_code, 201)
        self.assertEqual(SurveyResponse.objects.count(), 1)
        obj = SurveyResponse.objects.get()
        self.assertEqual(obj.app_version, "1.4.0")   # `version` -> app_version
        self.assertEqual(obj.escape, "Le Testament du Dernier Maître (Paris)")

    def test_invalid_returns_400(self):
        bad = _valid_parcours()
        bad["reponses"]["note"] = 99
        r = self.post(bad)
        self.assertEqual(r.status_code, 400)
        self.assertEqual(SurveyResponse.objects.count(), 0)

    def test_idempotent_on_reload(self):
        self.post(_valid_parcours())
        r2 = self.post(_valid_parcours(duree="70"))  # même (session, survey, escape)
        self.assertEqual(r2.status_code, 200)          # pas 201
        self.assertEqual(SurveyResponse.objects.count(), 1)
        self.assertEqual(SurveyResponse.objects.get().duree, "70")  # mis à jour

    def test_two_escapes_same_session_are_distinct(self):
        self.post(_valid_parcours())
        self.post(_valid_parcours(reponses={
            "escape": "Parc du Poutyl (Olivet)", "fini": "Oui, entièrement",
            "note": 7, "reco_parcours": 8, "difficulte": "Bien dosée",
        }))
        self.assertEqual(SurveyResponse.objects.count(), 2)

    def test_maintenance_alert_sent(self):
        p = _valid_parcours()
        p["reponses"].update({"visible": 2, "visible_quoi": "La plaque a été retirée"})
        r = self.post(p)
        self.assertEqual(r.status_code, 201)
        self.assertEqual(len(mail.outbox), 1)
        self.assertIn("Maintenance", mail.outbox[0].subject)

    def test_no_alert_when_visible_ok(self):
        p = _valid_parcours()
        p["reponses"].update({"visible": 5})
        self.post(p)
        self.assertEqual(len(mail.outbox), 0)

    def test_anonymous_without_session_not_deduped(self):
        self.post(_valid_parcours(session=""))
        self.post(_valid_parcours(session=""))
        self.assertEqual(SurveyResponse.objects.count(), 2)

    def test_rate_limit_trips(self):
        last = None
        for _ in range(22):  # limite = 20/h
            last = self.post(_valid_parcours(session=""))
        self.assertEqual(last.status_code, 429)


@override_settings(CACHES=LOCMEM)
class AdminConsultationTests(TestCase):
    def setUp(self):
        cache.clear()
        from django.contrib.auth import get_user_model
        from rest_framework.authtoken.models import Token
        User = get_user_model()
        self.admin = User.objects.create_user("boss", password="x", is_staff=True)
        self.token = Token.objects.create(user=self.admin)
        # jeu de données : 2 promoteurs, 1 détracteur sur reco_parcours
        for reco, fini, diff in [(10, "Oui, entièrement", "Bien dosée"),
                                 (9, "Oui, entièrement", "Un peu trop difficile"),
                                 (3, "Non, abandon en cours", "Bien dosée")]:
            SurveyResponse.objects.create(
                survey="parcours", session=f"s{reco}",
                escape="Parc du Poutyl (Olivet)",
                reponses={"reco_parcours": reco, "fini": fini, "difficulte": diff,
                          "note": 8, "plu": "les énigmes"},
            )

    def auth(self):
        return {"HTTP_AUTHORIZATION": f"Token {self.token.key}"}

    def test_responses_requires_staff(self):
        r = self.client.get("/api/admin/surveys/responses?survey=parcours")
        self.assertIn(r.status_code, (401, 403))

    def test_responses_listed_for_staff(self):
        r = self.client.get("/api/admin/surveys/responses?survey=parcours", **self.auth())
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()["count"], 3)

    def test_stats_nps_and_rates(self):
        r = self.client.get("/api/admin/surveys/stats?survey=parcours", **self.auth())
        body = r.json()
        self.assertEqual(body["total"], 3)
        self.assertEqual(body["nps_parcours"], 33)          # (2 prom - 1 detr)/3 = 33%
        self.assertEqual(body["taux_completion"], 67)       # 2/3
        self.assertEqual(body["taux_difficulte_ok"], 67)    # 2/3

    def test_export_csv(self):
        r = self.client.get("/api/admin/surveys/export?survey=parcours", **self.auth())
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r["Content-Type"].startswith("text/csv"))
        content = r.content.decode("utf-8-sig")
        self.assertIn("reco_parcours", content.splitlines()[0])
        self.assertIn("les énigmes", content)

    def test_bad_survey_key_400(self):
        r = self.client.get("/api/admin/surveys/stats?survey=nope", **self.auth())
        self.assertEqual(r.status_code, 400)


@override_settings(CACHES=LOCMEM)
class PageAndSchemaTests(TestCase):
    def test_schema_route(self):
        r = self.client.get("/api/survey/schema")
        self.assertEqual(r.status_code, 200)
        body = r.json()
        self.assertIn("parcours", body["surveys"])
        self.assertIn("application", body["surveys"])

    def test_survey_page_injects_schema(self):
        r = self.client.get("/survey")
        self.assertEqual(r.status_code, 200)
        html = r.content.decode("utf-8")
        self.assertIn("const SURVEYS =", html)
        self.assertIn('"endpoint": "/api/survey"', html)
        self.assertNotIn("__CITYSCAPE_SCHEMA__", html)  # placeholder remplacé

    def test_csv_export(self):
        SurveyResponse.objects.create(
            survey="parcours", session="s1",
            escape="Parc du Poutyl (Olivet)",
            reponses={"note": 8, "difficulte": "Bien dosée"},
        )
        from django.contrib.admin.sites import site
        from .models import SurveyResponse as SR
        admin_obj = site._registry[SR]
        resp = admin_obj.export_csv(None, SR.objects.all())
        content = resp.content.decode("utf-8-sig")
        self.assertIn("note", content.splitlines()[0])   # colonne question
        self.assertIn("Bien dosée", content)
