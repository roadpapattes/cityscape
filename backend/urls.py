from django.contrib import admin
from django.urls import path, include
from django.http import JsonResponse, HttpResponse
from django.conf import settings
from django.conf.urls.static import static
from engagement.views import CreatorFeedbackView
from surveys.views import survey_page
import os

def health(_):
    return JsonResponse({"status": "ok"})

def app_config(_):
    """
    Endpoint pour la configuration de l'app mobile.
    Utilisé pour forcer les mises à jour.

    Politique : l'utilisateur n'a pas le droit d'avoir plus d'une version
    de retard. min_version doit donc toujours être mis à jour à l'avant-
    dernière version publiée (celle juste avant current_version) à chaque
    nouvelle release mobile - sinon cette politique cesse d'être appliquée
    silencieusement (c'est ce qui s'est produit de la 0.3.16 à la 0.3.21 :
    min_version n'avait jamais été rebumpé).
    """
    return JsonResponse({
        "min_version": "0.3.21",
        "current_version": "0.3.22",
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
    path('survey', survey_page),                # page HTML des questionnaires
    path('api/', include('games.urls')),       # puis games (catalogue)
    path('api/', include('engagement.urls')),  # engagement D'ABORD
    path('api/', include('surveys.urls')),     # collecte + schéma questionnaires
    path('api/creator/feedback/', CreatorFeedbackView.as_view(), name='creator-feedback'),

]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)