# games/visibility.py
"""Qui a le droit de jouer quelle escape.

Règle unique, utilisée par tous les endpoints de session : le filtrage du
catalogue (games/api.py) masquait bien les escapes privées et non publiées,
mais rien ne protégeait l'accès direct par identifiant — il suffisait de
deviner un numéro pour jouer le brouillon ou l'escape privée d'un autre,
ou pour jouer un contenu refusé par la modération.
"""


def can_play(user, escape) -> bool:
    """Le propriétaire et les administrateurs accèdent à tout (test d'un
    brouillon, relecture de modération). Pour les autres, l'escape doit être
    publiée, et privée uniquement si l'utilisateur fait partie des invités.
    """
    if user is None or not getattr(user, "is_authenticated", False):
        return False

    if getattr(user, "is_staff", False) or getattr(user, "is_superuser", False):
        return True

    owner_id = getattr(escape, "owner_id", None)
    if owner_id is not None and owner_id == user.id:
        return True

    if getattr(escape, "status", "published") != "published":
        return False

    if getattr(escape, "is_private", False):
        return escape.allowed_users.filter(pk=user.pk).exists()

    return True
