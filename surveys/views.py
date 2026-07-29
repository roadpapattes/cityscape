import json
import logging
import os

from django.conf import settings
from django.core.mail import send_mail
from django.http import HttpResponse, JsonResponse
from django.utils.decorators import method_decorator
from django.views.decorators.csrf import csrf_exempt

from django_ratelimit.decorators import ratelimit

from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import SurveyResponse
from .schema import load_schema, validate_submission, SurveyValidationError, get_survey

log = logging.getLogger(__name__)

# Champs de contexte (métadonnées) acceptés au niveau racine du payload.
# Clé JSON envoyée par le front -> nom de colonne du modèle.
META_FIELDS = {
    "session": "session",
    "escape": "escape",
    "submitted_at": "submitted_at",
    "form_version": "form_version",
    "duree": "duree",
    "indices": "indices",
    "version": "app_version",   # le param d'URL s'appelle `version` (version de l'app)
    "os": "os",
    "lang": "lang",
    "etape_abandon": "etape_abandon",
}


@method_decorator(csrf_exempt, name="dispatch")
class SurveySubmitView(APIView):
    """POST /api/survey — collecte publique d'une soumission de questionnaire."""

    authentication_classes = []          # endpoint public, pas d'auth
    permission_classes = [permissions.AllowAny]

    # block=False : on ne laisse PAS django-ratelimit lever un 403 (défaut en
    # v4). On récupère request.limited pour renvoyer nous-mêmes un 429 propre.
    @method_decorator(ratelimit(key="ip", rate="20/h", method="POST", block=False))
    def post(self, request):
        # django_ratelimit pose request.limited ; on renvoie un 429 explicite.
        if getattr(request, "limited", False):
            return Response(
                {"detail": "Trop de soumissions. Réessayez plus tard."},
                status=status.HTTP_429_TOO_MANY_REQUESTS,
            )

        data = request.data if isinstance(request.data, dict) else {}
        survey_key = data.get("survey")

        # Validation des réponses contre le schéma (renvoie les réponses nettoyées)
        try:
            cleaned = validate_submission(survey_key, data.get("reponses", {}))
        except SurveyValidationError as e:
            return Response({"detail": str(e)}, status=status.HTTP_400_BAD_REQUEST)

        # Métadonnées
        fields = {}
        for json_key, col in META_FIELDS.items():
            val = data.get(json_key)
            if val is not None:
                fields[col] = val
        # L'escape stocké/dé-doublonné = la réponse (obligatoire en parcours),
        # à défaut le param d'URL. Vide pour le questionnaire application.
        fields["escape"] = (cleaned.get("escape") or fields.get("escape") or "")
        fields["survey"] = survey_key
        fields["reponses"] = cleaned

        session = (fields.get("session") or "").strip()

        # Anti-doublon idempotent quand une session est fournie
        if session:
            obj, created = SurveyResponse.objects.update_or_create(
                session=session, survey=survey_key, escape=fields["escape"],
                defaults=fields,
            )
        else:
            obj, created = SurveyResponse.objects.create(**fields), True

        # Alerte maintenance (prioritaire, ciblée) sinon notification générique.
        # On ne cumule pas les deux e-mails pour un même avis.
        alerted = self._maybe_alert(obj)
        if created and not alerted:
            self._notify_new_response(obj)

        return Response(
            {"ok": True, "id": obj.id, "created": created},
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )

    def _from_email(self):
        # Gmail SMTP : l'expéditeur doit être le compte authentifié.
        return (getattr(settings, "EMAIL_HOST_USER", "")
                or getattr(settings, "DEFAULT_FROM_EMAIL", "noreply@localhost"))

    def _recipients(self, setting_name, default):
        raw = getattr(settings, setting_name, None) or default
        return [a.strip() for a in str(raw).split(",") if a.strip()]

    def _maybe_alert(self, obj):
        """Alerte de maintenance (brief 4.4) : un élément de terrain signalé
        disparu/inaccessible peut rendre un parcours injouable → notif immédiate.

        Renvoie True si la condition d'alerte est remplie (→ on n'envoie pas en
        plus la notification générique pour ce même avis)."""
        if obj.survey != SurveyResponse.PARCOURS:
            return False
        r = obj.reponses or {}
        if r.get("visible") in (1, 2) and (r.get("visible_quoi") or "").strip():
            to = self._recipients("CREATOR_FEEDBACK_EMAIL", "feedback.enigmapolis@gmail.com")
            body = (
                "⚠️ Élément de terrain signalé disparu ou inaccessible.\n\n"
                f"Parcours : {obj.escape or '(non précisé)'}\n"
                f"Note « éléments encore visibles » : {r.get('visible')}/5\n"
                f"Description : {r.get('visible_quoi')}\n\n"
                f"Session : {obj.session or 'anonyme'}\n"
                f"Reçu le : {obj.received_at.isoformat()}\n"
            )
            try:
                send_mail(
                    subject=f"[CityScape][Maintenance] {obj.escape or 'Parcours'} — élément à vérifier",
                    message=body, from_email=self._from_email(), recipient_list=to,
                    fail_silently=True,   # la donnée est déjà sauvegardée
                )
            except Exception as e:  # pragma: no cover
                log.error("Alerte maintenance non envoyée: %s", e)
            return True
        return False

    def _notify_new_response(self, obj):
        """Notifie par e-mail chaque nouvel avis reçu (suivi en temps réel)."""
        to = self._recipients("SURVEY_NOTIFY_EMAIL", "")
        if not to:
            return
        r = obj.reponses or {}
        is_parcours = obj.survey == SurveyResponse.PARCOURS
        label = "Parcours" if is_parcours else "Application"

        lines = [f"Questionnaire : {label}"]
        if obj.escape:
            lines.append(f"Parcours : {obj.escape}")
        if is_parcours:
            if isinstance(r.get("note"), int):
                lines.append(f"Note : {r['note']}/10")
            if isinstance(r.get("reco_parcours"), int):
                lines.append(f"Recommandation : {r['reco_parcours']}/10")
            if r.get("fini"):
                lines.append(f"Parcours terminé : {r['fini']}")
        else:
            if isinstance(r.get("reco_app"), int):
                lines.append(f"Recommandation app : {r['reco_app']}/10")

        # Nombre de champs libres remplis (là où se trouve l'information exploitable)
        survey_def = get_survey(obj.survey) or {}
        text_ids = {
            q["id"] for s in survey_def.get("sections", [])
            for q in s.get("questions", []) if q.get("type") in ("text", "shorttext")
        }
        comments = [k for k in r if k in text_ids and str(r.get(k) or "").strip()]
        if comments:
            lines.append(f"Commentaires libres renseignés : {len(comments)}")

        lines += [
            "",
            f"Session : {obj.session or 'anonyme'}",
            f"Reçu le : {obj.received_at.isoformat()}",
            "",
            "Détail complet dans l'espace admin, onglet « Surveys ».",
        ]
        subject = f"[CityScape] Nouvel avis — {label}" + (f" · {obj.escape}" if obj.escape else "")
        try:
            send_mail(
                subject=subject, message="\n".join(lines),
                from_email=self._from_email(), recipient_list=to,
                fail_silently=True,   # la donnée est déjà sauvegardée
            )
        except Exception as e:  # pragma: no cover
            log.error("Notification nouvel avis non envoyée: %s", e)


class SurveySchemaView(APIView):
    """GET /api/survey/schema — le schéma (source de vérité) servi tel quel.
    Consommé par la page web et, plus tard, par l'app mobile."""

    authentication_classes = []
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        return JsonResponse(load_schema(), json_dumps_params={"ensure_ascii": False})


def survey_page(request):
    """GET /survey — sert le formulaire HTML en injectant le schéma (source
    unique) et l'endpoint de collecte. Les paramètres d'URL (session, escape,
    duree, …) sont lus côté client, rien à faire ici."""
    html_path = os.path.join(settings.BASE_DIR, "static_html", "survey.html")
    with open(html_path, "r", encoding="utf-8") as f:
        html = f.read()

    schema = load_schema()
    config = dict(schema.get("config", {}))
    config["endpoint"] = "/api/survey"
    inject = (
        "<script>\n"
        f"const CONFIG = {json.dumps(config, ensure_ascii=False)};\n"
        f"const ESCAPES = {json.dumps(schema.get('escapes', []), ensure_ascii=False)};\n"
        f"const SURVEYS = {json.dumps(schema.get('surveys', {}), ensure_ascii=False)};\n"
        "</script>"
    )
    html = html.replace("<!--__CITYSCAPE_SCHEMA__-->", inject)
    return HttpResponse(html, content_type="text/html; charset=utf-8")
