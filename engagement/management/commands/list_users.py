from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from django.db.models import Count

User = get_user_model()

ROLE_CHOICES = ("superadmin", "staff", "createur", "joueur")


class Command(BaseCommand):
    help = "Affiche la liste des utilisateurs avec leur profil (rôle, statut, vérification email)."

    def add_arguments(self, parser):
        parser.add_argument(
            "--role",
            choices=ROLE_CHOICES,
            help="Ne montrer que les utilisateurs de ce rôle.",
        )

    def _role(self, user):
        if user.is_superuser:
            return "superadmin"
        if user.is_staff:
            return "staff"
        if user._escapes_count > 0:
            return "createur"
        return "joueur"

    def handle(self, *args, **opts):
        users = (
            User.objects
            .select_related("profile")
            .annotate(_escapes_count=Count("created_escapes", distinct=True))
            .order_by("username")
        )

        role_filter = opts.get("role")

        header = f"{'username':<20} {'email':<30} {'rôle':<12} {'actif':<7} {'email vérifié':<14} {'inscrit le'}"
        self.stdout.write(header)
        self.stdout.write("-" * len(header))

        for user in users:
            role = self._role(user)
            if role_filter and role != role_filter:
                continue

            profile = getattr(user, "profile", None)
            email_verified = "oui" if profile and profile.email_verified else "non"
            actif = "oui" if user.is_active else "non"
            inscrit = user.date_joined.strftime("%Y-%m-%d")

            self.stdout.write(
                f"{user.username:<20} {user.email or '-':<30} {role:<12} {actif:<7} {email_verified:<14} {inscrit}"
            )
