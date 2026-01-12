# backend/admin.py
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.contrib.auth.models import User
from django.utils.html import format_html
from django.db.models import Count

# Personnalisation de l'admin site
admin.site.site_header = "CityScape Administration"
admin.site.site_title = "CityScape Admin"
admin.site.index_title = "Bienvenue dans l'interface d'administration CityScape"


# Customisation de l'admin User
class UserAdmin(BaseUserAdmin):
    list_display = [
        'username',
        'email',
        'full_name',
        'escapes_created',
        'sessions_count',
        'is_staff',
        'is_active',
        'date_joined'
    ]
    list_filter = ['is_staff', 'is_active', 'date_joined', 'is_superuser']
    search_fields = ['username', 'email', 'first_name', 'last_name']

    fieldsets = BaseUserAdmin.fieldsets + (
        ('Statistiques', {
            'fields': ('stats_display',),
            'classes': ('collapse',)
        }),
    )

    readonly_fields = ['date_joined', 'last_login', 'stats_display']

    def get_queryset(self, request):
        queryset = super().get_queryset(request)
        queryset = queryset.annotate(
            _escapes_count=Count('created_escapes'),
            _sessions_count=Count('play_sessions')
        )
        return queryset

    def full_name(self, obj):
        if obj.first_name or obj.last_name:
            return f"{obj.first_name} {obj.last_name}".strip()
        return "-"
    full_name.short_description = 'Nom complet'

    def escapes_created(self, obj):
        count = obj._escapes_count
        if count > 0:
            return format_html(
                '<span style="background-color: #17a2b8; color: white; padding: 3px 8px; '
                'border-radius: 3px; font-weight: bold;">{}</span>',
                count
            )
        return '0'
    escapes_created.short_description = 'Escapes créés'
    escapes_created.admin_order_field = '_escapes_count'

    def sessions_count(self, obj):
        count = obj._sessions_count
        if count > 0:
            return format_html(
                '<span style="background-color: #28a745; color: white; padding: 3px 8px; '
                'border-radius: 3px; font-weight: bold;">{}</span>',
                count
            )
        return '0'
    sessions_count.short_description = 'Sessions'
    sessions_count.admin_order_field = '_sessions_count'

    def stats_display(self, obj):
        escapes = obj.created_escapes.count()
        sessions = obj.play_sessions.count()
        completed = obj.play_sessions.filter(completed_at__isnull=False).count()
        ratings = obj.rating_set.count()

        return format_html(
            '<strong>Escapes créés:</strong> {}<br>'
            '<strong>Sessions jouées:</strong> {}<br>'
            '<strong>Sessions terminées:</strong> {}<br>'
            '<strong>Notes données:</strong> {}',
            escapes, sessions, completed, ratings
        )
    stats_display.short_description = 'Statistiques'


# Désenregistrer l'admin User par défaut et enregistrer le notre
admin.site.unregister(User)
admin.site.register(User, UserAdmin)
