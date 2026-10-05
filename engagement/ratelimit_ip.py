# engagement/ratelimit_ip.py
"""Résolution de l'IP cliente pour django-ratelimit.

Derrière nginx, Django ne voit dans REMOTE_ADDR que l'adresse du proxy
(127.0.0.1) : sans ce résolveur, toutes les limites key='ip' partagent un
unique compteur global. Concrètement, la limite de 5 connexions/heure
s'appliquait à l'ensemble des joueurs réunis, et n'importe qui pouvait
bloquer les connexions de tout le monde en épuisant le quota.
"""

import ipaddress


def client_ip(request):
    """IP réelle du client, telle que transmise par nginx.

    Seul X-Real-IP est pris en compte : nginx l'écrase systématiquement
    (`proxy_set_header X-Real-IP $remote_addr`), il n'est donc pas
    usurpable. X-Forwarded-For est volontairement ignoré — sa première
    valeur provient du client et permettrait de se forger une fausse IP
    pour contourner les limites, ou d'empoisonner le compteur d'un autre.

    Ne lève jamais : une adresse illisible ne doit pas transformer la page
    de connexion en erreur 500 (django_ratelimit._get_ip, lui, lève).
    """
    candidate = (
        request.META.get("HTTP_X_REAL_IP")
        or request.META.get("REMOTE_ADDR")
        or ""
    ).strip()

    try:
        ipaddress.ip_address(candidate)
    except ValueError:
        # Valeur neutre et valide : ces requêtes retombent dans un compteur
        # commun, soit le comportement d'avant ce correctif, plutôt qu'une
        # panne d'authentification.
        return "0.0.0.0"

    return candidate
