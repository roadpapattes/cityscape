from dataclasses import dataclass

from django.db.models import Count

from games.models import EscapeGame

from .models import PaywallImpression, Purchase


@dataclass
class EscapeFunnel:
    escape_id: int
    title: str
    price_cents: int
    impressions: int  # utilisateurs distincts ayant vu le paywall
    unlocks: int       # utilisateurs distincts ayant débloqué (Purchase valide)

    @property
    def conversion_rate(self) -> float:
        """Entre 0 et 1. 0 si aucune impression (pas de signal, pas de division par zéro)."""
        if not self.impressions:
            return 0.0
        return self.unlocks / self.impressions


def conversion_report() -> list[EscapeFunnel]:
    """Taux de conversion du paywall simulé, par escape payante.

    C'est le signal de bascule décrit dans la note de cadrage
    monétisation : préférer ce taux à un simple comptage de joueurs pour
    décider quand créer la structure juridique et activer les paiements
    réels (voir monetization/funnel_report management command).
    """
    impression_counts = dict(
        PaywallImpression.objects.values("escape_id")
        .annotate(n=Count("user_id", distinct=True))
        .values_list("escape_id", "n")
    )
    unlock_counts = dict(
        Purchase.objects.filter(status=Purchase.STATUS_VALID)
        .values("escape_id")
        .annotate(n=Count("user_id", distinct=True))
        .values_list("escape_id", "n")
    )

    escape_ids = set(impression_counts) | set(unlock_counts)
    escapes = {e.id: e for e in EscapeGame.objects.filter(id__in=escape_ids)}

    out = []
    for escape_id in escape_ids:
        escape = escapes.get(escape_id)
        if escape is None:
            continue
        out.append(EscapeFunnel(
            escape_id=escape_id,
            title=escape.title,
            price_cents=escape.price_cents or 0,
            impressions=impression_counts.get(escape_id, 0),
            unlocks=unlock_counts.get(escape_id, 0),
        ))
    out.sort(key=lambda f: f.conversion_rate, reverse=True)
    return out
