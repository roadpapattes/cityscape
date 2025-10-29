from django.contrib.auth import authenticate, get_user_model
from django.utils import timezone
from django.db.models import Avg, Count
from django.db import transaction
from django.shortcuts import get_object_or_404
from rest_framework import permissions
from rest_framework.authtoken.models import Token
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.permissions import IsAuthenticated

from .models import PlaySession, EscapeCompletion, Rating
from .serializers import (
    UserSerializer,
    RegisterSerializer,
    LoginSerializer,
    PlaySessionSerializer,
    RatingSerializer,
)

# NOTE: Adjust this import if your escapes app isn't named "games".
from games.models import EscapeGame

User = get_user_model()

# -------- Auth --------

class RegisterView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        s = RegisterSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        username = s.validated_data["username"]
        email = s.validated_data.get("email") or ""
        password = s.validated_data["password"]
        if User.objects.filter(username=username).exists():
            return Response({"detail": "Username already exists."}, status=400)
        user = User.objects.create_user(username=username, email=email, password=password)
        token, _ = Token.objects.get_or_create(user=user)
        return Response({"token": token.key, "user": UserSerializer(user).data}, status=201)


class LoginView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        s = LoginSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        user = authenticate(
            request, username=s.validated_data["username"], password=s.validated_data["password"]
        )
        if not user:
            return Response({"detail": "Invalid credentials."}, status=400)
        token, _ = Token.objects.get_or_create(user=user)
        return Response({"token": token.key, "user": UserSerializer(user).data}, status=200)


class LogoutView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        Token.objects.filter(user=request.user).delete()
        return Response({"detail": "Logged out."}, status=200)


# -------- Sessions --------

class StartSessionView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, escape_id: int):
        try:
            escape = EscapeGame.objects.get(pk=escape_id)
        except EscapeGame.DoesNotExist:
            return Response({"detail": "Escape not found."}, status=404)

        session, created = PlaySession.objects.get_or_create(user=request.user, escape=escape)
        return Response(PlaySessionSerializer(session).data, status=201 if created else 200)


class CompleteSessionView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, escape_id: int):
        code = (request.data or {}).get("code", "").strip()
        if not code:
            return Response({"detail": "Code required."}, status=400)
        try:
            escape = EscapeGame.objects.get(pk=escape_id)
        except EscapeGame.DoesNotExist:
            return Response({"detail": "Escape not found."}, status=404)

        comp, _ = EscapeCompletion.objects.get_or_create(escape=escape)
        if code != comp.code:
            return Response({"detail": "Invalid code."}, status=400)

        session, _ = PlaySession.objects.get_or_create(user=request.user, escape=escape)
        if not session.completed_at:
            session.completed_at = timezone.now()
            session.save(update_fields=["completed_at"])
        return Response(PlaySessionSerializer(session).data, status=200)


class CanRateView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, escape_id: int):
        try:
            escape = EscapeGame.objects.get(pk=escape_id)
        except EscapeGame.DoesNotExist:
            return Response({"detail": "Escape not found."}, status=404)
        has_completed = PlaySession.objects.filter(
            user=request.user, escape=escape, completed_at__isnull=False
        ).exists()
        already_rated = Rating.objects.filter(user=request.user, escape=escape).exists()
        return Response({"can_rate": bool(has_completed and not already_rated)}, status=200)


# -------- Ratings --------

class RatingsListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, escape_id):
        /*from django.shortcuts import get_object_or_404
        from games.models import EscapeGame
        from .models import Rating
        from .serializers import RatingSerializer*/

        escape = get_object_or_404(EscapeGame, pk=escape_id)

        s = RatingSerializer(data={
            "stars": request.data.get("stars"),
            "comment": request.data.get("comment", ""),
        })
        s.is_valid(raise_exception=True)

        with transaction.atomic():
            rating = Rating.objects.create(
                user=request.user,
                escape=escape,
                stars=s.validated_data["stars"],
                comment=s.validated_data.get("comment", ""),
            )
            agg = Rating.objects.filter(escape=escape).aggregate(avg=Avg("stars"))
            escape.rating = float(agg["avg"] or 0.0)
            escape.save(update_fields=["rating"])

        return Response({
            "rating": RatingSerializer(rating).data,
            "aggregate": {"avg": float(agg["avg"] or 0.0), "count": escape.rating and 1},
        }, status=201)