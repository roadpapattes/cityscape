from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework import permissions
from rest_framework.viewsets import ReadOnlyModelViewSet
from rest_framework.permissions import AllowAny, IsAuthenticated

from django.core.files.storage import default_storage
from django.utils.crypto import get_random_string
from django.conf import settings
from django.db.models import QuerySet, Q

from .models import EscapeGame
from .serializers import EscapeGameSerializer, CreatorEscapeListSerializer

from engagement.models import Rating
from engagement.serializers_comments import RatingCommentSerializer

import math
import os


def haversine_km(lat1, lon1, lat2, lon2):
    # distance between two points on Earth
    R = 6371.0
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dlambda/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c


class EscapeGameViewSet(viewsets.ModelViewSet):
    serializer_class = EscapeGameSerializer

    # -------- Visibilité publique (joueurs) --------
    def _visible_qs(self, request):
        """
        Escapes publiés visibles par l'utilisateur :
        - public (is_private=False), OU
        - private mais owner, OU
        - private mais ajouté dans allowed_users
        """
        base = EscapeGame.objects.filter(status="published")
        user = request.user if request.user.is_authenticated else None
        if user:
            base = base.filter(
                Q(is_private=False) |
                Q(owner=user) |
                Q(allowed_users=user)
            )
        else:
            base = base.filter(is_private=False)
        return base.order_by("-created_at").distinct()

    def get_queryset(self) -> QuerySet:
        # DRF utilisera ceci pour list/retrieve/search
        # -> applique la visibilité puis limite au catalogue public (publié)
        return self._visible_qs(self.request).filter(status="published").distinct()

    @action(detail=False, methods=['get'])
    def nearby(self, request):
        try:
            lat = float(request.query_params.get("lat"))
            lon = float(request.query_params.get("lon"))
            radius_km = float(request.query_params.get("radius_km", 5))
        except (TypeError, ValueError):
            return Response({"detail": "Provide lat, lon and optional radius_km (float)."},
                            status=status.HTTP_400_BAD_REQUEST)

        user = getattr(request, "user", None)
        qs = EscapeGame.objects.filter(status="published")

        if user and getattr(user, "is_authenticated", False):
            visibility_q = (
                Q(is_private=False) |
                (Q(is_private=True) & (Q(owner=user) | Q(allowed_users=user)))
            )
        else:
            visibility_q = Q(is_private=False)

        qs = qs.filter(visibility_q).distinct()

        items = []
        for eg in qs:
            # ignore si coords manquantes
            if eg.latitude is None or eg.longitude is None:
                continue
            d = haversine_km(lat, lon, eg.latitude, eg.longitude)
            if d <= radius_km:
                items.append((d, eg))

        items.sort(key=lambda x: x[0])
        data = []
        for dist, eg in items:
            ser = EscapeGameSerializer(eg).data
            ser["distance_km"] = round(dist, 3)
            data.append(ser)
        return Response(data)

    @action(detail=True, methods=['get'], permission_classes=[AllowAny], url_path='comments')
    def comments(self, request, pk=None):
        """Retourne les derniers commentaires (par défaut limit=3), si l'escape est visible par l'utilisateur."""
        # Contrôle d'accès sur l'escape demandé
        eg = self._visible_qs(request).filter(pk=pk).first()
        if eg is None:
            return Response({"detail": "Non autorisé."}, status=status.HTTP_403_FORBIDDEN)

        try:
            limit = int(request.query_params.get('limit', 3))
        except (TypeError, ValueError):
            limit = 3

        qs = (Rating.objects
              .filter(escape_id=pk)
              .exclude(comment__isnull=True)
              .exclude(comment__exact='')
              .order_by('-created_at')[:limit])

        data = RatingCommentSerializer(qs, many=True).data
        return Response(data)


class CreatorImageUploadView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser]

    def post(self, request):
        f = request.FILES.get('file')
        if not f:
            return Response({"detail": "Aucun fichier"}, status=status.HTTP_400_BAD_REQUEST)

        # dossier de destination
        subdir = os.path.join('escapes', request.user.username)
        name = get_random_string(12) + os.path.splitext(f.name)[1].lower()
        path = default_storage.save(os.path.join(subdir, name), f)

        # URL publique
        url = request.build_absolute_uri(os.path.join(settings.MEDIA_URL, path).replace('\\', '/'))
        return Response({"url": url}, status=status.HTTP_201_CREATED)


class CreatorEscapeViewSet(ReadOnlyModelViewSet):
    permission_classes = [IsAuthenticated]
    serializer_class = CreatorEscapeListSerializer

    def get_queryset(self):
        qs = EscapeGame.objects.all()

        # Optimisations pour éviter N+1 selon notre serializer:
        qs = qs.select_related("creator", "created_by") \
               .prefetch_related("steps__creator", "steps__created_by")

        # Filtrage "Mes escapes" pour non-admins
        user = self.request.user
        if not getattr(user, "is_staff", False):
            # garde la logique existante creator/created_by
            qs = qs.filter(creator=user) | qs.filter(created_by=user)

        # Filtre status=... si fourni (brouillon/publié/etc.)
        st = self.request.query_params.get("status")
        if st and st != "all":
            qs = qs.filter(status=st)

        return qs
