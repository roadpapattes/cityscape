from django.contrib import admin

from .models import CreatorLedgerEntry, PaywallImpression, Purchase


@admin.register(Purchase)
class PurchaseAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "escape", "payment_provider", "amount_cents", "status", "purchased_at")
    list_filter = ("payment_provider", "status")
    search_fields = ("user__username", "escape__title")


@admin.register(CreatorLedgerEntry)
class CreatorLedgerEntryAdmin(admin.ModelAdmin):
    list_display = ("id", "creator", "purchase", "share_cents", "status", "created_at")
    list_filter = ("status",)
    search_fields = ("creator__username",)


@admin.register(PaywallImpression)
class PaywallImpressionAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "escape", "created_at")
    search_fields = ("user__username", "escape__title")
