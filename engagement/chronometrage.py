# -*- coding: utf-8 -*-
"""Mesure du temps de jeu cote serveur.

Le temps de jeu etait entierement declare par le client : l'app envoyait un
nombre de secondes, le serveur l'additionnait. Pratique pour afficher un
temps actif - l'app seule sait quand le joueur a mis le jeu de cote - mais
inutilisable pour un classement, et pas a cause de l'inflation : personne ne
cherche a paraitre lent. Le risque est la **sous-declaration**. Il suffit de
ne jamais envoyer le temps, ou d'envoyer une seconde, pour terminer une
escape en un temps imbattable.

Deux mesures ici, qui se completent :

1. `enregistrer_activite` : le serveur horodate lui-meme chaque action du
   joueur et cumule les ecarts entre deux actions consecutives. Un ecart
   superieur a ECART_ACTIVITE_MAX est tenu pour une pause et n'est pas
   compte. Le resultat est un temps actif qu'un client ne peut ni gonfler
   (les ecarts sont plafonnes et lus sur l'horloge du serveur) ni retrecir
   (il faut interagir pour jouer). C'est cette valeur qui devra servir de
   base a un classement.

2. `cumuler_temps_client` : le temps declare reste enregistre pour
   l'affichage, mais borne par l'ecoule reel depuis le debut de la session.
   On ne peut pas avoir joue deux heures dans une fenetre de dix minutes.
"""

from django.utils import timezone

# Au-dela de cet ecart entre deux actions, on considere que le joueur avait
# mis le jeu de cote. Cinq minutes : assez long pour chercher sur place et
# reflechir devant une enigme, assez court pour ne pas compter une pause
# dejeuner comme du temps de jeu.
ECART_ACTIVITE_MAX = 300

# En dessous, on n'ecrit pas en base : les pings de proximite peuvent arriver
# jusqu'a soixante fois par minute, et un enregistrement par ping serait du
# gaspillage. L'ecart n'est pas perdu pour autant - on laisse aussi
# `last_activity_at` en place, donc il sera compte au prochain evenement
# retenu.
ECART_MIN_ECRITURE = 5


def ecoule_serveur(sess, maintenant=None):
    """Temps ecoule au mur depuis le debut de la session, mesure par le
    serveur. Inclut les pauses : c'est un plafond, pas un temps de jeu."""
    maintenant = maintenant or timezone.now()
    fin = sess.completed_at or maintenant
    return max(0, int((fin - sess.started_at).total_seconds()))


def enregistrer_activite(sess, maintenant=None):
    """Horodate une action du joueur et cumule le temps actif cote serveur.

    Renvoie le nombre de secondes ajoutees (0 si l'ecart etait trop court
    pour etre enregistre, ou trop long pour compter comme du jeu).
    """
    maintenant = maintenant or timezone.now()

    # A la premiere action, l'origine est le debut de la session : le temps
    # passe entre le lancement et la premiere reponse est du jeu.
    precedent = sess.last_activity_at or sess.started_at
    if precedent is None:
        sess.last_activity_at = maintenant
        sess.save(update_fields=["last_activity_at"])
        return 0

    ecart = (maintenant - precedent).total_seconds()

    if ecart < ECART_MIN_ECRITURE:
        # Rien n'est ecrit et `last_activity_at` n'avance pas, donc l'ecart
        # sera compte au prochain evenement retenu : on economise une
        # ecriture sans perdre de temps de jeu.
        return 0

    # Arrondi et non troncature : tronquer perdrait jusqu'a une seconde a
    # chaque action, soit un biais systematique a la baisse - exactement ce
    # que ce chronometrage cherche a empecher.
    ajout = round(ecart) if ecart <= ECART_ACTIVITE_MAX else 0
    if ajout:
        sess.server_play_seconds = int(sess.server_play_seconds or 0) + ajout

    sess.last_activity_at = maintenant
    sess.save(update_fields=["server_play_seconds", "last_activity_at"])
    return ajout


def cumuler_temps_client(sess, secondes_declarees, maintenant=None):
    """Ajoute au temps affiche les secondes declarees par le client, sans
    jamais depasser l'ecoule reel mesure par le serveur.

    Renvoie le nouveau total. Une valeur absente, negative ou illisible est
    traitee comme zero : l'appelant n'a pas a la valider.
    """
    try:
        declare = int(secondes_declarees)
    except (TypeError, ValueError):
        declare = 0
    if declare < 0:
        declare = 0

    total = int(sess.play_time_seconds or 0) + declare
    plafond = ecoule_serveur(sess, maintenant=maintenant)

    nouveau = min(total, plafond)
    if nouveau != int(sess.play_time_seconds or 0):
        sess.play_time_seconds = nouveau
        sess.save(update_fields=["play_time_seconds"])
    return nouveau
