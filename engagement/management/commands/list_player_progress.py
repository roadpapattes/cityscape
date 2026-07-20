from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from django.utils import timezone

from engagement.models import PlaySession

User = get_user_model()


class Command(BaseCommand):
    help = "Affiche, par joueur, la liste de ses escapes en cours (non terminés)."

    def add_arguments(self, parser):
        parser.add_argument(
            "--username",
            help="N'afficher qu'un seul joueur (username exact).",
        )

    def handle(self, *args, **opts):
        sessions = (
            PlaySession.objects
            .filter(completed_at__isnull=True)
            .select_related("user", "escape")
            .order_by("user__username", "-started_at")
        )

        username = opts.get("username")
        if username:
            sessions = sessions.filter(user__username=username)

        players = {}
        for sess in sessions:
            players.setdefault(sess.user, []).append(sess)

        if not players:
            self.stdout.write("Aucun escape en cours.")
            return

        for user, user_sessions in players.items():
            self.stdout.write(f"\n{user.username} ({user.email or 'pas d’email'})")
            for sess in user_sessions:
                total = sess.escape.creator_steps.count()
                idx = sess.current_step_index or 0
                progress = f"{idx}/{total} ({round(idx / total * 100)}%)" if total else f"{idx}"
                started = timezone.localtime(sess.started_at).strftime("%Y-%m-%d %H:%M")
                minutes = (sess.play_time_seconds or 0) // 60
                self.stdout.write(
                    f"  - {sess.escape.title:<40} étape {progress:<14} depuis {started}   {minutes} min de jeu"
                )
