# engagement/signals.py
from django.db.models.signals import post_save, post_delete
from django.dispatch import receiver
from django.db.models import Avg
from .models import Rating

def _recompute_escape_avg(escape_id: int):
    from games.models import EscapeGame
    agg = Rating.objects.filter(escape_id=escape_id).aggregate(avg=Avg("stars"))
    EscapeGame.objects.filter(pk=escape_id).update(rating=float(agg["avg"] or 0.0))

@receiver(post_save, sender=Rating)
def rating_saved(sender, instance: Rating, **kwargs):
    _recompute_escape_avg(instance.escape_id)

@receiver(post_delete, sender=Rating)
def rating_deleted(sender, instance: Rating, **kwargs):
    _recompute_escape_avg(instance.escape_id)
