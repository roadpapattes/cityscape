from django.utils import timezone
from django.contrib import admin
from django.utils.html import format_html
from django.urls import reverse
from django.contrib.auth import get_user_model
from .models import (
    PlaySession, EscapeCompletion, Rating, PasswordResetToken, UserProfile,
    EmailVerificationToken, AccountDeletionRequest,
)

User = get_user_model()


@admin.register(PlaySession)
class PlaySessionAdmin(admin.ModelAdmin):
    list_display = [
        'id',
        'user_link',
        'escape_link',
        'started_at',
        'completion_badge',
        'current_step',
        'penalty_display',
        'duration',
        'temps_compare',
    ]
    list_filter = ['started_at', 'completed_at']
    search_fields = ['user__username', 'user__email', 'escape__title']
    readonly_fields = ['started_at', 'duration_display', 'answers_display', 'hints_used_display']

    fieldsets = (
        ('Session', {
            'fields': ('user', 'escape', 'started_at', 'completed_at', 'duration_display')
        }),
        ('Progression', {
            'fields': ('current_step_index', 'penalty', 'answers_display', 'hints_used_display')
        }),
        ('Temps de jeu', {
            'fields': ('play_time_seconds', 'server_play_seconds', 'last_activity_at'),
            'description': (
                "play_time_seconds est declare par le client (borne a l'ecoule reel, "
                "mais sous-declarable) ; server_play_seconds est mesure par le serveur "
                "et c'est lui qui devra servir de base a un classement."
            ),
        }),
    )

    def temps_compare(self, obj):
        """Client contre serveur. Un temps client tres inferieur au temps
        mesure signale une sous-declaration : c'est tout l'interet d'avoir
        les deux cote a cote."""
        client = int(obj.play_time_seconds or 0)
        serveur = int(obj.server_play_seconds or 0)
        couleur = "#dc3545" if serveur > 0 and client < serveur / 2 else "#6c757d"
        return format_html(
            '<span style="color: {};">client {} s / serveur {} s</span>',
            couleur, client, serveur,
        )
    temps_compare.short_description = "Temps (client / serveur)"

    def user_link(self, obj):
        url = reverse('admin:auth_user_change', args=[obj.user.id])
        return format_html('<a href="{}">{}</a>', url, obj.user.username)
    user_link.short_description = 'Utilisateur'

    def escape_link(self, obj):
        url = reverse('admin:games_escapegame_change', args=[obj.escape.id])
        return format_html('<a href="{}">{}</a>', url, obj.escape.title)
    escape_link.short_description = 'Escape'

    def completion_badge(self, obj):
        if obj.completed_at:
            return format_html(
                '<span style="background-color: #28a745; color: white; padding: 3px 10px; '
                'border-radius: 3px; font-weight: bold;">✅ Terminé</span>'
            )
        return format_html(
            '<span style="background-color: #ffc107; color: black; padding: 3px 10px; '
            'border-radius: 3px; font-weight: bold;">⏳ En cours</span>'
        )
    completion_badge.short_description = 'Statut'

    def current_step(self, obj):
        return f"Étape {obj.current_step_index + 1}"
    current_step.short_description = 'Étape actuelle'

    def penalty_display(self, obj):
        if obj.penalty > 0:
            return format_html(
                '<span style="color: red; font-weight: bold;">+{} min</span>',
                obj.penalty
            )
        return '0 min'
    penalty_display.short_description = 'Pénalité'

    def duration(self, obj):
        if obj.completed_at:
            delta = obj.completed_at - obj.started_at
            minutes = int(delta.total_seconds() / 60)
            return f"{minutes} min"
        return "En cours"
    duration.short_description = 'Durée'

    def duration_display(self, obj):
        if obj.completed_at:
            delta = obj.completed_at - obj.started_at
            minutes = int(delta.total_seconds() / 60)
            return f"{minutes} minutes"
        return "Session en cours"
    duration_display.short_description = 'Durée totale'

    def answers_display(self, obj):
        if obj.answers:
            items = [f"Étape {k}: {v}" for k, v in obj.answers.items()]
            return format_html('<br>'.join(items))
        return "Aucune réponse"
    answers_display.short_description = 'Réponses'

    def hints_used_display(self, obj):
        if obj.hints_used:
            items = [f"Étape {k}: {v} indices" for k, v in obj.hints_used.items()]
            return format_html('<br>'.join(items))
        return "Aucun indice utilisé"
    hints_used_display.short_description = 'Indices utilisés'


@admin.register(EscapeCompletion)
class EscapeCompletionAdmin(admin.ModelAdmin):
    list_display = ['id', 'escape_link', 'code']
    search_fields = ['escape__title', 'code']
    readonly_fields = ['escape']

    def escape_link(self, obj):
        url = reverse('admin:games_escapegame_change', args=[obj.escape.id])
        return format_html('<a href="{}">{}</a>', url, obj.escape.title)
    escape_link.short_description = 'Escape'


@admin.register(Rating)
class RatingAdmin(admin.ModelAdmin):
    list_display = [
        'id',
        'escape_link',
        'user_link',
        'stars_display',
        'has_comment',
        'created_at'
    ]
    list_filter = ['stars', 'created_at']
    search_fields = ['user__username', 'user__email', 'escape__title', 'comment']
    readonly_fields = ['created_at']

    fieldsets = (
        ('Évaluation', {
            'fields': ('escape', 'user', 'stars', 'comment')
        }),
        ('Métadonnées', {
            'fields': ('created_at',)
        }),
    )

    def user_link(self, obj):
        url = reverse('admin:auth_user_change', args=[obj.user.id])
        return format_html('<a href="{}">{}</a>', url, obj.user.username)
    user_link.short_description = 'Utilisateur'

    def escape_link(self, obj):
        url = reverse('admin:games_escapegame_change', args=[obj.escape.id])
        return format_html('<a href="{}">{}</a>', url, obj.escape.title)
    escape_link.short_description = 'Escape'

    def stars_display(self, obj):
        stars = '⭐' * obj.stars
        return format_html(
            '<span style="font-size: 16px;">{}</span> <small>({}/5)</small>',
            stars, obj.stars
        )
    stars_display.short_description = 'Note'

    def has_comment(self, obj):
        return '✅ Oui' if obj.comment else '❌ Non'
    has_comment.short_description = 'Commentaire'


@admin.register(PasswordResetToken)
class PasswordResetTokenAdmin(admin.ModelAdmin):
    list_display = [
        'id',
        'user_link',
        'code',
        'created_at',
        'expires_at',
        'status_badge'
    ]
    list_filter = ['used', 'created_at']
    search_fields = ['user__username', 'user__email', 'code']
    readonly_fields = ['created_at', 'code']

    fieldsets = (
        ('Token', {
            'fields': ('user', 'code', 'created_at', 'expires_at', 'used')
        }),
    )

    def user_link(self, obj):
        url = reverse('admin:auth_user_change', args=[obj.user.id])
        return format_html('<a href="{}">{}</a>', url, obj.user.username)
    user_link.short_description = 'Utilisateur'

    def status_badge(self, obj):
        if obj.used:
            return format_html(
                '<span style="background-color: #6c757d; color: white; padding: 3px 10px; '
                'border-radius: 3px;">✓ Utilisé</span>'
            )
        elif obj.is_valid():
            return format_html(
                '<span style="background-color: #28a745; color: white; padding: 3px 10px; '
                'border-radius: 3px;">✓ Valide</span>'
            )
        else:
            return format_html(
                '<span style="background-color: #dc3545; color: white; padding: 3px 10px; '
                'border-radius: 3px;">✗ Expiré</span>'
            )
    status_badge.short_description = 'Statut'


@admin.register(EmailVerificationToken)
class EmailVerificationTokenAdmin(admin.ModelAdmin):
    list_display = [
        'id',
        'user_link',
        'code',
        'created_at',
        'expires_at',
        'status_badge'
    ]
    list_filter = ['used', 'created_at']
    search_fields = ['user__username', 'user__email', 'code']
    readonly_fields = ['created_at', 'code']

    fieldsets = (
        ('Token', {
            'fields': ('user', 'code', 'created_at', 'expires_at', 'used')
        }),
    )

    def user_link(self, obj):
        url = reverse('admin:auth_user_change', args=[obj.user.id])
        return format_html('<a href="{}">{}</a>', url, obj.user.username)
    user_link.short_description = 'Utilisateur'

    def status_badge(self, obj):
        if obj.used:
            return format_html(
                '<span style="background-color: #6c757d; color: white; padding: 3px 10px; '
                'border-radius: 3px;">✓ Utilisé</span>'
            )
        elif obj.is_valid():
            return format_html(
                '<span style="background-color: #28a745; color: white; padding: 3px 10px; '
                'border-radius: 3px;">✓ Valide</span>'
            )
        else:
            return format_html(
                '<span style="background-color: #dc3545; color: white; padding: 3px 10px; '
                'border-radius: 3px;">✗ Expiré</span>'
            )
    status_badge.short_description = 'Statut'


@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    list_display = ['id', 'user_link', 'email_verified_badge']
    list_filter = ['email_verified']
    search_fields = ['user__username', 'user__email']

    def user_link(self, obj):
        url = reverse('admin:auth_user_change', args=[obj.user.id])
        return format_html('<a href="{}">{}</a>', url, obj.user.username)
    user_link.short_description = 'Utilisateur'

    def email_verified_badge(self, obj):
        if obj.email_verified:
            return format_html(
                '<span style="background-color: #28a745; color: white; padding: 3px 10px; '
                'border-radius: 3px;">✓ Vérifié</span>'
            )
        return format_html(
            '<span style="background-color: #dc3545; color: white; padding: 3px 10px; '
            'border-radius: 3px;">✗ Non vérifié</span>'
        )
    email_verified_badge.short_description = 'Email'


@admin.register(AccountDeletionRequest)
class AccountDeletionRequestAdmin(admin.ModelAdmin):
    """Suivi des demandes de suppression de compte.

    Lecture seule : la liste est une piste d'audit du respect du delai de 30
    jours. Le traitement passe par la commande `anonymiser_compte`, qui
    cloture la demande elle-meme - modifier un statut a la main ici
    laisserait croire qu'un compte a ete traite alors qu'il ne l'est pas.
    """

    list_display = [
        "id", "username_au_moment_de_la_demande", "statut_badge",
        "demandee_le", "echeance_affichee", "traitee_le",
    ]
    list_filter = ["statut", "demandee_le"]
    search_fields = ["username_au_moment_de_la_demande", "email_demande"]
    date_hierarchy = "demandee_le"
    ordering = ["-demandee_le"]

    readonly_fields = [
        "user", "email_demande", "username_au_moment_de_la_demande", "motif",
        "statut", "demandee_le", "traitee_le", "detail_traitement",
        "echeance_affichee",
    ]

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        # Supprimer la trace reviendrait a effacer la preuve du traitement.
        return False

    def statut_badge(self, obj):
        if obj.statut == AccountDeletionRequest.STATUT_TRAITEE:
            couleur, texte = "#28a745", "✓ Traitée"
        elif obj.en_retard:
            couleur, texte = "#dc3545", "⚠ En retard"
        elif obj.statut == AccountDeletionRequest.STATUT_EN_ATTENTE:
            couleur, texte = "#ffc107", "En attente"
        else:
            couleur, texte = "#6c757d", "Annulée"
        return format_html(
            '<span style="background-color: {}; color: white; padding: 3px 10px; '
            'border-radius: 3px;">{}</span>',
            couleur, texte,
        )
    statut_badge.short_description = "Statut"

    def echeance_affichee(self, obj):
        jours = (obj.echeance - timezone.now()).days
        if obj.statut != AccountDeletionRequest.STATUT_EN_ATTENTE:
            return obj.echeance.strftime("%d/%m/%Y")
        if jours < 0:
            return format_html(
                '<span style="color: #dc3545; font-weight: bold;">{} ({} jours de retard)</span>',
                obj.echeance.strftime("%d/%m/%Y"), abs(jours),
            )
        return format_html(
            "{} (dans {} jours)", obj.echeance.strftime("%d/%m/%Y"), jours,
        )
    echeance_affichee.short_description = "Échéance (30 jours)"
