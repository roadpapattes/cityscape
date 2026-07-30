import csv

from django.contrib import admin
from django.http import HttpResponse
from django.utils import timezone
from django.utils.html import escape as esc

from .models import SurveyResponse
from .schema import question_order, get_survey, hidden_qids


# Feuille imprimable : un avis par page A4. Ouverte dans le navigateur puis
# « Enregistrer en PDF ». CSS pensé pour tenir sur une seule page.
_PRINT_DOC = """<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8">
<title>Avis CityScape</title>
<style>
@page {{ size: A4 portrait; margin: 10mm; }}
* {{ box-sizing: border-box; }}
body {{ margin:0; color:#17201C; font-size:10px; line-height:1.26;
  font-family:-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif; }}
.toolbar {{ background:#1D5C4E; color:#fff; padding:10px 14px; display:flex; gap:14px; align-items:center; }}
.toolbar button {{ font-size:13px; padding:6px 16px; border:0; border-radius:3px; cursor:pointer;
  background:#A87C1F; color:#fff; }}
@media print {{ .toolbar {{ display:none; }} }}
.sheet {{ padding:2mm 0 1mm; page-break-after:always; }}
.sheet:last-child {{ page-break-after:auto; }}
.head {{ border-bottom:2px solid #1D5C4E; padding-bottom:5px; margin-bottom:6px; }}
.ttl {{ font-size:15px; font-weight:700; color:#1D5C4E; text-transform:uppercase; }}
.meta {{ font-size:9.5px; color:#555; margin-top:2px; font-family:"Roboto Mono",monospace; }}
.sec {{ margin-top:6px; break-inside:avoid; }}
.sec-t {{ font-size:9px; letter-spacing:.08em; text-transform:uppercase; color:#A87C1F;
  border-bottom:1px solid #ddd; padding-bottom:1px; margin-bottom:3px; }}
.grid {{ display:grid; grid-template-columns:1fr 1fr; gap:2px 18px; }}
.qa {{ break-inside:avoid; }}
.qa.long {{ grid-column:1 / -1; }}
.ql {{ color:#666; }}
.qv {{ font-weight:600; white-space:pre-wrap; }}
.empty {{ padding:40px; color:#888; }}
</style></head><body>
<div class="toolbar">
  <button onclick="window.print()">Imprimer / Enregistrer en PDF</button>
  <span>Un avis par page — utilisez « Enregistrer au format PDF » comme imprimante.</span>
</div>
{sheets}
<script>window.addEventListener("load",function(){{setTimeout(function(){{window.print();}},350);}});</script>
</body></html>"""


@admin.register(SurveyResponse)
class SurveyResponseAdmin(admin.ModelAdmin):
    list_display = ("id", "survey", "escape", "note_display", "session", "received_at")
    list_filter = ("survey", "received_at", "os")
    search_fields = ("session", "escape", "reponses")
    readonly_fields = ("received_at", "updated_at")
    date_hierarchy = "received_at"
    actions = ("print_selected", "export_csv")

    @admin.display(description="Note")
    def note_display(self, obj):
        r = obj.reponses or {}
        return r.get("note", r.get("reco_app", "—"))

    @admin.action(description="Imprimer (PDF) — un avis par page")
    def print_selected(self, request, queryset):
        # Page imprimable, un avis par feuille, prête pour « Enregistrer en PDF ».
        sheets = "".join(self._sheet(obj) for obj in queryset.order_by("received_at"))
        if not sheets:
            sheets = '<p class="empty">Aucun avis sélectionné.</p>'
        return HttpResponse(_PRINT_DOC.format(sheets=sheets))

    def _sheet(self, obj):
        survey = get_survey(obj.survey) or {}
        hidden = hidden_qids(obj.survey)
        rep = obj.reponses or {}
        label = dict(SurveyResponse.SURVEY_CHOICES).get(obj.survey, obj.survey)

        bits = []
        if obj.received_at:
            bits.append("Reçu le " + timezone.localtime(obj.received_at).strftime("%d/%m/%Y à %H:%M"))
        if obj.session:
            bits.append("Session " + obj.session)
        if obj.os:
            bits.append(obj.os)
        if obj.app_version:
            bits.append("v" + obj.app_version)
        if obj.duree:
            bits.append(obj.duree + " min")
        if obj.indices:
            bits.append(obj.indices + " indice(s)")

        sections = ""
        for sec in survey.get("sections", []):
            if sec.get("hidden"):
                continue
            items = ""
            for q in sec.get("questions", []):
                if q.get("hidden") or q["id"] in hidden:
                    continue
                v = rep.get(q["id"])
                if v is None or v == "":
                    continue
                long = q["type"] in ("text", "shorttext")
                items += (
                    f'<div class="qa{" long" if long else ""}">'
                    f'<div class="ql">{esc(q["label"])}</div>'
                    f'<div class="qv">{esc(self._fmt(q, v))}</div></div>'
                )
            if items:
                sections += (
                    f'<div class="sec"><div class="sec-t">{esc(sec.get("title", ""))}</div>'
                    f'<div class="grid">{items}</div></div>'
                )

        title = esc(label) + (f" — {esc(obj.escape)}" if obj.escape else "")
        return (
            f'<article class="sheet"><div class="head"><div class="ttl">{title}</div>'
            f'<div class="meta">{esc(" · ".join(bits))}</div></div>{sections}</article>'
        )

    @staticmethod
    def _fmt(q, v):
        if q["type"] == "likert":
            return f"{v} / 5"
        if q["type"] == "nps":
            return f"{v} / 10"
        return str(v)

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
