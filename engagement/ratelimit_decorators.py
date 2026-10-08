# engagement/ratelimit_decorators.py
"""Rate limiting decorators for CityScape API endpoints"""

from django_ratelimit.decorators import ratelimit
from django.utils.decorators import method_decorator

# Rate limits for authentication endpoints
auth_rate_limit = method_decorator(ratelimit(key='ip', rate='5/h', method='POST', block=True), name='post')
password_reset_rate_limit = method_decorator(ratelimit(key='ip', rate='3/h', method='POST', block=True), name='post')
google_signin_rate_limit = method_decorator(ratelimit(key='ip', rate='10/h', method='POST', block=True), name='post')
email_verify_rate_limit = method_decorator(ratelimit(key='ip', rate='5/h', method='POST', block=True), name='post')

# Tout endpoint non authentifié qui déclenche un envoi d'email est un relais
# potentiel : sans limite, il permet d'inonder la boîte d'un joueur et de
# brûler le quota SMTP, ce qui couperait les réinitialisations de mot de passe.
account_deletion_rate_limit = method_decorator(ratelimit(key='ip', rate='3/h', method='POST', block=True), name='post')

# Le changement de mot de passe exige l'ancien : sans limite, l'endpoint
# devient un oracle permettant de le deviner par essais successifs. Limite
# par utilisateur plutot que par IP, l'appelant etant authentifie.
password_change_rate_limit = method_decorator(ratelimit(key='user', rate='5/h', method='POST', block=True), name='post')

# Rate limits for game actions
# Borne les tentatives : protège le brute-force de réponses, et surtout la
# triangulation de la cible d'une étape "Point à atteindre" par recherche
# dichotomique sur le résultat des soumissions (le masquage de la distance
# côté réponse ne suffit pas si le nombre d'essais est illimité).
answer_submit_rate_limit = method_decorator(ratelimit(key='user', rate='30/m', method='POST', block=True), name='post')
proximity_ping_rate_limit = method_decorator(ratelimit(key='user', rate='60/m', method='POST', block=True), name='post')
