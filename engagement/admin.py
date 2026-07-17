from django.contrib import admin
from django.utils.html import format_html
from django.urls import reverse
from django.contrib.auth import get_user_model
from .models import PlaySession, EscapeCompletion, Rating, PasswordResetToken, UserProfile, EmailVerificationToken

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
        'duration'
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
    )

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
