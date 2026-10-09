from django.conf import settings
from django.db import models
from django.utils import timezone
import secrets
import string

User = settings.AUTH_USER_MODEL

class PlaySession(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="play_sessions")
    escape = models.ForeignKey(
        'games.EscapeGame',
        on_delete=models.CASCADE,
        related_name="sessions",
    )
    started_at = models.DateTimeField(auto_now_add=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    current_step_index = models.PositiveIntegerField(default=0)
    hints_used = models.JSONField(default=dict, blank=True)
    # NOUVEAU : malus cumulé (mauvaises réponses + indices)
    penalty = models.IntegerField(default=0)  # augmente de 5 par mauvaise réponse + hint_penalty quand indice demandé
    answers = models.JSONField(default=dict, blank=True)
    # Temps de jeu cumulé en secondes (temps réellement passé à jouer)
    play_time_seconds = models.PositiveIntegerField(default=0)

    class Meta:
        unique_together = ('user', 'escape')

    def __str__(self):
        return f"Session({self.user}, {self.escape}, completed={self.completed_at is not None})"


class EscapeCompletion(models.Model):
    escape = models.OneToOneField('games.EscapeGame', on_delete=models.CASCADE, related_name='completion')
    code = models.CharField(max_length=24, default="0000")

    def __str__(self):
        return f"CompletionCode({self.escape_id}, {self.code})"


class Rating(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    # >>> change ici : related_name='ratings' + référence string au modèle cible
    escape = models.ForeignKey('games.EscapeGame', on_delete=models.CASCADE, related_name='ratings')

    stars = models.PositiveSmallIntegerField()
    comment = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["user","escape"], name="uniq_user_escape_rating"),
        ]

    def __str__(self):
        return f"{self.user} → {self.escape} ({self.stars})"


class PasswordResetToken(models.Model):
    """
    Model to store password reset tokens with 6-digit codes.
    Tokens expire after 15 minutes and can only be used once.
    """
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='password_reset_tokens'
    )
    code = models.CharField(max_length=6)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField(null=True, blank=True)
    used = models.BooleanField(default=False)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"PasswordResetToken({self.user.username}, {self.code}, used={self.used})"

    @classmethod
    def generate_code(cls):
        """Generate a random 6-digit code"""
        return ''.join(secrets.choice(string.digits) for _ in range(6))

    def is_valid(self):
        """Check if token is still valid (not used and not expired)"""
        return not self.used and timezone.now() < self.expires_at

    def save(self, *args, **kwargs):
        """Auto-generate code and expiration on creation"""
        if not self.pk:  # Only on creation
            if not self.code:
                self.code = self.generate_code()
            if not self.expires_at:
                self.expires_at = timezone.now() + timezone.timedelta(minutes=15)
        super().save(*args, **kwargs)


class UserProfile(models.Model):
    """
    Etat de verification d'email. Separe du User Django par defaut (pas de champ
    libre dessus sans swapper AUTH_USER_MODEL).
    """
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='profile'
    )
    email_verified = models.BooleanField(default=False)

    # Derniere utilisation du jeton d'API, pour l'expiration glissante
    # (cf. engagement/authentication.py). Porte ici plutot que sur un modele
    # dedie parce qu'un Token DRF est en relation un-a-un avec l'utilisateur :
    # par jeton et par compte reviennent au meme. A revoir si l'on autorise
    # un jour plusieurs jetons simultanes par compte (multi-appareils).
    token_last_used = models.DateTimeField(null=True, blank=True)

    def __str__(self):
        return f"UserProfile({self.user.username}, verified={self.email_verified})"


class EmailVerificationToken(models.Model):
    """
    Meme mecanique que PasswordResetToken : code a 6 chiffres, expire apres
    15 minutes, usage unique.
    """
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='email_verification_tokens'
    )
    code = models.CharField(max_length=6)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField(null=True, blank=True)
    used = models.BooleanField(default=False)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"EmailVerificationToken({self.user.username}, {self.code}, used={self.used})"

    @classmethod
    def generate_code(cls):
        """Generate a random 6-digit code"""
        return ''.join(secrets.choice(string.digits) for _ in range(6))

    def is_valid(self):
        """Check if token is still valid (not used and not expired)"""
        return not self.used and timezone.now() < self.expires_at

    def save(self, *args, **kwargs):
        """Auto-generate code and expiration on creation"""
        if not self.pk:  # Only on creation
            if not self.code:
                self.code = self.generate_code()
            if not self.expires_at:
                self.expires_at = timezone.now() + timezone.timedelta(minutes=15)
        super().save(*args, **kwargs)


class AccountDeletionRequest(models.Model):
    """Trace d'une demande de suppression de compte.

    La politique de confidentialité promet une suppression « sous 30
    jours ». Avant ce modèle, la demande ne laissait aucune trace en base :
    l'engagement ne tenait que par la vigilance de l'administrateur et le
    suivi reposait sur sa boîte mail. Impossible, dans ces conditions, de
    vérifier le délai ni de prouver qu'une demande avait été traitée.

    La demande référence l'utilisateur en `SET_NULL` : une fois le compte
    réellement supprimé un jour, la trace du traitement doit survivre - c'est
    précisément elle qui prouve qu'on a tenu l'engagement.
    """

    STATUT_EN_ATTENTE = "en_attente"
    STATUT_TRAITEE = "traitee"
    STATUT_ANNULEE = "annulee"
    STATUT_CHOICES = (
        (STATUT_EN_ATTENTE, "En attente"),
        (STATUT_TRAITEE, "Traitée"),
        (STATUT_ANNULEE, "Annulée"),
    )

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name="deletion_requests",
    )
    # Conservé en clair tant que la demande est en attente : c'est la seule
    # facon de retrouver le compte concerne si l'utilisateur a entretemps
    # change d'adresse. Efface au traitement (voir marquer_traitee).
    email_demande = models.EmailField(blank=True, default="")
    # Repris pour garder une trace lisible apres anonymisation, le username
    # etant alors remplace.
    username_au_moment_de_la_demande = models.CharField(
        max_length=150, blank=True, default="",
    )
    motif = models.TextField(blank=True, default="")

    statut = models.CharField(
        max_length=16, choices=STATUT_CHOICES, default=STATUT_EN_ATTENTE,
    )
    demandee_le = models.DateTimeField(auto_now_add=True)
    traitee_le = models.DateTimeField(null=True, blank=True)
    # Ce qui a reellement ete fait, pour pouvoir le justifier plus tard.
    detail_traitement = models.TextField(blank=True, default="")

    class Meta:
        ordering = ["-demandee_le"]
        verbose_name = "Demande de suppression de compte"
        verbose_name_plural = "Demandes de suppression de compte"

    def __str__(self):
        return (
            f"AccountDeletionRequest({self.username_au_moment_de_la_demande or '?'}, "
            f"{self.statut}, {self.demandee_le:%Y-%m-%d})"
        )

    @property
    def echeance(self):
        """Date limite des 30 jours promis par la politique de confidentialité."""
        return self.demandee_le + timezone.timedelta(days=30)

    @property
    def en_retard(self):
        return self.statut == self.STATUT_EN_ATTENTE and timezone.now() > self.echeance

    def marquer_traitee(self, detail=""):
        """Clôt la demande et efface l'adresse, qui n'a plus d'utilité.

        Garder l'email d'une personne dont on vient d'anonymiser le compte
        reviendrait à conserver la donnée qu'elle a demandé d'effacer.
        """
        self.statut = self.STATUT_TRAITEE
        self.traitee_le = timezone.now()
        self.detail_traitement = detail
        self.email_demande = ""
        self.motif = ""
        self.save(update_fields=[
            "statut", "traitee_le", "detail_traitement", "email_demande", "motif",
        ])
