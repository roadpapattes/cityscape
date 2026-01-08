
from pathlib import Path
import os
import sys
# Load environment variables from .env file first
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass


BASE_DIR = Path(__file__).resolve().parent.parent
# fichiers médias
MEDIA_URL = '/media/'
MEDIA_ROOT = BASE_DIR / 'media'
APPEND_SLASH = False

SECRET_KEY = 'dev-secret-key-change-me'
DEBUG = True
# ALLOWED_HOSTS = ['*']
def _split_env_list(key, default=""):
    return [x.strip() for x in os.getenv(key, default).split(",") if x.strip()]

ALLOWED_HOSTS = _split_env_list("ALLOWED_HOSTS", "localhost,127.0.0.1")
CSRF_TRUSTED_ORIGINS = _split_env_list("CSRF_TRUSTED_ORIGINS", "")

# Django reçoit HTTP depuis le NAS, mais le client est en HTTPS :
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

# (Recommandé) CORS si tu testes depuis une app/WEB :
# pip install django-cors-headers
CORS_ALLOWED_ORIGINS = [
    "https://api.cityscape.ovh",
    "http://localhost:3000",   # si tu fais des tests front local
    "http://10.0.2.2:8000",    # si tu testes via émulateur Android
]

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'rest_framework',
    'rest_framework.authtoken',  # <-- important
    'engagement.apps.EngagementConfig',   # notre app
    'django_filters',
    'games',
    'corsheaders',
]

MIDDLEWARE = [
    'corsheaders.middleware.CorsMiddleware',
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'backend.urls'
DEFAULT_CHARSET = "utf-8"

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'backend.wsgi.application'

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': BASE_DIR / 'db.sqlite3',
    }
}

AUTH_PASSWORD_VALIDATORS = []

LANGUAGE_CODE = 'fr-fr'
TIME_ZONE = 'Europe/Paris'
USE_I18N = True
USE_TZ = True

STATIC_URL = '/static/'
DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'
STATIC_ROOT = os.getenv('STATIC_ROOT', '/var/www/cityscape/static')
MEDIA_ROOT = os.getenv('MEDIA_ROOT', '/var/www/cityscape/media')

REST_FRAMEWORK = {
    'DEFAULT_FILTER_BACKENDS': [
        'django_filters.rest_framework.DjangoFilterBackend'
    ],
    'DEFAULT_AUTHENTICATION_CLASSES': [
        'rest_framework.authentication.TokenAuthentication',
    ],
    'DEFAULT_PERMISSION_CLASSES': [
        'rest_framework.permissions.AllowAny',
    ]
}

# --- Email (Gmail SMTP) ---
# ⚠️ Nécessite un "mot de passe d’application" Google (A2F obligatoire).
EMAIL_BACKEND = "django.core.mail.backends.smtp.EmailBackend"
EMAIL_HOST = "smtp.gmail.com"
EMAIL_PORT = 587
EMAIL_USE_TLS = True
EMAIL_USE_SSL = False

EMAIL_HOST_USER = "feedback.enigmapolis@gmail.com"            # <-- ton adresse Gmail
EMAIL_HOST_PASSWORD = "nzvfzwujgbgymsrh"   # <-- 16 caractères générés par Google

DEFAULT_FROM_EMAIL = "Escape City <toncompte@gmail.com>"
SERVER_EMAIL = DEFAULT_FROM_EMAIL  # emails d'erreur Django (optionnel)






