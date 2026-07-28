from django.db import models


class SurveyResponse(models.Model):
    """Une soumission de questionnaire.

    Stockage tolérant à l'évolution du schéma : les métadonnées filtrables sont
    en colonnes, les réponses elles-mêmes en JSON (`reponses`). Ajouter une
    question au schéma ne nécessite donc aucune migration.
    """

    PARCOURS = "parcours"
    APPLICATION = "application"
    SURVEY_CHOICES = [
        (PARCOURS, "Parcours"),
        (APPLICATION, "Application"),
    ]

    # --- Métadonnées (colonnes classiques, indexables/filtrables) ---
    survey = models.CharField(max_length=32, choices=SURVEY_CHOICES, db_index=True)
    # Identifiant de session anonyme. Vide si le client n'en fournit pas :
    # dans ce cas l'anti-doublon est désactivé (cf. Meta.constraints).
    session = models.CharField(max_length=128, blank=True, default="", db_index=True)
    escape = models.CharField(max_length=255, blank=True, default="")

    submitted_at = models.DateTimeField(null=True, blank=True)  # horodatage client
    form_version = models.CharField(max_length=32, blank=True, default="")

    # Contexte transmis par l'app (pas déclaratif) — cf. brief §2
    duree = models.CharField(max_length=32, blank=True, default="")
    indices = models.CharField(max_length=32, blank=True, default="")
    app_version = models.CharField(max_length=32, blank=True, default="")
    os = models.CharField(max_length=32, blank=True, default="")
    lang = models.CharField(max_length=16, blank=True, default="")
    etape_abandon = models.CharField(max_length=64, blank=True, default="")

    # --- Réponses (schéma-tolérant) ---
    reponses = models.JSONField(default=dict, blank=True)

    received_at = models.DateTimeField(auto_now_add=True, db_index=True)  # source de vérité serveur
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-received_at"]
        constraints = [
            # Anti-doublon (session, survey, escape) — uniquement quand une
            # session anonyme est fournie. Sans session, chaque envoi est conservé
            # (on ne peut pas distinguer deux testeurs anonymes).
            models.UniqueConstraint(
                fields=["session", "survey", "escape"],
                condition=~models.Q(session=""),
                name="uniq_session_survey_escape",
            ),
        ]

    def __str__(self):
        who = self.session or "anon"
        return f"{self.survey} · {who} · {self.escape or '—'}"
