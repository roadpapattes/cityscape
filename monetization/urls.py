from django.urls import path

from .views import EscapeUnlockView

urlpatterns = [
    path('escapes/<int:escape_id>/unlock', EscapeUnlockView.as_view(), name='escape-unlock'),
]
