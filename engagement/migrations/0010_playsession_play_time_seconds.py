# Generated migration for play_time_seconds field

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('engagement', '0009_passwordresettoken'),
    ]

    operations = [
        migrations.AddField(
            model_name='playsession',
            name='play_time_seconds',
            field=models.PositiveIntegerField(default=0),
        ),
    ]
