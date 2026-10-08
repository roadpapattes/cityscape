# engagement/authentication.py
"""Expiration glissante des jetons d'API.

Un jeton DRF n'expire jamais : une fois derobe, il donne un acces
permanent. On lui applique donc une duree de vie glissante — 90 jours
depuis la derniere utilisation, et non depuis la creation, pour qu'un
joueur regulier ne soit jamais deconnecte, tandis qu'un jeton oublie
ou vole finit par cesser de fonctionner.
"""

from datetime import timedelta

from django.conf import settings
from django.utils import timezone
from rest_framework.authentication import TokenAuthentication
from rest_framework.exceptions import AuthenticationFailed

from .models import UserProfile


def _duree_de_vie():
    return timedelta(days=getattr(settings, "AUTH_TOKEN_TTL_DAYS", 90))


def _intervalle_rafraichissement():
    """A quelle frequence on reporte la date de derniere utilisation.

    Sans ce palier, chaque requete authentifiee declencherait une ecriture
    en base. Une precision a la journee suffit amplement pour une fenetre
    de 90 jours, et ramene le cout a une ecriture par joueur et par jour.
    """
    return timedelta(hours=getattr(settings, "AUTH_TOKEN_TOUCH_HOURS", 24))


class ExpiringTokenAuthentication(TokenAuthentication):
    def authenticate_credentials(self, key):
        user, token = super().authenticate_credentials(key)

        profil, _ = UserProfile.objects.get_or_create(user=user)
        maintenant = timezone.now()

        if profil.token_last_used is None:
            # Jeton anterieur a la mise en place de l'expiration : on demarre
            # sa fenetre maintenant plutot que de se fier a sa date de
            # creation, sinon le deploiement deconnecterait d'un coup tous
            # les joueurs dont le jeton a plus de 90 jours.
            profil.token_last_used = maintenant
            profil.save(update_fields=["token_last_used"])
            return user, token

        if maintenant - profil.token_last_used > _duree_de_vie():
            # Le jeton est supprime : inutile de laisser trainer un secret
            # qui ne sert plus, et le client sera renvoye vers la connexion
            # par le traitement du 401.
            token.delete()
            raise AuthenticationFailed(
                "Session expirée. Veuillez vous reconnecter."
            )

        if maintenant - profil.token_last_used > _intervalle_rafraichissement():
            profil.token_last_used = maintenant
            profil.save(update_fields=["token_last_used"])

        return user, token
