# games/serializers_creator.py
from rest_framework import serializers

# --- Alias robustes sur les modèles ---
try:
    from .models import Escape as EscapeModel
except Exception:
    try:
        from .models import EscapeGame as EscapeModel
    except Exception:
        # Dernier fallback (si tu avais un autre nom)
        from .models import Game as EscapeModel  # adapte si besoin

try:
    from .models import EscapeStep as EscapeStepModel
except Exception:
    try:
        from .models import Step as EscapeStepModel
    except Exception:
        EscapeStepModel = None  # si pas de modèle d'étapes, on gère plus bas


class EscapeReadSerializer(serializers.Serializer):
    """Serializer de lecture sans dépendre des noms exacts des champs du modèle."""
    id = serializers.IntegerField()
    title = serializers.CharField()
    city = serializers.CharField()
    status = serializers.CharField(required=False, allow_blank=True)
    rating = serializers.FloatField(required=False)
    duration_minutes = serializers.IntegerField(required=False)
    difficulty = serializers.IntegerField(required=False)
    created_at = serializers.DateTimeField(required=False)

    def to_representation(self, instance):
        g = getattr
        return {
            "id": g(instance, "id", None),
            "title": g(instance, "title", "") or g(instance, "name", ""),
            "city": g(instance, "city", ""),
            "status": g(instance, "status", "draft"),
            "rating": float(g(instance, "rating", 0) or 0),
            "duration_minutes": int(g(instance, "duration_minutes", 60) or 60),
            "difficulty": int(g(instance, "difficulty", 1) or 1),
            "created_at": g(instance, "created_at", None),
        }


class StepWriteSerializer(serializers.Serializer):
    order = serializers.IntegerField()
    title = serializers.CharField(required=False, allow_blank=True)
    prompt = serializers.CharField()   # énoncé / indice
    answer = serializers.CharField()
    latitude = serializers.FloatField()
    longitude = serializers.FloatField()
    radius_m = serializers.IntegerField(default=50)


class EscapeWriteSerializer(serializers.Serializer):
    title = serializers.CharField()
    description = serializers.CharField(required=False, allow_blank=True)
    city = serializers.CharField()
    latitude = serializers.FloatField()
    longitude = serializers.FloatField()
    duration_minutes = serializers.IntegerField(default=60)
    difficulty = serializers.IntegerField(default=2)
    end_code = serializers.CharField(required=False, allow_blank=True)  # si le modèle l'a
    steps = StepWriteSerializer(many=True, required=False)
