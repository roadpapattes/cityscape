from django.conf import settings
from django.db import models

User = settings.AUTH_USER_MODEL

# NOTE: Adjust this import if your escapes app isn't named "games".
from games.models import EscapeGame

class PlaySession(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="play_sessions")
    escape = models.ForeignKey(EscapeGame, on_delete=models.CASCADE, related_name="sessions")
    started_at = models.DateTimeField(auto_now_add=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        unique_together = ('user', 'escape')

    def __str__(self):
        return f"Session({self.user}, {self.escape}, completed={self.completed_at is not None})"


class EscapeCompletion(models.Model):
    escape = models.OneToOneField(EscapeGame, on_delete=models.CASCADE, related_name="completion")
    code = models.CharField(max_length=24, default="0000")

    def __str__(self):
        return f"CompletionCode({self.escape_id}, {self.code})"


class Rating(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="ratings")
    escape = models.ForeignKey(EscapeGame, on_delete=models.CASCADE, related_name="ratings")
    stars = models.PositiveSmallIntegerField()  # 1..5
    comment = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('user', 'escape')
        ordering = ('-created_at',)

    def __str__(self):
        return f"Rating({self.escape_id}, {self.user_id}, {self.stars})"
