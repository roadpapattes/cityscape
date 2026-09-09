from django.core.management.base import BaseCommand

from monetization.funnel import conversion_report


class Command(BaseCommand):
    help = (
        "Taux de conversion du paywall simulé (lancement gratuit instrumenté), "
        "par escape payante — le signal de bascule décrit dans la note de "
        "cadrage monétisation, à préférer à un simple comptage de joueurs."
    )

    def handle(self, *args, **opts):
        rows = conversion_report()

        if not rows:
            self.stdout.write("Aucune impression de paywall enregistrée pour l'instant.")
            return

        total_impressions = sum(r.impressions for r in rows)
        total_unlocks = sum(r.unlocks for r in rows)
        global_rate = (total_unlocks / total_impressions) if total_impressions else 0.0

        self.stdout.write(
            f"{'Escape':<45} {'Prix':>8} {'Vues':>6} {'Débloquées':>11} {'Taux':>8}"
        )
        self.stdout.write("-" * 82)
        for r in rows:
            price = f"{r.price_cents / 100:.2f}€"
            self.stdout.write(
                f"{r.title[:45]:<45} {price:>8} {r.impressions:>6} {r.unlocks:>11} "
                f"{r.conversion_rate * 100:>7.1f}%"
            )

        self.stdout.write("-" * 82)
        self.stdout.write(
            f"{'TOTAL':<45} {'':>8} {total_impressions:>6} {total_unlocks:>11} "
            f"{global_rate * 100:>7.1f}%"
        )
