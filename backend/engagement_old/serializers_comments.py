# engagement/serializers_comments.py
from rest_framework import serializers
from .models import Rating  # adapte l'import si le modèle est ailleurs

class RatingCommentSerializer(serializers.ModelSerializer):
    user = serializers.CharField(source='user.username', read_only=True)

    class Meta:
        model = Rating
        fields = ['user', 'stars', 'comment', 'created_at']
