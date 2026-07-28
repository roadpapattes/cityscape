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
from .schema import load_schema, validate_submission, SurveyValidationError

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

        self._maybe_alert(obj)

        return Response(
            {"ok": True, "id": obj.id, "created": created},
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )

    def _maybe_alert(self, obj):
        """Alerte de maintenance (brief 4.4) : un élément de terrain signalé
        disparu/inaccessible peut rendre un parcours injouable → notif immédiate."""
        if obj.survey != SurveyResponse.PARCOURS:
            return
        r = obj.reponses or {}
        if r.get("visible") in (1, 2) and (r.get("visible_quoi") or "").strip():
            to = getattr(settings, "CREATOR_FEEDBACK_EMAIL", None) or "feedback.enigmapolis@gmail.com"
            from_email = getattr(settings, "DEFAULT_FROM_EMAIL", "noreply@localhost")
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
                    message=body, from_email=from_email, recipient_list=[to],
                    fail_silently=True,   # la donnée est déjà sauvegardée
                )
            except Exception as e:  # pragma: no cover
                log.error("Alerte maintenance non envoyée: %s", e)


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
