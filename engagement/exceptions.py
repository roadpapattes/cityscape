# engagement/exceptions.py
from django_ratelimit.exceptions import Ratelimited
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import exception_handler as drf_exception_handler


def custom_exception_handler(exc, context):
    """DRF exception handler: turns django_ratelimit's Ratelimited into a clean 429."""
    if isinstance(exc, Ratelimited):
        return Response(
            {"detail": "Trop de tentatives. Réessayez plus tard."},
            status=status.HTTP_429_TOO_MANY_REQUESTS,
        )
    return drf_exception_handler(exc, context)
