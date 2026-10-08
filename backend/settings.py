
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

SECRET_KEY = os.getenv('DJANGO_SECRET_KEY', 'dev-secret-key-change-me')
DEBUG = os.getenv('DEBUG', 'False').lower() in ('true', '1', 'yes')
# ALLOWED_HOSTS = ['*']
def _split_env_list(key, default=""):
    return [x.strip() for x in os.getenv(key, default).split(",") if x.strip()]

ALLOWED_HOSTS = _split_env_list("ALLOWED_HOSTS", "localhost,127.0.0.1")
CSRF_TRUSTED_ORIGINS = _split_env_list("CSRF_TRUSTED_ORIGINS", "")

# Django reçoit HTTP depuis le NAS, mais le client est en HTTPS :
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

# CORS : piloté par l'environnement comme ALLOWED_HOSTS, pour ne pas laisser
# d'origines de développement actives en production. Ajouter localhost dans le
# .env local (CORS_ALLOWED_ORIGINS=https://api.cityscape.ovh,http://localhost:3000)
CORS_ALLOWED_ORIGINS = _split_env_list(
    "CORS_ALLOWED_ORIGINS", "https://api.cityscape.ovh"
)

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
    'surveys',
    'monetization',
]

# Lancement gratuit instrumenté (voir note de cadrage monétisation) : tant
# que False, tout déblocage d'escape payante passe par un Purchase simulé
# à 0 centime (aucun argent réel, aucune intégration Google Play Billing
# active). Ne pas activer sans avoir terminé la Phase 3 de la feuille de
# route (structure juridique créée, intégration Play Billing réelle).
MONETIZATION_ENABLED = False

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

# Base de données pilotée par variables d'environnement.
# Par défaut : SQLite (dev/test). Avec DB_ENGINE=postgres : PostgreSQL.
# Bascule / rollback = une simple variable d'env, sans re-déployer de code.
if os.getenv('DB_ENGINE') == 'postgres':
    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.postgresql',
            'NAME': os.getenv('DB_NAME', 'cityscape'),
            'USER': os.getenv('DB_USER', 'cityscape'),
            'PASSWORD': os.getenv('DB_PASSWORD'),
            'HOST': os.getenv('DB_HOST', '127.0.0.1'),
            'PORT': os.getenv('DB_PORT', '5432'),
            'CONN_MAX_AGE': int(os.getenv('DB_CONN_MAX_AGE', '60')),
            # Revalide une connexion persistante avant réutilisation : évite un
            # plantage sur la 1re requête si PG a coupé la connexion entretemps
            # (restart, timeout réseau). Va de pair avec CONN_MAX_AGE > 0.
            'CONN_HEALTH_CHECKS': True,
        }
    }
else:
    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.sqlite3',
            'NAME': BASE_DIR / 'db.sqlite3',
        }
    }

AUTH_PASSWORD_VALIDATORS = [
    {
        'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator',
        'OPTIONS': {'min_length': 8}
    },
    {
        'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator',
    },
]

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
        'engagement.authentication.ExpiringTokenAuthentication',
    ],
    'DEFAULT_PERMISSION_CLASSES': [
        'rest_framework.permissions.IsAuthenticated',
    ],
    'EXCEPTION_HANDLER': 'engagement.exceptions.custom_exception_handler',
}

# Expiration glissante des jetons d'API : 90 jours depuis la DERNIERE
# utilisation, pas depuis la creation. Un joueur regulier n'est donc jamais
# deconnecte, tandis qu'un jeton oublie ou derobe finit par expirer.
# AUTH_TOKEN_TOUCH_HOURS limite la frequence d'ecriture de la date de
# derniere utilisation (voir engagement/authentication.py).
AUTH_TOKEN_TTL_DAYS = 90
AUTH_TOKEN_TOUCH_HOURS = 24

# django-ratelimit : sans ceci, la clé 'ip' retombe sur REMOTE_ADDR, qui vaut
# l'adresse de nginx (127.0.0.1) pour toutes les requêtes — toutes les limites
# par IP partageaient donc un seul compteur global. Voir engagement/ratelimit_ip.py
RATELIMIT_IP_META_KEY = 'engagement.ratelimit_ip.client_ip'

# Cache partagé entre tous les workers Gunicorn (utilisé par django-ratelimit).
# Fichier sur disque plutôt que LocMemCache (non partagé entre workers) ou
# DatabaseCache (contention d'écriture sur le même fichier que db.sqlite3).
CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.filebased.FileBasedCache",
        "LOCATION": BASE_DIR / "django_cache",
    }
}

# --- Email (Gmail SMTP) ---
# ⚠️ Nécessite un "mot de passe d’application" Google (A2F obligatoire).
EMAIL_BACKEND = "django.core.mail.backends.smtp.EmailBackend"
EMAIL_HOST = "smtp.gmail.com"
EMAIL_PORT = 587
EMAIL_USE_TLS = True
EMAIL_USE_SSL = False

EMAIL_HOST_USER = os.getenv('EMAIL_HOST_USER', 'feedback.enigmapolis@gmail.com')
EMAIL_HOST_PASSWORD = os.getenv('EMAIL_HOST_PASSWORD')

# Expéditeur = le compte Gmail authentifié (obligatoire pour que Gmail SMTP
# n'écrase/ne rejette pas l'envoi). Surchargeable via l'env.
DEFAULT_FROM_EMAIL = os.getenv('DEFAULT_FROM_EMAIL', f"CityScape <{EMAIL_HOST_USER}>")
SERVER_EMAIL = DEFAULT_FROM_EMAIL  # emails d'erreur Django (optionnel)

# Destinataire des notifications « nouvel avis » (questionnaires de satisfaction).
# Un e-mail est envoyé à chaque nouvel avis reçu. Surchargeable via l'env
# (plusieurs adresses possibles, séparées par des virgules).
SURVEY_NOTIFY_EMAIL = os.getenv('SURVEY_NOTIFY_EMAIL', 'damien.gilbon@gmail.com')







# Chemin de l'administration Django.
#
# Volontairement lu depuis l'environnement et JAMAIS ecrit en dur ici : le
# depot est public, donc un chemin code dans le fichier serait publie avec
# lui, ce qui vide la mesure de son sens. Garder la valeur reelle dans le
# .env du serveur.
#
# L'interet est modeste mais reel : le formulaire de connexion de l'admin
# n'est couvert par aucune des limites de debit du projet (elles protegent
# l'API), et /admin/ est la premiere chose que balaient les robots. Changer
# le chemin ne remplace pas un mot de passe solide, il supprime le bruit
# automatise.
DJANGO_ADMIN_URL = os.getenv('DJANGO_ADMIN_URL', 'admin/')

# Google OAuth
GOOGLE_OAUTH_CLIENT_ID = os.getenv('GOOGLE_OAUTH_CLIENT_ID')

# Security headers
SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_BROWSER_XSS_FILTER = True
X_FRAME_OPTIONS = 'DENY'

# HTTPS settings (active en production quand DEBUG=False)
if not DEBUG:
    SECURE_SSL_REDIRECT = True
    SESSION_COOKIE_SECURE = True
    CSRF_COOKIE_SECURE = True
    SECURE_HSTS_SECONDS = 31536000  # 1 an
    SECURE_HSTS_INCLUDE_SUBDOMAINS = True
    SECURE_HSTS_PRELOAD = True
