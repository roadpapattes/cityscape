# Purge des positions GPS conservees dans l'historique des sessions.
#
# Les etapes « Point a atteindre » enregistraient la position exacte du
# joueur, horodatee et sans limite de duree, alors qu'aucun code ne la
# lisait. Cesser de la collecter ne suffit pas : il faut aussi effacer ce
# qui a deja ete accumule.

from django.db import migrations


def purger_positions(apps, schema_editor):
    PlaySession = apps.get_model("engagement", "PlaySession")

    sessions_modifiees = []
    for session in PlaySession.objects.exclude(answers={}).iterator():
        reponses = session.answers or {}
        touchee = False

        for entree in reponses.values():
            if not isinstance(entree, dict):
                continue
            if entree.pop("latitude", None) is not None:
                touchee = True
            if entree.pop("longitude", None) is not None:
                touchee = True

        if touchee:
            session.answers = reponses
            sessions_modifiees.append(session)

    if sessions_modifiees:
        PlaySession.objects.bulk_update(sessions_modifiees, ["answers"], batch_size=200)


def pas_de_retour_en_arriere(apps, schema_editor):
    """Irreversible par nature : des donnees personnelles effacees ne se
    reconstituent pas, et c'est precisement l'objectif."""
    pass


class Migration(migrations.Migration):

    dependencies = [
        ("engagement", "0014_userprofile_token_last_used"),
    ]

    operations = [
        migrations.RunPython(purger_positions, pas_de_retour_en_arriere),
    ]
