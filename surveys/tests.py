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
