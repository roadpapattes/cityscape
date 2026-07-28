from django.urls import path

from .views import SurveySubmitView, SurveySchemaView
from .views_admin import (
    AdminSurveyResponsesView, AdminSurveyStatsView, AdminSurveyExportView,
)

# Inclus sous /api/ par backend/urls.py
urlpatterns = [
    path("survey", SurveySubmitView.as_view(), name="survey-submit"),
    path("survey/schema", SurveySchemaView.as_view(), name="survey-schema"),

    # Consultation admin (staff) depuis le dashboard creator-web
    path("admin/surveys/responses", AdminSurveyResponsesView.as_view(), name="admin-survey-responses"),
    path("admin/surveys/stats", AdminSurveyStatsView.as_view(), name="admin-survey-stats"),
    path("admin/surveys/export", AdminSurveyExportView.as_view(), name="admin-survey-export"),
]
