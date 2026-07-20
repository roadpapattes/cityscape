# engagement/views_admin.py
from django.contrib.auth import get_user_model
from django.db.models import Count
from rest_framework import mixins, serializers, status, viewsets
from rest_framework.permissions import IsAdminUser
from rest_framework.response import Response
from rest_framework.views import APIView

from games.models import EscapeGame
from .models import PlaySession

User = get_user_model()


class AdminUserSerializer(serializers.ModelSerializer):
    role = serializers.SerializerMethodField()
    email_verified = serializers.SerializerMethodField()
    escapes_created = serializers.SerializerMethodField()
    sessions_count = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = (
            "id", "username", "email", "is_active", "is_staff", "is_superuser",
            "role", "email_verified", "escapes_created", "sessions_count", "date_joined",
        )

    def get_role(self, obj):
        if obj.is_superuser:
            return "superadmin"
        if obj.is_staff:
            return "staff"
        if getattr(obj, "_escapes_count", 0) > 0:
            return "createur"
        return "joueur"

    def get_email_verified(self, obj):
        profile = getattr(obj, "profile", None)
        return bool(profile.email_verified) if profile else True

    def get_escapes_created(self, obj):
        return getattr(obj, "_escapes_count", None)

    def get_sessions_count(self, obj):
        return getattr(obj, "_sessions_count", None)


class AdminUserViewSet(
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    viewsets.GenericViewSet,
):
    """
    Lecture + activation/désactivation des comptes. Pas de create/destroy :
    la création se fait par inscription normale, la suppression reste réservée
    à l'admin Django/shell.
    """
    permission_classes = [IsAdminUser]
    serializer_class = AdminUserSerializer

    def get_queryset(self):
        return (
            User.objects
            .select_related("profile")
            .annotate(
                _escapes_count=Count("created_escapes", distinct=True),
                _sessions_count=Count("play_sessions", distinct=True),
            )
            .order_by("username")
        )

    def _apply_update(self, request, target):
        data = request.data
        update_fields = []

        if "is_active" in data:
            new_active = bool(data["is_active"])
            if target.pk == request.user.pk and not new_active:
                return None, Response(
                    {"detail": "Vous ne pouvez pas désactiver votre propre compte."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            target.is_active = new_active
            update_fields.append("is_active")

        if "is_staff" in data:
            if not request.user.is_superuser:
                return None, Response(
                    {"detail": "Seul un superadmin peut modifier le statut staff."},
                    status=status.HTTP_403_FORBIDDEN,
                )
            target.is_staff = bool(data["is_staff"])
            update_fields.append("is_staff")

        if update_fields:
            target.save(update_fields=update_fields)

        return target, None

    def partial_update(self, request, *args, **kwargs):
        target = self.get_object()
        target, error = self._apply_update(request, target)
        if error:
            return error
        return Response(AdminUserSerializer(self.get_queryset().get(pk=target.pk)).data)

    def update(self, request, *args, **kwargs):
        return self.partial_update(request, *args, **kwargs)


class AdminStatsView(APIView):
    permission_classes = [IsAdminUser]

    def get(self, request):
        users_total = User.objects.count()
        users_active = User.objects.filter(is_active=True).count()

        status_counts = {
            row["status"]: row["count"]
            for row in EscapeGame.objects.values("status").annotate(count=Count("id"))
        }
        escapes_by_status = {
            s: status_counts.get(s, 0) for s in ("draft", "submitted", "published", "rejected")
        }

        sessions_in_progress = PlaySession.objects.filter(completed_at__isnull=True).count()
        sessions_completed = PlaySession.objects.filter(completed_at__isnull=False).count()

        return Response({
            "users_total": users_total,
            "users_active": users_active,
            "escapes_by_status": escapes_by_status,
            "sessions_in_progress": sessions_in_progress,
            "sessions_completed": sessions_completed,
        })
