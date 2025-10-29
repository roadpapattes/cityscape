# engagement/apps.py
from django.apps import AppConfig

class EngagementConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "engagement"

    def ready(self):
        # charge les receivers post_save/post_delete
        import engagement.signals  # noqa: F401
