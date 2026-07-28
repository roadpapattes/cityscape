"""Endpoints d'administration des questionnaires (consultation dashboard).

Réservés au staff (IsAdminUser). Servent l'onglet « Surveys » de l'interface
creator-web : liste des réponses, indicateurs clés (brief §5), export CSV.
"""
import csv

from django.http import HttpResponse
from rest_framework import status
from rest_framework.permissions import IsAdminUser
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import SurveyResponse
from .schema import get_survey, question_order

SURVEY_KEYS = ("parcours", "application")


def _nps(values):
    """NPS = %promoteurs(9-10) − %détracteurs(0-6). Les 7-8 comptent au total."""
    vals = [v for v in values if isinstance(v, int)]
    if not vals:
        return None
    promoters = sum(1 for v in vals if v >= 9)
    detractors = sum(1 for v in vals if v <= 6)
    return round((promoters - detractors) / len(vals) * 100)


def _rate(values, predicate):
    vals = [v for v in values if v not in (None, "")]
    if not vals:
        return None
    return round(sum(1 for v in vals if predicate(v)) / len(vals) * 100)


def _mean(values):
    vals = [v for v in values if isinstance(v, int)]
    if not vals:
        return None
    return round(sum(vals) / len(vals), 2)


def _valid_key(request):
    key = request.query_params.get("survey", "parcours")
    return key if key in SURVEY_KEYS else None


class AdminSurveyResponsesView(APIView):
    """GET /api/admin/surveys/responses?survey=parcours — réponses brutes."""
    permission_classes = [IsAdminUser]

    def get(self, request):
        key = _valid_key(request)
        if not key:
            return Response({"detail": "survey invalide."}, status=status.HTTP_400_BAD_REQUEST)

        qs = SurveyResponse.objects.filter(survey=key).order_by("-received_at")
        data = [{
            "id": r.id,
            "escape": r.escape,
            "session": r.session,
            "os": r.os,
            "app_version": r.app_version,
            "duree": r.duree,
            "indices": r.indices,
            "received_at": r.received_at.isoformat() if r.received_at else None,
            "reponses": r.reponses or {},
        } for r in qs]
        return Response({"count": len(data), "results": data})


class AdminSurveyStatsView(APIView):
    """GET /api/admin/surveys/stats?survey=parcours — indicateurs clés."""
    permission_classes = [IsAdminUser]

    def get(self, request):
        key = _valid_key(request)
        if not key:
            return Response({"detail": "survey invalide."}, status=status.HTTP_400_BAD_REQUEST)

        rows = list(SurveyResponse.objects.filter(survey=key).values_list("reponses", flat=True))
        col = lambda qid: [(r or {}).get(qid) for r in rows]

        stats = {"total": len(rows)}
        if key == "parcours":
            stats["nps_parcours"] = _nps(col("reco_parcours"))
            stats["taux_completion"] = _rate(col("fini"), lambda v: v == "Oui, entièrement")
            stats["taux_difficulte_ok"] = _rate(col("difficulte"), lambda v: v == "Bien dosée")
            stats["note_moyenne"] = _mean(col("note"))
        else:
            stats["nps_app"] = _nps(col("reco_app"))
            umux = [v for v in (col("umux_besoins") + col("umux_facile")) if isinstance(v, int)]
            stats["umux_lite"] = round(sum(umux) / len(umux), 2) if umux else None
        return Response(stats)


class AdminSurveyExportView(APIView):
    """GET /api/admin/surveys/export?survey=parcours — CSV, une colonne/question."""
    permission_classes = [IsAdminUser]

    def get(self, request):
        key = _valid_key(request)
        if not key:
            return Response({"detail": "survey invalide."}, status=status.HTTP_400_BAD_REQUEST)

        q_cols = question_order(key)
        meta_cols = ["id", "escape", "session", "received_at", "os", "app_version", "duree", "indices"]

        resp = HttpResponse(content_type="text/csv; charset=utf-8")
        resp["Content-Disposition"] = f'attachment; filename="survey_{key}.csv"'
        resp.write("﻿")  # BOM → Excel lit l'UTF-8
        writer = csv.writer(resp)
        writer.writerow(meta_cols + q_cols)
        for r in SurveyResponse.objects.filter(survey=key).order_by("-received_at"):
            rep = r.reponses or {}
            writer.writerow([
                r.id, r.escape, r.session,
                r.received_at.isoformat() if r.received_at else "",
                r.os, r.app_version, r.duree, r.indices,
            ] + [rep.get(qid, "") for qid in q_cols])
        return resp
