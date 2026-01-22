from django.contrib import admin
from django.urls import path, include
from django.http import JsonResponse, HttpResponse
from django.conf import settings
from django.conf.urls.static import static
from engagement.views import CreatorFeedbackView
import os

def health(_):
    return JsonResponse({"status": "ok"})

def app_config(_):
    """
    Endpoint pour la configuration de l'app mobile.
    Utilisé pour forcer les mises à jour.
    """
    return JsonResponse({
        "min_version": "0.3.7",
        "current_version": "0.3.7",
        "force_update": True,
        "update_message": "Une nouvelle version est disponible! Mettez à jour pour profiter des dernières fonctionnalités."
    })

def privacy_policy(_):
    html_path = os.path.join(settings.BASE_DIR, 'static_html', 'privacy-policy.html')
    with open(html_path, 'r', encoding='utf-8') as f:
        return HttpResponse(f.read(), content_type='text/html')

def delete_account(_):
    html_path = os.path.join(settings.BASE_DIR, 'static_html', 'delete-account.html')
    with open(html_path, 'r', encoding='utf-8') as f:
        return HttpResponse(f.read(), content_type='text/html')

def index(_):
    html_path = os.path.join(settings.BASE_DIR, 'static_html', 'index.html')
    with open(html_path, 'r', encoding='utf-8') as f:
        return HttpResponse(f.read(), content_type='text/html')

def downloads_redirect(_):
    html_path = os.path.join(settings.BASE_DIR, 'static_html', 'downloads.html')
    with open(html_path, 'r', encoding='utf-8') as f:
        return HttpResponse(f.read(), content_type='text/html')

urlpatterns = [
    path('', index),  # Page d'accueil
    path('downloads/', downloads_redirect),  # Redirection anciens téléchargements APK
    path('api/health', health),
    path('api/app-config', app_config),
    path('privacy-policy', privacy_policy),
    path('delete-account', delete_account),
    path('admin/', admin.site.urls),
    path('api/', include('games.urls')),       # puis games (catalogue)
    path('api/', include('engagement.urls')),  # engagement D'ABORD
    path('api/creator/feedback/', CreatorFeedbackView.as_view(), name='creator-feedback'),

]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)