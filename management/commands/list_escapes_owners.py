from django.core.management.base import BaseCommand
from django.apps import apps
from django.contrib.auth import get_user_model

class Command(BaseCommand):
    help = "Affiche id, titre, propriétaire(s), statut des escapes"

    def add_arguments(self, parser):
        parser.add_argument("--model", default="escapes.EscapeGame",
                            help="AppLabel.ModelName (défaut: escapes.EscapeGame)")

    def handle(self, *args, **opts):
        label = opts["model"]
        M = apps.get_model(label)
        User = get_user_model()

        fks = [f for f in M._meta.get_fields() if f.is_relation and not f.many_to_many and f.related_model == User]
        m2m = [f for f in M._meta.get_fields() if f.is_relation and f.many_to_many and f.related_model == User]

        qs = M.objects.all().select_related(*[f.name for f in fks]).prefetch_related(*[f.name for f in m2m])

        def uname(u):
            return getattr(u, "username", None) or getattr(u, "email", None) or (str(u) if u else None)

        for e in qs:
            owners = []
            for f in fks:
                u = getattr(e, f.name, None)
                if u:
                    owners.append(uname(u))
            if not owners and m2m:
                users = getattr(e, m2m[0].name).all()[:3]
                owners = [uname(u) for u in users if u]
            title = getattr(e, "title", "") or getattr(e, "name", "")
            status = getattr(e, "status", "")
            owners_str = ", ".join([o for o in owners if o]) or "-"
            self.stdout.write(f"{e.id}\t{title}\t{owners_str}\t{status}")
