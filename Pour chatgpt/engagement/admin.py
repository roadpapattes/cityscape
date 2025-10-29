from django.contrib import admin
from .models import PlaySession, EscapeCompletion, Rating

@admin.register(PlaySession)
class PlaySessionAdmin(admin.ModelAdmin):
    list_display = ("user", "escape", "started_at", "completed_at")
    list_filter = ("completed_at",)
    search_fields = ("user__username", "escape__title")

@admin.register(EscapeCompletion)
class EscapeCompletionAdmin(admin.ModelAdmin):
    list_display = ("escape", "code")
    search_fields = ("escape__title", "code")

@admin.register(Rating)
class RatingAdmin(admin.ModelAdmin):
    list_display = ("escape", "user", "stars", "created_at")
    list_filter = ("stars",)
    search_fields = ("user__username", "escape__title", "comment")
