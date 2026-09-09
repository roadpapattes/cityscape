from django.contrib.auth import get_user_model
from django.test import TestCase, override_settings
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from games.models import EscapeGame
from .funnel import conversion_report
from .models import CreatorLedgerEntry, PaywallImpression, Purchase
from .services import get_valid_purchase, has_access, record_paywall_impression, unlock_escape

User = get_user_model()


def _make_escape(price_cents=None, owner=None):
    return EscapeGame.objects.create(
        title="Test Escape", city="Testville",
        latitude=48.85, longitude=2.35,
        status="published", price_cents=price_cents, owner=owner,
    )


class ServiceTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(username="alice", password="pw")

    def test_free_escape_always_has_access(self):
        escape = _make_escape(price_cents=None)
        self.assertTrue(has_access(self.user, escape))
        self.assertTrue(has_access(None, escape))

    def test_paid_escape_blocks_until_unlocked(self):
        escape = _make_escape(price_cents=499)
        self.assertFalse(has_access(self.user, escape))

        purchase = unlock_escape(self.user, escape)
        self.assertEqual(purchase.payment_provider, Purchase.PROVIDER_FREE_LAUNCH)
        self.assertEqual(purchase.amount_cents, 0)
        self.assertTrue(has_access(self.user, escape))

    def test_unlock_is_idempotent(self):
        escape = _make_escape(price_cents=499)
        first = unlock_escape(self.user, escape)
        second = unlock_escape(self.user, escape)
        self.assertEqual(first.id, second.id)
        self.assertEqual(Purchase.objects.filter(user=self.user, escape=escape).count(), 1)

    def test_free_launch_purchase_never_creates_ledger_entry(self):
        from .services import record_creator_share
        creator = User.objects.create_user(username="creator", password="pw")
        escape = _make_escape(price_cents=499, owner=creator)
        purchase = unlock_escape(self.user, escape)
        entry = record_creator_share(purchase)
        self.assertIsNone(entry)
        self.assertEqual(CreatorLedgerEntry.objects.count(), 0)

    @override_settings(MONETIZATION_ENABLED=True)
    def test_real_payments_not_implemented_yet(self):
        from .services import MonetizationNotReady
        escape = _make_escape(price_cents=499)
        with self.assertRaises(MonetizationNotReady):
            unlock_escape(self.user, escape)


class EscapeUnlockViewTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(username="bob", password="pw")
        self.token = Token.objects.create(user=self.user)
        self.client = APIClient()
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {self.token.key}")

    def test_status_endpoint_reports_locked_then_unlocked(self):
        escape = _make_escape(price_cents=299)
        r = self.client.get(f"/api/escapes/{escape.id}/unlock")
        self.assertEqual(r.status_code, 200)
        self.assertFalse(r.json()["unlocked"])
        self.assertEqual(r.json()["price_cents"], 299)

        r = self.client.post(f"/api/escapes/{escape.id}/unlock")
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.json()["unlocked"])
        self.assertEqual(r.json()["purchase"]["amount_cents"], 0)

        r = self.client.get(f"/api/escapes/{escape.id}/unlock")
        self.assertTrue(r.json()["unlocked"])

    def test_unlocking_free_escape_is_rejected(self):
        escape = _make_escape(price_cents=None)
        r = self.client.post(f"/api/escapes/{escape.id}/unlock")
        self.assertEqual(r.status_code, 400)


class SessionGateTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(username="carol", password="pw")
        self.token = Token.objects.create(user=self.user)
        self.client = APIClient()
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {self.token.key}")

    def test_start_session_blocked_on_paid_unowned_escape(self):
        escape = _make_escape(price_cents=199)
        r = self.client.post(f"/api/escapes/{escape.id}/sessions/start")
        self.assertEqual(r.status_code, 402)

    def test_start_session_allowed_after_unlock(self):
        escape = _make_escape(price_cents=199)
        unlock_escape(self.user, escape)
        r = self.client.post(f"/api/escapes/{escape.id}/sessions/start")
        self.assertIn(r.status_code, (200, 201))


class PaywallImpressionTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(username="dave", password="pw")
        self.token = Token.objects.create(user=self.user)
        self.client = APIClient()
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {self.token.key}")

    def test_impression_endpoint_records_event(self):
        escape = _make_escape(price_cents=399)
        r = self.client.post(f"/api/escapes/{escape.id}/paywall_impression")
        self.assertEqual(r.status_code, 201)
        self.assertEqual(PaywallImpression.objects.filter(user=self.user, escape=escape).count(), 1)

    def test_impression_rejected_on_free_escape(self):
        escape = _make_escape(price_cents=None)
        r = self.client.post(f"/api/escapes/{escape.id}/paywall_impression")
        self.assertEqual(r.status_code, 400)


class ConversionReportTests(TestCase):
    def setUp(self):
        self.alice = User.objects.create_user(username="alice2", password="pw")
        self.bob = User.objects.create_user(username="bob2", password="pw")
        self.carol = User.objects.create_user(username="carol2", password="pw")

    def test_conversion_rate_computed_from_distinct_users(self):
        escape = _make_escape(price_cents=500)
        for u in (self.alice, self.bob, self.carol):
            record_paywall_impression(u, escape)
        # Repeated impression for alice must not inflate the denominator.
        record_paywall_impression(self.alice, escape)
        unlock_escape(self.alice, escape)

        rows = conversion_report()
        self.assertEqual(len(rows), 1)
        row = rows[0]
        self.assertEqual(row.impressions, 3)
        self.assertEqual(row.unlocks, 1)
        self.assertAlmostEqual(row.conversion_rate, 1 / 3)

    def test_no_impressions_means_zero_rate_not_error(self):
        escape = _make_escape(price_cents=500)
        unlock_escape(self.alice, escape)
        rows = conversion_report()
        self.assertEqual(rows[0].impressions, 0)
        self.assertEqual(rows[0].conversion_rate, 0.0)
