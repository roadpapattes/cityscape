# -*- coding: utf-8 -*-
"""Anonymisation d'un compte, en reponse a une demande de suppression.

Pourquoi anonymiser plutot que supprimer la ligne utilisateur : une
suppression seche fait cascader la base. `Rating.user` est en CASCADE, donc
les notes laissees sur les escapes disparaitraient - alors qu'elles ont une
valeur pour les autres joueurs, independamment de leur auteur. `Purchase` et
`CreatorLedgerEntry` le sont aussi, et detruire les pieces d'une transaction
entre en conflit avec l'obligation de conservation des documents comptables.

On garde donc la ligne et on efface ce qui identifie la personne. Rien ne
cascade, et ce qui doit survivre survit par construction.

La fonction est idempotente : la rejouer sur un compte deja anonymise ne
fait rien de plus et ne leve pas d'erreur.
"""

from django.contrib.auth import get_user_model
from django.db import transaction
from rest_framework.authtoken.models import Token

from games.models import EscapeGame

from .models import (
    EmailVerificationToken,
    PasswordResetToken,
    PlaySession,
    Rating,
    UserProfile,
)

User = get_user_model()

# Prefixe du username de remplacement. Sert aussi a reconnaitre un compte
# deja anonymise, d'ou l'importance de ne pas le changer a la legere.
PREFIXE_ANONYME = "compte-supprime-"


def username_anonyme(user_id):
    return f"{PREFIXE_ANONYME}{user_id}"


def est_deja_anonymise(user):
    return user.username.startswith(PREFIXE_ANONYME)


@transaction.atomic
def anonymiser_compte(user, simulation=False):
    """Efface les donnees personnelles du compte, en conservant ce qui a une
    valeur pour les tiers ou une obligation de conservation.

    Renvoie un dictionnaire decrivant ce qui a ete fait (ou ce qui le serait,
    en simulation), destine a etre consigne dans la demande de suppression.

    `simulation=True` ne modifie rien : la transaction est de toute facon
    annulee par l'appelant, mais la fonction s'abstient aussi d'ecrire, pour
    que le compte des objets concernes reste lisible.
    """
    rapport = {
        "user_id": user.id,
        "username_avant": user.username,
        "deja_anonymise": est_deja_anonymise(user),
        "simulation": bool(simulation),
    }

    # --- Ce qui est supprime : purement personnel, aucune valeur pour un tiers
    sessions = PlaySession.objects.filter(user=user)
    # `answers` contient le texte tape par le joueur, et l'ensemble constitue
    # un historique de comportement : rien a conserver pour autrui, les
    # agregats d'une escape vivant sur EscapeCompletion, rattache a l'escape.
    rapport["sessions_supprimees"] = sessions.count()

    jetons_mdp = PasswordResetToken.objects.filter(user=user)
    jetons_email = EmailVerificationToken.objects.filter(user=user)
    rapport["jetons_reinitialisation_supprimes"] = jetons_mdp.count()
    rapport["jetons_verification_supprimes"] = jetons_email.count()

    jetons_api = Token.objects.filter(user=user)
    rapport["jetons_api_revoques"] = jetons_api.count()

    # Figurer sur la liste blanche d'une escape privee est un lien nominatif
    # vers la personne : on l'en retire.
    escapes_privees = EscapeGame.objects.filter(allowed_users=user)
    rapport["acces_prives_retires"] = escapes_privees.count()

    # --- Ce qui est conserve, mais depouille de son texte libre
    notes = Rating.objects.filter(user=user)
    rapport["notes_conservees"] = notes.count()
    rapport["commentaires_effaces"] = notes.exclude(comment="").count()

    # --- Ce qui est conserve tel quel
    rapport["escapes_conservees"] = EscapeGame.objects.filter(owner=user).count()
    rapport["escapes_publiees_conservees"] = EscapeGame.objects.filter(
        owner=user, status="published",
    ).count()

    if simulation:
        return rapport

    sessions.delete()
    jetons_mdp.delete()
    jetons_email.delete()
    jetons_api.delete()
    for escape in escapes_privees:
        escape.allowed_users.remove(user)

    # Les etoiles restent, le commentaire part : c'est du texte libre ecrit
    # par la personne, qui peut l'identifier.
    notes.update(comment="")

    profil, _ = UserProfile.objects.get_or_create(user=user)
    profil.email_verified = False
    profil.token_last_used = None
    profil.save(update_fields=["email_verified", "token_last_used"])

    user.username = username_anonyme(user.id)
    user.email = ""
    user.first_name = ""
    user.last_name = ""
    # Desactive pour que plus aucune authentification ne soit possible, et
    # prive de tout privilege au cas ou le compte en aurait eu.
    user.is_active = False
    user.is_staff = False
    user.is_superuser = False
    user.set_unusable_password()
    user.save()

    rapport["username_apres"] = user.username
    return rapport


def resume_rapport(rapport):
    """Rend le rapport lisible dans un email ou un champ texte."""
    lignes = [
        f"compte #{rapport['user_id']} ({rapport['username_avant']})"
        f" -> {rapport.get('username_apres', username_anonyme(rapport['user_id']))}",
        f"sessions de jeu supprimees        : {rapport['sessions_supprimees']}",
        f"jetons API revoques               : {rapport['jetons_api_revoques']}",
        f"jetons de reinitialisation        : {rapport['jetons_reinitialisation_supprimes']}",
        f"jetons de verification d'email    : {rapport['jetons_verification_supprimes']}",
        f"acces a des escapes privees       : {rapport['acces_prives_retires']}",
        f"notes conservees (etoiles)        : {rapport['notes_conservees']}",
        f"commentaires effaces              : {rapport['commentaires_effaces']}",
        f"escapes conservees                : {rapport['escapes_conservees']}"
        f" (dont publiees : {rapport['escapes_publiees_conservees']})",
    ]
    if rapport["deja_anonymise"]:
        lignes.insert(1, "ATTENTION : ce compte etait deja anonymise")
    return "\n".join(lignes)
