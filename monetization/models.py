from django.conf import settings
from django.db import models

from games.models import EscapeGame


class Purchase(models.Model):
    """Déblocage d'une escape payante par un joueur.

    Tant que settings.MONETIZATION_ENABLED est False, tous les déblocages
    passent par payment_provider="free_launch" (0 centime, aucun argent
    réel) — voir la note de cadrage monétisation pour le détail du
    lancement gratuit instrumenté.
    """

    PROVIDER_FREE_LAUNCH = "free_launch"
    PROVIDER_GOOGLE_PLAY = "google_play"
    PROVIDER_CHOICES = (
        (PROVIDER_FREE_LAUNCH, "Lancement gratuit (simulé)"),
        (PROVIDER_GOOGLE_PLAY, "Google Play Billing"),
    )

    STATUS_VALID = "valid"
    STATUS_REFUNDED = "refunded"
    STATUS_CHOICES = (
        (STATUS_VALID, "Valide"),
        (STATUS_REFUNDED, "Remboursée"),
    )

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="purchases",
    )
    escape = models.ForeignKey(
        EscapeGame, on_delete=models.CASCADE, related_name="purchases",
    )
    payment_provider = models.CharField(max_length=16, choices=PROVIDER_CHOICES)
    google_play_purchase_token = models.CharField(max_length=255, blank=True, default="")
    amount_cents = models.PositiveIntegerField(default=0)
    currency = models.CharField(max_length=3, default="EUR")
    status = models.CharField(max_length=16, choices=STATUS_CHOICES, default=STATUS_VALID)
    purchased_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            models.Index(fields=["user", "escape"]),
        ]

    def __str__(self):
        return f"{self.user_id} -> {self.escape_id} ({self.payment_provider}, {self.status})"


class CreatorLedgerEntry(models.Model):
    """Part revenant au créateur pour un achat réel.

    Ne doit jamais être créée pour un Purchase en payment_provider
    "free_launch" (aucun argent réel n'a transité) — voir
    monetization.services.record_creator_share.
    """

    STATUS_PENDING = "pending"
    STATUS_PAID = "paid"
    STATUS_CHOICES = (
        (STATUS_PENDING, "En attente de reversement"),
        (STATUS_PAID, "Reversée"),
    )

    creator = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="ledger_entries",
    )
    purchase = models.OneToOneField(
        Purchase, on_delete=models.CASCADE, related_name="ledger_entry",
    )
    share_cents = models.PositiveIntegerField(default=0)
    status = models.CharField(max_length=16, choices=STATUS_CHOICES, default=STATUS_PENDING)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.creator_id} <- {self.purchase_id} ({self.share_cents}c, {self.status})"
