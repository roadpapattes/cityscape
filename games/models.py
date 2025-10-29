from django.db import models
from django.conf import settings


class EscapeGame(models.Model):
    title = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    city = models.CharField(max_length=100, blank=True)
    image_url = models.URLField(blank=True, null=True)
    latitude = models.FloatField()
    longitude = models.FloatField()
    rating = models.FloatField(default=0)
    
    # Privé / public
    is_private = models.BooleanField(default=False)
    allowed_users = models.ManyToManyField(
        settings.AUTH_USER_MODEL,
        blank=True,
        related_name="allowed_private_escapes",
        help_text="Utilisateurs autorisés à voir un escape privé."
    )

    # Pénalités
    penalize_wrong_answers = models.BooleanField(default=False)
    wrong_answer_penalty = models.IntegerField(default=5)  # minutes

    victory_message = models.TextField(blank=True, default="")
    reject_reason = models.TextField(blank=True, default="")

    duration_minutes = models.PositiveIntegerField(
        default=60,
        verbose_name="estimated duration (min)",
        help_text="Durée totale estimée pour terminer l'escape (en minutes)."
    )

    difficulty = models.IntegerField(default=1)  # 1..3
    created_at = models.DateTimeField(auto_now_add=True)

    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name='created_escapes'
    )

    STATUS_CHOICES = (
        ('draft', 'draft'),
        ('submitted', 'submitted'),
        ('pending', 'pending'),
        ('rejected', 'rejected'),
        ('published', 'published'),
    )
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='draft')

    # (legacy, optionnel)
    end_code = models.CharField(max_length=32, blank=True, null=True, default=None)

    def __str__(self):
        return f"{self.title} ({self.city})"


class GameStep(models.Model):
    ANSWER_TEXT  = "text"
    ANSWER_MCQ   = "mcq"
    ANSWER_NUM   = "numeric"
    ANSWER_MATCH = "matching"
    ANSWER_NARR  = "narration"

    ANSWER_CHOICES = (
        (ANSWER_TEXT,  "Texte libre"),
        (ANSWER_MCQ,   "Choix multiple"),
        (ANSWER_NUM,   "Numeric"),
        (ANSWER_MATCH, "Association"),
        (ANSWER_NARR,  "Narration"),
    )

    escape = models.ForeignKey(
        EscapeGame,
        related_name="creator_steps",  # ⚠️ utilisé côté créateur
        on_delete=models.CASCADE,
    )
    order = models.PositiveIntegerField(default=1)

    title = models.CharField(max_length=200)
    text = models.TextField(blank=True)

    latitude = models.FloatField(blank=True, null=True)
    longitude = models.FloatField(blank=True, null=True)

    image_url = models.URLField(blank=True, null=True)

    answer_type = models.CharField(max_length=10, choices=ANSWER_CHOICES, default=ANSWER_TEXT)

    # --- Texte libre
    answer_text = models.CharField(max_length=255, blank=True)

    # --- QCM
    options = models.JSONField(default=list, blank=True)         # liste de strings
    correct_index = models.PositiveIntegerField(blank=True, null=True)

    # --- Indices
    hint = models.TextField(blank=True)
    hint_penalty = models.IntegerField(default=0)
    hints = models.JSONField(default=list, blank=True)

    # --- Numérique (non utilisé par l’endpoint gameplay qui lit answer_text)
    expected_number  = models.FloatField(null=True, blank=True, help_text="(Optionnel) Non utilisé par le moteur actuel.")
    number_tolerance = models.FloatField(null=True, blank=True, default=0, help_text="(Optionnel) Non utilisé par le moteur actuel.")

    # --- Association (matching)
    # match_left / match_right : listes de libellés
    # match_pairs : liste de paires d'indices [[li,ri], ...]
    match_left  = models.JSONField(default=list, blank=True)
    match_right = models.JSONField(default=list, blank=True)
    match_pairs = models.JSONField(default=list, blank=True)

    # --- Fin d’escape
    is_final = models.BooleanField(
        default=False,
        help_text="Si activé, une bonne réponse à cette étape termine l'escape."
    )
    final_message = models.TextField(
        blank=True,
        help_text="Message montré quand le joueur termine l'escape via cette étape."
    )

    class Meta:
        ordering = ["order"]
        constraints = [
            models.UniqueConstraint(
                fields=["escape", "order"],
                name="uniq_step_order_per_escape"
            )
        ]

    def __str__(self):
        return f"[{self.order}] {self.title}"


# (Legacy) si encore consommé quelque part
class EscapeStep(models.Model):
    escape = models.ForeignKey('games.EscapeGame', on_delete=models.CASCADE, related_name='steps')
    order = models.PositiveIntegerField(default=1)
    title = models.CharField(max_length=200, blank=True)
    prompt = models.TextField(blank=True)
    answer = models.CharField(max_length=200, blank=True)
    latitude = models.FloatField()
    longitude = models.FloatField()
    radius_m = models.PositiveIntegerField(default=50)

    class Meta:
        ordering = ['order']

    def __str__(self):
        return self.title
