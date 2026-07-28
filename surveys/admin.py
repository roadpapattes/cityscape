import csv

from django.contrib import admin
from django.http import HttpResponse

from .models import SurveyResponse
from .schema import question_order


@admin.register(SurveyResponse)
class SurveyResponseAdmin(admin.ModelAdmin):
    list_display = ("id", "survey", "escape", "note_display", "session", "received_at")
    list_filter = ("survey", "received_at", "os")
    search_fields = ("session", "escape", "reponses")
    readonly_fields = ("received_at", "updated_at")
    date_hierarchy = "received_at"
    actions = ("export_csv",)

    @admin.display(description="Note")
    def note_display(self, obj):
        r = obj.reponses or {}
        return r.get("note", r.get("reco_app", "—"))

    @admin.action(description="Exporter la sélection en CSV")
    def export_csv(self, request, queryset):
        # Une colonne par question. Si la sélection couvre plusieurs
        # questionnaires, on concatène les colonnes de chacun (dans l'ordre du schéma).
        surveys = list(dict.fromkeys(queryset.values_list("survey", flat=True)))
        q_cols = []
        for key in surveys:
            for qid in question_order(key):
                if qid not in q_cols:
                    q_cols.append(qid)

        meta_cols = [
            "id", "survey", "escape", "session", "submitted_at", "received_at",
            "form_version", "duree", "indices", "app_version", "os", "lang", "etape_abandon",
        ]

        resp = HttpResponse(content_type="text/csv; charset=utf-8")
        resp["Content-Disposition"] = 'attachment; filename="survey_responses.csv"'
        resp.write("﻿")  # BOM → Excel ouvre l'UTF-8 correctement
        writer = csv.writer(resp)
        writer.writerow(meta_cols + q_cols)

        for obj in queryset:
            row = [
                obj.id, obj.survey, obj.escape, obj.session,
                obj.submitted_at.isoformat() if obj.submitted_at else "",
                obj.received_at.isoformat() if obj.received_at else "",
                obj.form_version, obj.duree, obj.indices, obj.app_version,
                obj.os, obj.lang, obj.etape_abandon,
            ]
            r = obj.reponses or {}
            row += [r.get(qid, "") for qid in q_cols]
            writer.writerow(row)

        return resp
