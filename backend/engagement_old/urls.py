from django.urls import re_path
from .views import (
    RegisterView, LoginView, LogoutView,
    StartSessionView, CompleteSessionView,
    CanRateView, RatingsListCreateView,
)

urlpatterns = [
    # Auth
    re_path(r'^auth/register/?$', RegisterView.as_view()),
    re_path(r'^auth/login/?$',    LoginView.as_view()),
    re_path(r'^auth/logout/?$',   LogoutView.as_view()),

    # Sessions / Ratings — accepte avec ou sans "/" final
    re_path(r'^escapes/(?P<escape_id>\d+)/sessions/start/?$',    StartSessionView.as_view()),
    re_path(r'^escapes/(?P<escape_id>\d+)/sessions/complete/?$', CompleteSessionView.as_view()),
    re_path(r'^escapes/(?P<escape_id>\d+)/can_rate/?$',          CanRateView.as_view()),
    re_path(r'^escapes/(?P<escape_id>\d+)/ratings/?$',           RatingsListCreateView.as_view()),
]