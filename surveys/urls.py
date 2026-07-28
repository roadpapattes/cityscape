from django.urls import path

from .views import SurveySubmitView, SurveySchemaView

# Inclus sous /api/ par backend/urls.py
urlpatterns = [
    path("survey", SurveySubmitView.as_view(), name="survey-submit"),
    path("survey/schema", SurveySchemaView.as_view(), name="survey-schema"),
]
