# Generated for the "Point à atteindre" (location) puzzle validation type.

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('games', '0023_escapegame_audio_url'),
    ]

    operations = [
        migrations.AddField(
            model_name='gamestep',
            name='radius_m',
            field=models.PositiveIntegerField(
                default=30,
                help_text='Rayon de validation en mètres (type « Point à atteindre »). Plancher conseillé : 20 m.',
            ),
        ),
        migrations.AddField(
            model_name='gamestep',
            name='reveal_mode',
            field=models.CharField(
                choices=[
                    ('guided', 'Guidé (point affiché sur la carte)'),
                    ('hotcold', 'Chaud / froid (jauge de proximité)'),
                    ('blind', 'Aveugle (aucune aide)'),
                ],
                default='guided',
                help_text='Comment le joueur est guidé vers le point (type « Point à atteindre »).',
                max_length=10,
            ),
        ),
        migrations.AddField(
            model_name='gamestep',
            name='auto_validate',
            field=models.BooleanField(
                default=True,
                help_text="Valide automatiquement l'étape à l'entrée dans le rayon. Si désactivé, un bouton de validation est proposé au joueur.",
            ),
        ),
        migrations.AlterField(
            model_name='gamestep',
            name='answer_type',
            field=models.CharField(
                choices=[
                    ('text', 'Texte libre'),
                    ('mcq', 'Choix multiple'),
                    ('numeric', 'Numeric'),
                    ('matching', 'Association'),
                    ('cesar', 'Code de César'),
                    ('narration', 'Narration'),
                    ('location', 'Point à atteindre'),
                ],
                default='text',
                max_length=10,
            ),
        ),
    ]
