from django.conf import settings
from django.db import models

User = settings.AUTH_USER_MODEL

class PlaySession(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="play_sessions")
    escape = models.ForeignKey(
        'games.EscapeGame',
        on_delete=models.CASCADE,
        related_name="sessions",
    )
    started_at = models.DateTimeField(auto_now_add=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    current_step_index = models.PositiveIntegerField(default=0)
    hints_used = models.JSONField(default=dict, blank=True)
    # NOUVEAU : malus cumulé (mauvaises réponses + indices)
    penalty = models.IntegerField(default=0)  # augmente de 5 par mauvaise réponse + hint_penalty quand indice demandé
    answers = models.JSONField(default=dict, blank=True)

    class Meta:
        unique_together = ('user', 'escape')

    def __str__(self):
        return f"Session({self.user}, {self.escape}, completed={self.completed_at is not None})"


class EscapeCompletion(models.Model):
    escape = models.OneToOneField('games.EscapeGame', on_delete=models.CASCADE, related_name='completion')
    code = models.CharField(max_length=24, default="0000")

    def __str__(self):
        return f"CompletionCode({self.escape_id}, {self.code})"


class Rating(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    # >>> change ici : related_name='ratings' + référence string au modèle cible
    escape = models.ForeignKey('games.EscapeGame', on_delete=models.CASCADE, related_name='ratings')

    stars = models.PositiveSmallIntegerField()
    comment = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["user","escape"], name="uniq_user_escape_rating"),
        ]

    def __str__(self):
        return f"{self.user} → {self.escape} ({self.stars})"
