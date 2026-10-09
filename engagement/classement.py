# -*- coding: utf-8 -*-
"""Classement des meilleurs temps sur une escape.

Un classement par escape, et non un palmares general : tout le monde y a
resolu les memes enigmes, donc les temps sont comparables. Des escapes de
longueurs differentes ne le seraient pas sans normalisation.

Le rang est determine par le **temps mesure cote serveur** plus les
**penalites** - convention des escape games, et seule facon de distinguer
celui qui a resolu proprement de celui qui a force les reponses au hasard
en consommant les indices.

La mesure client (`play_time_seconds`) n'est jamais utilisee ici : elle est
declaree par l'application et donc sous-declarable. Voir
engagement/chronometrage.py.

Interaction avec la suppression de compte, a connaitre : l'anonymisation
supprime les sessions de jeu (voir engagement/anonymisation.py). Les temps
d'un joueur qui fait supprimer son compte **disparaissent donc du
classement**, et la place se libere. C'est voulu - l'historique de jeu est
une donnee personnelle, et la page de suppression annonce explicitement sa
perte - mais cela signifie qu'un record peut s'effacer.
"""

from django.db.models import ExpressionWrapper, F, IntegerField, Q, Value
from django.db.models.functions import Greatest

from .anonymisation import est_deja_anonymise
from .models import PlaySession

# Les penalites sont stockees en minutes, les temps en secondes.
SECONDES_PAR_MINUTE = 60

# Nombre d'entrees renvoyees par defaut, et plafond absolu quelle que soit la
# demande : le classement est lu depuis un telephone, et rien ne justifie de
# faire voyager des milliers de lignes.
LIMITE_DEFAUT = 20
LIMITE_MAX = 100

LIBELLE_COMPTE_ANONYMISE = "Compte supprimé"


def _expression_score():
    """temps mesure + penalites, en secondes.

    `Greatest(penalty, 0)` est defensif : les deux chemins qui accumulent une
    penalite sont gardes par `> 0`, donc elle ne peut pas devenir negative
    aujourd'hui. Mais ni `hint_penalty` ni `wrong_answer_penalty` n'est
    valide a la creation d'une etape, et une penalite negative ameliorerait
    un rang - autant que le classement ne depende pas de cette garde-la.
    """
    return ExpressionWrapper(
        F("server_play_seconds")
        + Greatest(F("penalty"), Value(0)) * SECONDES_PAR_MINUTE,
        output_field=IntegerField(),
    )


def sessions_classables(escape):
    """Les sessions qui ont le droit de figurer au classement.

    Trois conditions. Terminee, evidemment. Et `server_play_seconds > 0`,
    qui ecarte les sessions anterieures a la mise en place du chronometrage
    serveur : elles valent 0 et apparaitraient en tete avec un temps nul,
    ce qui serait a la fois faux et decourageant.
    """
    return (
        PlaySession.objects.filter(
            escape=escape,
            completed_at__isnull=False,
            server_play_seconds__gt=0,
        )
        .annotate(score=_expression_score())
        .select_related("user")
        # L'ordre doit etre total, sinon deux lectures peuvent renvoyer des
        # rangs differents a score egal. A egalite, le premier a avoir
        # termine passe devant.
        .order_by("score", "completed_at", "id")
    )


def nom_affiche(user):
    """Le nom a afficher pour un joueur classe.

    Le cas anonymise est un filet de securite qui ne doit pas se declencher
    aujourd'hui : l'anonymisation supprimant les sessions de jeu, un compte
    anonymise n'a plus aucune session classable. La garde reste parce que
    l'invariant - ne jamais nommer un compte anonymise - doit tenir meme si
    cette regle change, et parce qu'un classement est public pour tous les
    joueurs ayant acces a l'escape. Elle est couverte par un test unitaire,
    faute de scenario qui l'atteigne.
    """
    if est_deja_anonymise(user):
        return LIBELLE_COMPTE_ANONYMISE
    return user.username


def _entree(sess, rang):
    """Une ligne de classement.

    L'identifiant de l'utilisateur n'y figure pas : le classement est lisible
    par tous les joueurs ayant acces a l'escape, et un identifiant numerique
    stable est une prise pour correler des comptes entre eux.
    """
    penalite_minutes = max(0, int(sess.penalty or 0))
    return {
        "rang": rang,
        "joueur": nom_affiche(sess.user),
        "temps_s": int(sess.server_play_seconds or 0),
        "penalite_s": penalite_minutes * SECONDES_PAR_MINUTE,
        "score_s": int(sess.score),
        "termine_le": sess.completed_at,
    }


def rang_de(escape, sess):
    """Rang d'une session donnee, y compris hors du haut du tableau.

    Compte les sessions qui la precedent selon le meme ordre total que
    `sessions_classables`, plutot que de parcourir le classement entier.
    """
    devant = sessions_classables(escape).filter(
        Q(score__lt=sess.score)
        | Q(score=sess.score, completed_at__lt=sess.completed_at)
        | Q(score=sess.score, completed_at=sess.completed_at, id__lt=sess.id)
    )
    return devant.count() + 1


def classement_escape(escape, limite=LIMITE_DEFAUT, pour_utilisateur=None):
    """Le haut du classement, et la place du joueur qui consulte.

    `moi` est renseigne meme si le joueur est loin du haut du tableau :
    c'est l'information qui l'interesse, et la lui faire chercher dans une
    liste tronquee n'aurait pas de sens. Il vaut None s'il n'a pas encore
    termine l'escape.
    """
    limite = max(1, min(int(limite or LIMITE_DEFAUT), LIMITE_MAX))

    qs = sessions_classables(escape)
    entrees = [_entree(sess, rang) for rang, sess in enumerate(qs[:limite], start=1)]

    moi = None
    if pour_utilisateur is not None and pour_utilisateur.is_authenticated:
        # unique_together (user, escape) : au plus une session par joueur.
        ma_session = qs.filter(user=pour_utilisateur).first()
        if ma_session is not None:
            moi = _entree(ma_session, rang_de(escape, ma_session))

    return {
        "escape_id": escape.id,
        "total_classes": qs.count(),
        "entrees": entrees,
        "moi": moi,
    }
