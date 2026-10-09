# -*- coding: utf-8 -*-
"""Traite une demande de suppression de compte en anonymisant le compte.

Volontairement une commande d'administration, et non une action en libre
service dans l'application : l'operation est irreversible, et un bouton
accessible avec un jeton derobe donnerait a un attaquant le moyen de
detruire le compte de sa victime. Le delai de 30 jours annonce par la
politique de confidentialite laisse au titulaire le temps de reagir a
l'email de confirmation.
"""

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from engagement.anonymisation import anonymiser_compte, est_deja_anonymise, resume_rapport
from engagement.models import AccountDeletionRequest

User = get_user_model()


class Command(BaseCommand):
    help = (
        "Anonymise un compte : efface les donnees personnelles, conserve les "
        "notes (etoiles), les escapes et les traces de transaction."
    )

    def add_arguments(self, parser):
        cible = parser.add_mutually_exclusive_group(required=True)
        cible.add_argument("--username", help="Nom d'utilisateur du compte a anonymiser.")
        cible.add_argument("--id", type=int, help="Identifiant du compte a anonymiser.")
        cible.add_argument(
            "--email", help="Adresse email du compte a anonymiser.",
        )
        parser.add_argument(
            "--simulation", action="store_true",
            help="N'ecrit rien : affiche ce qui serait fait.",
        )
        parser.add_argument(
            "--confirmer", action="store_true",
            help="Requis pour ecrire reellement (sans quoi la commande simule).",
        )

    def _trouver(self, opts):
        if opts.get("username"):
            critere, valeur = "username", opts["username"]
            qs = User.objects.filter(username=valeur)
        elif opts.get("id"):
            critere, valeur = "id", opts["id"]
            qs = User.objects.filter(id=valeur)
        else:
            critere, valeur = "email", (opts["email"] or "").strip().lower()
            # Une adresse peut en theorie etre portee par plusieurs comptes :
            # mieux vaut refuser que d'en anonymiser un au hasard.
            qs = User.objects.filter(email__iexact=valeur)

        nb = qs.count()
        if nb == 0:
            raise CommandError(f"Aucun compte avec {critere} = {valeur!r}.")
        if nb > 1:
            noms = ", ".join(qs.values_list("username", flat=True))
            raise CommandError(
                f"{nb} comptes avec {critere} = {valeur!r} ({noms}). "
                "Utiliser --id pour lever l'ambiguite."
            )
        return qs.get()

    def handle(self, *args, **opts):
        user = self._trouver(opts)

        # Par defaut on simule : --confirmer est le garde-fou contre une
        # commande lancee trop vite sur le mauvais compte.
        simulation = opts["simulation"] or not opts["confirmer"]

        if est_deja_anonymise(user):
            self.stdout.write(self.style.WARNING(
                f"Le compte #{user.id} ({user.username}) est deja anonymise."
            ))

        self.stdout.write(f"Compte cible : #{user.id} {user.username} <{user.email or '-'}>")

        if simulation:
            # Pas d'ecriture du tout, et on annule malgre tout la transaction
            # par precaution si un jour la fonction venait a ecrire.
            with transaction.atomic():
                rapport = anonymiser_compte(user, simulation=True)
                transaction.set_rollback(True)
            self.stdout.write("")
            self.stdout.write(resume_rapport(rapport))
            self.stdout.write("")
            self.stdout.write(self.style.WARNING(
                "SIMULATION : rien n'a ete ecrit. Relancer avec --confirmer pour appliquer."
            ))
            return

        rapport = anonymiser_compte(user)
        resume = resume_rapport(rapport)

        # Cloture la demande la plus ancienne encore en attente, s'il y en a
        # une : c'est elle qui porte la preuve du respect du delai.
        demande = (
            AccountDeletionRequest.objects
            .filter(user=user, statut=AccountDeletionRequest.STATUT_EN_ATTENTE)
            .order_by("demandee_le")
            .first()
        )
        if demande:
            demande.marquer_traitee(detail=resume)
            self.stdout.write(
                f"Demande #{demande.id} du {demande.demandee_le:%Y-%m-%d} marquee traitee."
            )
        else:
            self.stdout.write(self.style.WARNING(
                "Aucune demande en attente pour ce compte : anonymisation "
                "effectuee, mais sans trace de demande prealable."
            ))

        self.stdout.write("")
        self.stdout.write(resume)
        self.stdout.write("")
        self.stdout.write(self.style.SUCCESS("Anonymisation effectuee."))
