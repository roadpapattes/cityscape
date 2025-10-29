# games/admin.py
from django.contrib import admin
from .models import EscapeGame, GameStep

class GameStepInline(admin.TabularInline):
    model = GameStep
    extra = 0
    fields = ("order", "title", "answer_type", "correct_index")
    ordering = ("order",)

@admin.register(EscapeGame)
class EscapeGameAdmin(admin.ModelAdmin):
    list_display = ("title", "city", "status", "rating", "duration_minutes", "difficulty", "created_at")
    search_fields = ("title", "city")
    inlines = [GameStepInline]

@admin.register(GameStep)
class GameStepAdmin(admin.ModelAdmin):
    list_display  = ("id", "escape", "order", "title", "answer_type")
    list_filter   = ("answer_type", "escape")
    ordering      = ("escape", "order")
    search_fields = ("title", "text")
