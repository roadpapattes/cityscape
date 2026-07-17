# Migration de rattrapage : reproduit exactement ce qui a deja ete applique en
# prod hors-git (fichier untracked historique sur le serveur, meme nom, memes
# operations, pour que Django la reconnaisse comme deja appliquee et ne rejoue
# rien au prochain deploiement). Fork depuis 0009 comme en prod (en parallele de
# 0010_playsession_play_time_seconds) ; reconciliee par une migration de merge.
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('engagement', '0009_passwordresettoken'),
    ]

    operations = [
        migrations.AlterModelOptions(
            name='passwordresettoken',
            options={'ordering': ['-created_at']},
        ),
        migrations.AddField(
            model_name='passwordresettoken',
            name='expires_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
    ]
