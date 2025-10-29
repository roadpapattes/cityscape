from django.contrib.auth import get_user_model
from rest_framework import serializers
from .models import PlaySession, Rating

User = get_user_model()

class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ("id", "username", "email")

class RegisterSerializer(serializers.Serializer):
    username = serializers.CharField()
    email = serializers.EmailField(required=False, allow_blank=True)
    password = serializers.CharField(write_only=True, min_length=6)

class LoginSerializer(serializers.Serializer):
    username = serializers.CharField()
    password = serializers.CharField(write_only=True)

class PlaySessionSerializer(serializers.ModelSerializer):
    class Meta:
        model = PlaySession
        fields = ("id", "escape", "started_at", "completed_at")

class RatingSerializer(serializers.ModelSerializer):
    user = UserSerializer(read_only=True)

    class Meta:
        model = Rating
        fields = ("id", "escape", "user", "stars", "comment", "created_at")

    def validate_stars(self, value):
        if value < 1 or value > 5:
            raise serializers.ValidationError("Stars must be between 1 and 5.")
        return value

class RatingCommentSerializer(serializers.ModelSerializer):
    user = serializers.CharField(source='user.username', read_only=True)

    class Meta:
        model = Rating
        fields = ['user', 'stars', 'comment', 'created_at']


# --- Steps (public) ---
from games.models import EscapeStep

class PublicStepSerializer(serializers.ModelSerializer):
    hints_total = serializers.SerializerMethodField()
    class Meta:
        model = EscapeStep
        fields = ("order", "prompt", "hints_total")

    def get_hints_total(self, obj):
        return sum(1 for h in [obj.hint1, obj.hint2, obj.hint3] if (h or "").strip())
