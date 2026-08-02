# games/api.py
from math import radians, sin, cos, asin, sqrt
from typing import Any, Optional, List

from django.db.models import Q
from django.contrib.auth.models import AnonymousUser

from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import AllowAny


def _try_import_model(module: str, *names: str) -> Optional[Any]:
    try:
        m = __import__(module, fromlist=["*"])
    except Exception:
        return None
    for n in names:
        if hasattr(m, n):
            return getattr(m, n)
    return None


EscapeModel = _try_import_model("games.models", "EscapeGame", "Escape", "Game")
RatingModel = (
    _try_import_model("engagement.models", "Rating")
    or _try_import_model("games.models", "Rating", "EscapeRating", "Review", "Comment")
)

FALLBACK_ESCAPES = [
    {"id": 1, "title": "Paris Mystère", "description": "Autour de l'île de la Cité", "city": "Paris",
     "latitude": 48.8566, "longitude": 2.3522, "rating": 4.6, "duration_minutes": 75, "difficulty": 2,
     "created_at": "2025-01-01T12:00:00Z", "status": "published"},
    {"id": 2, "title": "Canebière Secrets", "description": "Vieux-Port", "city": "Marseille",
     "latitude": 43.2965, "longitude": 5.3698, "rating": 4.3, "duration_minutes": 60, "difficulty": 3,
     "created_at": "2025-01-10T12:00:00Z", "status": "published"},
    {"id": 3, "title": "Lyon Enigmas", "description": "Presqu'île", "city": "Lyon",
     "latitude": 45.7640, "longitude": 4.8357, "rating": 4.8, "duration_minutes": 90, "difficulty": 2,
     "created_at": "2025-02-01T12:00:00Z", "status": "published"},
]


def _to_dict_escape(obj) -> dict:
    if obj is None:
        return {}
    g = getattr

    def _first(*names, default=None):
        for n in names:
            if hasattr(obj, n):
                return g(obj, n)
        return default

    return {
        "id": _first("id"),
        "title": _first("title", "name", default=""),
        "description": _first("description", default=""),
        "city": _first("city", default=""),
        "latitude": float(_first("latitude", "lat", default=0.0) or 0.0),
        "longitude": float(_first("longitude", "lng", "lon", default=0.0) or 0.0),
        "rating": float(_first("rating", "avg_rating", default=0.0) or 0.0),
        "duration_minutes": int(_first("duration_minutes", "duration", default=60) or 60),
        "difficulty": int(_first("difficulty", default=1) or 1),
        "created_at": _first("created_at", default=None),
        "status": _first("status", default="published"),
        "image_url": _first("image_url", default=None),
        "image_credit": _first("image_credit", default="") or "",
        "age_rating": _first("age_rating", default="3"),
        "creator": getattr(obj, "creator_display_name", "") or "",
    }


def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    R = 6371.0
    dlat = radians(lat2 - lat1)
    dlon = radians(lon2 - lon1)
    a = sin(dlat / 2) ** 2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon / 2) ** 2
    return 2 * R * asin(sqrt(a))


def _visible_qs(request):
    """
    Filtre commun : published + confidentialité.
    Public: is_private=False
    Authentifié: public OU owner OU autorisé via allowed_users.
    """
    if EscapeModel is None:
        return []

    qs = EscapeModel.objects.all()
    if any(f.name == "owner" for f in EscapeModel._meta.fields):
        qs = qs.select_related("owner")

    # status='published' si le champ existe
    if any(f.name == "status" for f in EscapeModel._meta.fields):
        qs = qs.filter(status="published")

    # pas de champ de confidentialité -> on retourne tel quel
    has_privacy = any(f.name == "is_private" for f in EscapeModel._meta.fields)
    has_allowed = any(
        getattr(f, "many_to_many", False) and f.name == "allowed_users"
        for f in EscapeModel._meta.many_to_many
    )

    user = getattr(request, "user", None)
    if not has_privacy:
        return qs

    # Anonyme / non authentifié -> uniquement publics
    if not user or isinstance(user, AnonymousUser) or not user.is_authenticated:
        return qs.filter(Q(is_private=False) | Q(is_private__isnull=True)).distinct()

    # Authentifié
    if has_allowed:
        return qs.filter(
            Q(is_private=False) |
            Q(owner=user) |
            Q(allowed_users=user)
        ).distinct()

    # S'il n'y a pas de M2M allowed_users, fallback owner/public
    return qs.filter(
        Q(is_private=False) | Q(owner=user)
    ).distinct()


@api_view(["GET"])
@permission_classes([AllowAny])
def escapes_list(request):
    if EscapeModel is None:
        return Response(FALLBACK_ESCAPES)
    qs = _visible_qs(request)
    data = [_to_dict_escape(e) for e in qs]
    return Response(data)


@api_view(["GET"])
@permission_classes([AllowAny])
def escapes_nearby(request):
    try:
        lat = float(request.GET.get("lat"))
        lon = float(request.GET.get("lon"))
        radius = float(request.GET.get("radius_km", 8))
    except Exception:
        return Response({"detail": "lat/lon invalides"}, status=status.HTTP_400_BAD_REQUEST)

    if EscapeModel is None:
        res = [e for e in FALLBACK_ESCAPES if _haversine_km(lat, lon, e["latitude"], e["longitude"]) <= radius]
        return Response(res)

    qs = _visible_qs(request).only(
        "id", "title", "latitude", "longitude", "city", "image_url", "image_credit", "age_rating", "owner"
    )
    out: List[dict] = []
    for e in qs:
        d = _to_dict_escape(e)
        if d["latitude"] and d["longitude"]:
            if _haversine_km(lat, lon, d["latitude"], d["longitude"]) <= radius:
                out.append(d)
    return Response(out)


@api_view(["GET"])
@permission_classes([AllowAny])
def comments_list(request, pk: int):
    limit = int(request.GET.get("limit", 3))

    if RatingModel is None:
        return Response([])

    qs = RatingModel.objects.all()
    possible_fk = [f.name for f in RatingModel._meta.fields if getattr(f, "is_relation", False)]
    fk_name = None
    for cand in ("escape", "escape_game", "game", "parent"):
        if cand in possible_fk:
            fk_name = cand
            break
    if fk_name:
        qs = qs.filter(**{f"{fk_name}_id": pk})
    if any(f.name == "created_at" for f in RatingModel._meta.fields):
        qs = qs.order_by("-created_at")
    qs = qs[:limit]

    items = []
    for r in qs:
        g = getattr
        items.append({
            "user": getattr(getattr(r, "user", None), "username", "Anonyme"),
            "stars": int(g(r, "stars", g(r, "note", 0)) or 0),
            "comment": g(r, "comment", g(r, "text", "")) or "",
            "created_at": g(r, "created_at", None),
        })
    return Response(items)
