# games/urls.py
from django.urls import path
from rest_framework.routers import DefaultRouter

from .api import escapes_list, escapes_nearby, comments_list
from .views_creator import CreatorEscapeViewSet
from .views import CreatorImageUploadView, CreatorAudioUploadView

urlpatterns = [
    path('escapes', escapes_list, name='escapes-list'),
    path('escapes/nearby', escapes_nearby, name='escapes-nearby'),
    path('escapes/<int:pk>/comments', comments_list, name='comments-list'),
    path('creator/upload_image', CreatorImageUploadView.as_view(), name='creator_upload_image'),
    path('creator/upload_audio', CreatorAudioUploadView.as_view(), name='creator_upload_audio'),
    # En prod, sers /media/ via ton serveur (Nginx/S3…), mais pour dev c’est suffisant.
]

# Routes "créateur" (auth requise)
router = DefaultRouter(trailing_slash=False)
router.register(r'creator/escapes', CreatorEscapeViewSet, basename='creator-escapes')

urlpatterns += router.urls