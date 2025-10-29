from django.contrib import admin
from django.urls import path, include
from django.http import JsonResponse
from django.conf import settings
from django.conf.urls.static import static
from engagement.views import CreatorFeedbackView

def health(_):
    return JsonResponse({"status": "ok"})

urlpatterns = [
    path('api/health', health),
    path('admin/', admin.site.urls),
    path('api/', include('games.urls')),       # puis games (catalogue)
    path('api/', include('engagement.urls')),  # engagement D’ABORD
    path('api/creator/feedback/', CreatorFeedbackView.as_view(), name='creator-feedback'),

]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)