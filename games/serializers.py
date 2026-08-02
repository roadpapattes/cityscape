from rest_framework import serializers
from django.contrib.auth import get_user_model
from django.http import QueryDict

from .models import EscapeGame, GameStep

User = get_user_model()


def _coerce_usernames(raw):
    """
    Accepte:
      - ["alice", "bob"]
      - "alice"
      - "alice,bob"
      - "  alice ,  bob  "
    Retourne toujours une liste nettoyée et dédupliquée.
    """
    if raw is None:
        return None
    # QueryDict renvoie parfois str pour un seul élément
    if isinstance(raw, QueryDict):
        raw = raw.getlist("allowed_usernames") or raw.get("allowed_usernames")

    if isinstance(raw, str):
        txt = raw.strip()
        if not txt:
            return []
        # CSV simple
        parts = [p.strip() for p in txt.split(",")]
        return sorted({p for p in parts if p})
    elif isinstance(raw, (list, tuple)):
        parts = [str(p).strip() for p in raw if str(p).strip()]
        return sorted(set(parts))
    # autre type -> ignore
    return []


class EscapeGameSerializer(serializers.ModelSerializer):
    reject_reason = serializers.SerializerMethodField(read_only=True)
    # Crédit créateur affiché sur la fiche descriptive (lecture seule).
    creator = serializers.SerializerMethodField(read_only=True)

    # Privacy
    is_private = serializers.BooleanField(required=False)
    # En écriture, on passe par to_internal_value pour tolérer string/CSV.
    # En lecture, to_representation renverra la liste depuis la M2M.
    allowed_usernames = serializers.ListField(
        child=serializers.CharField(allow_blank=False, trim_whitespace=True),
        required=False
    )

    class Meta:
        model = EscapeGame
        fields = (
            "id", "title", "city", "status", "created_at", "image_url",
            "description", "victory_message", "duration_minutes", "difficulty",
            "age_rating", "creator",
            "latitude", "longitude",
            "penalize_wrong_answers", "wrong_answer_penalty",
            "reject_reason",
            # privacy
            "is_private", "allowed_usernames",
        )
        read_only_fields = ("id", "created_at", "owner", "creator")

    # ---------- Crédit créateur (#8a) ----------
    def get_creator(self, obj):
        return obj.creator_display_name

    # ---------- READ ----------
    def get_reject_reason(self, obj):
        for name in ("reject_reason", "rejection_reason", "moderation_reason", "reason"):
            if hasattr(obj, name):
                val = getattr(obj, name) or ""
                if isinstance(val, str) and val.strip():
                    return val
        return ""

    def to_representation(self, instance):
        data = super().to_representation(instance)
        # Expose la liste des pseudos autorisés depuis la M2M
        data["allowed_usernames"] = list(
            instance.allowed_users.values_list("username", flat=True)
        ) if hasattr(instance, "allowed_users") else []
        return data

    # ---------- WRITE ----------
    def to_internal_value(self, data):
        """
        Rends l'API tolérante:
        - accepte 'allowed_usernames' en string, CSV ou liste
        - accepte alias legacy 'allowed_users'
        """
        if isinstance(data, (dict, QueryDict)):
            data = data.copy()
            raw = (
                data.get("allowed_usernames")
                if "allowed_usernames" in data
                else data.get("allowed_users")
            )
            coerced = _coerce_usernames(raw)
            if coerced is not None:
                data["allowed_usernames"] = coerced
        return super().to_internal_value(data)

    def _apply_allowed_usernames(self, instance, usernames):
        """
        Mappe allowed_usernames -> allowed_users (M2M) et
        garantit que le créateur reste autorisé.
        """
        if usernames is None:
            return

        wanted = sorted(set([u.strip() for u in usernames if u and u.strip()]))
        users = list(User.objects.filter(username__in=wanted))

        owner = getattr(instance, "owner", None)
        if owner and owner not in users:
            users.append(owner)

        if hasattr(instance, "allowed_users"):
            instance.allowed_users.set(users)

    def update(self, instance, validated_data):
        usernames = validated_data.pop("allowed_usernames", None)
        instance = super().update(instance, validated_data)
        self._apply_allowed_usernames(instance, usernames)
        instance.save(update_fields=[])  # no-op pour déclencher éventuels signaux
        return instance

    def create(self, validated_data):
        usernames = validated_data.pop("allowed_usernames", None)
        instance = super().create(validated_data)

        # À la création, si l'owner existe, s'assurer qu'il est dedans
        if hasattr(instance, "owner") and instance.owner_id:
            if usernames is None:
                usernames = []
            if instance.owner.username not in usernames:
                usernames.append(instance.owner.username)

        self._apply_allowed_usernames(instance, usernames)
        instance.save(update_fields=[])
        return instance


class CreatorEscapeListSerializer(serializers.ModelSerializer):
    creator_id = serializers.SerializerMethodField()
    creator_username = serializers.SerializerMethodField()
    reject_reason = serializers.SerializerMethodField()

    # Exposer aussi privacy côté liste créateur
    is_private = serializers.BooleanField(read_only=True)
    allowed_usernames = serializers.SerializerMethodField(read_only=True)

    class Meta:
        model = EscapeGame
        fields = (
            "id", "title", "status", "image_url", "city", "duration_minutes",
            "latitude", "longitude", "creator_id", "creator_username",
            "description", "victory_message",
            "penalize_wrong_answers", "wrong_answer_penalty", "reject_reason",
            "is_private", "allowed_usernames",
        )

    # --------- helpers ----------
    def get_creator_id(self, obj: EscapeGame):
        u = getattr(obj, "owner", None)
        return getattr(u, "id", None)

    def get_creator_username(self, obj: EscapeGame):
        u = getattr(obj, "owner", None)
        if not u:
            return None
        return getattr(u, "username", None) or getattr(u, "email", None)

    def get_reject_reason(self, obj):
        for name in ('reject_reason', 'rejection_reason', 'moderation_reason', 'reason'):
            if hasattr(obj, name):
                val = getattr(obj, name) or ''
                if isinstance(val, str) and val.strip():
                    return val
        return ''

    def get_allowed_usernames(self, obj: EscapeGame):
        if hasattr(obj, "allowed_users"):
            return list(obj.allowed_users.values_list("username", flat=True))
        return []
