from django.conf import settings
from django.shortcuts import get_object_or_404
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from games.models import EscapeGame

from .services import MonetizationNotReady, has_access, record_paywall_impression, unlock_escape


def _purchase_payload(purchase):
    return {
        "id": purchase.id,
        "payment_provider": purchase.payment_provider,
        "amount_cents": purchase.amount_cents,
        "currency": purchase.currency,
        "status": purchase.status,
        "purchased_at": purchase.purchased_at.isoformat(),
    }


class EscapeUnlockView(APIView):
    """Débloque une escape payante pour le joueur connecté.

    Tant que settings.MONETIZATION_ENABLED est False, ceci ne fait que
    créer un Purchase simulé à 0 centime — aucun paiement réel n'a lieu
    (voir monetization.services.unlock_escape).
    """

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, escape_id: int):
        escape = get_object_or_404(EscapeGame, pk=escape_id)

        if not escape.is_paid:
            return Response(
                {"detail": "Cette escape est gratuite, aucun déblocage requis."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            purchase = unlock_escape(request.user, escape)
        except MonetizationNotReady as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_501_NOT_IMPLEMENTED)

        return Response(
            {"ok": True, "unlocked": True, "purchase": _purchase_payload(purchase)},
            status=status.HTTP_200_OK,
        )

    def get(self, request, escape_id: int):
        """État du déblocage pour ce joueur (utilisé par l'app avant de
        lancer une session sur une escape payante)."""
        escape = get_object_or_404(EscapeGame, pk=escape_id)
        return Response({
            "escape_id": escape.id,
            "price_cents": escape.price_cents,
            "currency": escape.currency,
            "monetization_enabled": bool(getattr(settings, "MONETIZATION_ENABLED", False)),
            "unlocked": has_access(request.user, escape),
        })


class PaywallImpressionView(APIView):
    """Enregistre que le joueur a vu l'écran de déblocage d'une escape
    payante — signal de conversion (voir monetization.funnel). Appelé par
    l'app au moment où le dialogue de déblocage s'affiche, indépendamment
    de la suite (déblocage ou abandon)."""

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, escape_id: int):
        escape = get_object_or_404(EscapeGame, pk=escape_id)
        if not escape.is_paid:
            return Response(
                {"detail": "Cette escape est gratuite, pas de paywall à mesurer."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        record_paywall_impression(request.user, escape)
        return Response({"ok": True}, status=status.HTTP_201_CREATED)
