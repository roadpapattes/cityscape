# games/admin.py
from django.contrib import admin
from django.utils.html import format_html
from django.urls import reverse
from django.db.models import Count, Avg
from .models import EscapeGame, GameStep, EscapeStep


@admin.register(EscapeGame)
class EscapeGameAdmin(admin.ModelAdmin):
    list_display = [
        'id',
        'title',
        'city',
        'status_badge',
        'difficulty_stars',
        'rating_display',
        'owner',
        'is_private',
        'steps_count',
        'created_at',
    ]
    list_filter = ['status', 'difficulty', 'age_rating', 'is_private', 'created_at', 'city']
    search_fields = ['title', 'city', 'description', 'owner__username']
    readonly_fields = ['created_at', 'rating', 'preview_map']

    fieldsets = (
        ('Informations principales', {
            'fields': ('title', 'description', 'city', 'image_url', 'image_credit', 'owner')
        }),
        ('Localisation', {
            'fields': ('latitude', 'longitude', 'preview_map'),
            'classes': ('collapse',)
        }),
        ('Configuration', {
            'fields': ('status', 'difficulty', 'age_rating', 'duration_minutes', 'rating', 'is_private', 'allowed_users')
        }),
        ('Pénalités', {
            'fields': ('penalize_wrong_answers', 'wrong_answer_penalty'),
            'classes': ('collapse',)
        }),
        ('Messages', {
            'fields': ('victory_message', 'reject_reason'),
            'classes': ('collapse',)
        }),
        ('Métadonnées', {
            'fields': ('created_at', 'end_code'),
            'classes': ('collapse',)
        }),
    )

    filter_horizontal = ['allowed_users']

    def get_queryset(self, request):
        queryset = super().get_queryset(request)
        queryset = queryset.annotate(
            _steps_count=Count('creator_steps'),
            _avg_rating=Avg('ratings__stars')
        )
        return queryset

    def steps_count(self, obj):
        return obj._steps_count
    steps_count.short_description = 'Étapes'
    steps_count.admin_order_field = '_steps_count'

    def status_badge(self, obj):
        colors = {
            'draft': '#6c757d',
            'submitted': '#17a2b8',
            'pending': '#ffc107',
            'rejected': '#dc3545',
            'published': '#28a745',
        }
        color = colors.get(obj.status, '#6c757d')
        return format_html(
            '<span style="background-color: {}; color: white; padding: 3px 10px; '
            'border-radius: 3px; font-weight: bold;">{}</span>',
            color, obj.get_status_display()
        )
    status_badge.short_description = 'Statut'

    def difficulty_stars(self, obj):
        stars = '⭐' * obj.difficulty
        return stars
    difficulty_stars.short_description = 'Difficulté'

    def rating_display(self, obj):
        if hasattr(obj, '_avg_rating') and obj._avg_rating:
            return f"{obj._avg_rating:.1f} / 5"
        return "Pas encore noté"
    rating_display.short_description = 'Note moyenne'
    rating_display.admin_order_field = '_avg_rating'

    def preview_map(self, obj):
        if obj.latitude and obj.longitude:
            return format_html(
                '<a href="https://www.google.com/maps?q={},{}" target="_blank">'
                'Voir sur Google Maps 🗺️</a><br>'
                '<small>Lat: {}, Lon: {}</small>',
                obj.latitude, obj.longitude, obj.latitude, obj.longitude
            )
        return "Pas de coordonnées"
    preview_map.short_description = 'Localisation'

    actions = ['publish_escapes', 'reject_escapes', 'make_private', 'make_public']

    def publish_escapes(self, request, queryset):
        updated = queryset.update(status='published')
        self.message_user(request, f'{updated} escape(s) publié(s).')
    publish_escapes.short_description = '✅ Publier les escapes sélectionnés'

    def reject_escapes(self, request, queryset):
        updated = queryset.update(status='rejected')
        self.message_user(request, f'{updated} escape(s) rejeté(s).')
    reject_escapes.short_description = '❌ Rejeter les escapes sélectionnés'

    def make_private(self, request, queryset):
        updated = queryset.update(is_private=True)
        self.message_user(request, f'{updated} escape(s) rendu(s) privé(s).')
    make_private.short_description = '🔒 Rendre privé'

    def make_public(self, request, queryset):
        updated = queryset.update(is_private=False)
        self.message_user(request, f'{updated} escape(s) rendu(s) public(s).')
    make_public.short_description = '🌍 Rendre public'


class GameStepInline(admin.TabularInline):
    model = GameStep
    extra = 0
    fields = ['order', 'title', 'answer_type', 'is_final', 'latitude', 'longitude']
    readonly_fields = ['order']
    show_change_link = True


@admin.register(GameStep)
class GameStepAdmin(admin.ModelAdmin):
    list_display = ['id', 'escape_link', 'order', 'title', 'answer_type', 'is_final', 'has_hint']
    list_filter = ['answer_type', 'is_final', 'escape__status']
    search_fields = ['title', 'text', 'escape__title']
    readonly_fields = ['preview_map']

    fieldsets = (
        ('Informations', {
            'fields': ('escape', 'order', 'title', 'text', 'image_url', 'image_credit')
        }),
        ('Localisation', {
            'fields': ('latitude', 'longitude', 'preview_map'),
            'classes': ('collapse',)
        }),
        ('Réponse', {
            'fields': ('answer_type', 'answer_text', 'options', 'correct_index', 'expected_number', 'number_tolerance', 'match_left', 'match_right', 'match_pairs')
        }),
        ('Indices', {
            'fields': ('hint', 'hint_penalty', 'hints'),
            'classes': ('collapse',)
        }),
        ('Fin d\'escape', {
            'fields': ('is_final', 'final_message'),
            'classes': ('collapse',)
        }),
    )

    def escape_link(self, obj):
        url = reverse('admin:games_escapegame_change', args=[obj.escape.id])
        return format_html('<a href="{}">{}</a>', url, obj.escape.title)
    escape_link.short_description = 'Escape'

    def has_hint(self, obj):
        return '✅' if obj.hint or obj.hints else '❌'
    has_hint.short_description = 'Indice'

    def preview_map(self, obj):
        if obj.latitude and obj.longitude:
            return format_html(
                '<a href="https://www.google.com/maps?q={},{}" target="_blank">'
                'Voir sur Google Maps 🗺️</a>',
                obj.latitude, obj.longitude
            )
        return "Pas de coordonnées"
    preview_map.short_description = 'Localisation'


@admin.register(EscapeStep)
class EscapeStepAdmin(admin.ModelAdmin):
    list_display = ['id', 'escape', 'order', 'title', 'latitude', 'longitude']
    list_filter = ['escape']
    search_fields = ['title', 'prompt', 'escape__title']
    readonly_fields = ['preview_map']

    def preview_map(self, obj):
        return format_html(
            '<a href="https://www.google.com/maps?q={},{}" target="_blank">'
            'Voir sur Google Maps 🗺️</a>',
            obj.latitude, obj.longitude
        )
    preview_map.short_description = 'Localisation'
