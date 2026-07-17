# engagement/urls.py
from django.urls import path
from django.http import JsonResponse
from .views import (
    RegisterView, LoginView, LogoutView, MeView,
    PasswordResetRequestView, PasswordResetConfirmView,
    EmailVerifyConfirmView, EmailVerifyResendView,
    GoogleSignInView,
    AccountDeletionRequestView,
    StartSessionView,
    SessionStateView, SessionHistoryView, SessionHintView, SessionAnswerView,
    SessionSyncTimeView,
    CanRateView, ReportEscapeView, RatingsListCreateView,
)

urlpatterns = [
    # Ping/health (engagement scope)
    path('_ping', lambda r: JsonResponse({'ok': True})),

    # Auth
    path('auth/register', RegisterView.as_view()),
    path('auth/login',    LoginView.as_view()),
    path('auth/logout',   LogoutView.as_view()),
    path('auth/me',       MeView.as_view()),
    path('auth/password-reset/request', PasswordResetRequestView.as_view()),
    path('auth/password-reset/confirm', PasswordResetConfirmView.as_view()),
    path('auth/verify-email/confirm', EmailVerifyConfirmView.as_view()),
    path('auth/verify-email/resend',  EmailVerifyResendView.as_view()),
    path('auth/google',   GoogleSignInView.as_view()),
    path('auth/delete-account-request', AccountDeletionRequestView.as_view()),

    # Gameplay (sessions)
    path('escapes/<int:escape_id>/sessions/start',  StartSessionView.as_view()),
    path('escapes/<int:escape_id>/sessions/state',  SessionStateView.as_view()),
    path('escapes/<int:escape_id>/sessions/history', SessionHistoryView.as_view()),
    path('escapes/<int:escape_id>/sessions/hint',   SessionHintView.as_view()),
    path('escapes/<int:escape_id>/sessions/answer', SessionAnswerView.as_view()),
    path('escapes/<int:escape_id>/sessions/sync_time', SessionSyncTimeView.as_view()),
    path('escapes/<int:escape_id>/report', ReportEscapeView.as_view(), name='escape-report'),

    # Ratings
    path('escapes/<int:escape_id>/can_rate',  CanRateView.as_view()),
    path('escapes/<int:escape_id>/ratings',   RatingsListCreateView.as_view()),
]
