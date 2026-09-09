from django.urls import path

from .views import EscapeUnlockView, PaywallImpressionView

urlpatterns = [
    path('escapes/<int:escape_id>/unlock', EscapeUnlockView.as_view(), name='escape-unlock'),
    path('escapes/<int:escape_id>/paywall_impression', PaywallImpressionView.as_view(), name='paywall-impression'),
]
