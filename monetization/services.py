from django.conf import settings
from django.db import transaction

from .models import CreatorLedgerEntry, PaywallImpression, Purchase

# Barème provisoire (Phase 4 de la note de cadrage) — non appliqué tant que
# les Purchase restent en payment_provider="free_launch".
CREATOR_SHARE_RATIO = 0.70


class MonetizationNotReady(Exception):
    """Levée si un appel tente un vrai paiement alors que
    settings.MONETIZATION_ENABLED est False (aucune intégration Google Play
    Billing n'existe encore côté serveur)."""


def get_valid_purchase(user, escape):
    return Purchase.objects.filter(
        user=user, escape=escape, status=Purchase.STATUS_VALID,
    ).first()


def has_access(user, escape) -> bool:
    """L'accès est libre pour une escape gratuite ; sinon il faut un
    Purchase valide (simulé ou réel selon le mode)."""
    if not escape.is_paid:
        return True
    if not user or not getattr(user, "is_authenticated", False):
        return False
    return get_valid_purchase(user, escape) is not None


@transaction.atomic
def unlock_escape(user, escape) -> Purchase:
    """Débloque une escape payante pour ce joueur.

    En mode lancement gratuit (MONETIZATION_ENABLED=False), crée
    immédiatement un Purchase à 0 centime — aucun argent réel ne transite
    et aucune CreatorLedgerEntry n'est générée. Idempotent : si un Purchase
    valide existe déjà, on le renvoie tel quel plutôt que d'en recréer un.
    """
    existing = get_valid_purchase(user, escape)
    if existing is not None:
        return existing

    if getattr(settings, "MONETIZATION_ENABLED", False):
        # Phase 3 de la note de cadrage : intégration Google Play Billing
        # réelle (validation du jeton d'achat côté serveur) — pas encore
        # implémentée.
        raise MonetizationNotReady(
            "Les paiements réels ne sont pas encore intégrés côté serveur."
        )

    purchase = Purchase.objects.create(
        user=user,
        escape=escape,
        payment_provider=Purchase.PROVIDER_FREE_LAUNCH,
        amount_cents=0,
        currency=escape.currency or "EUR",
        status=Purchase.STATUS_VALID,
    )
    # Garde-fou : un déblocage simulé ne doit jamais générer de dette envers
    # le créateur, puisqu'aucun argent réel n'a été perçu.
    return purchase


def record_paywall_impression(user, escape) -> PaywallImpression:
    """Enregistre que le joueur a vu l'écran de déblocage pour cette
    escape — signal utilisé pour le taux de conversion (voir
    monetization.funnel.conversion_report)."""
    return PaywallImpression.objects.create(user=user, escape=escape)


def record_creator_share(purchase: Purchase) -> CreatorLedgerEntry | None:
    """Crée la part créateur pour un achat réel. No-op pour un déblocage
    simulé (payment_provider="free_launch")."""
    if purchase.payment_provider != Purchase.PROVIDER_GOOGLE_PLAY:
        return None
    creator = purchase.escape.owner
    if creator is None:
        return None
    share_cents = int(round(purchase.amount_cents * CREATOR_SHARE_RATIO))
    entry, _ = CreatorLedgerEntry.objects.get_or_create(
        purchase=purchase,
        defaults={"creator": creator, "share_cents": share_cents},
    )
    return entry
