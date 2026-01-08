# engagement/views.py
from .ratelimit_decorators import auth_rate_limit, password_reset_rate_limit, google_signin_rate_limit
import re
import unicodedata
import logging
log = logging.getLogger(__name__)
from typing import Dict, Any

from django.contrib.auth import authenticate, get_user_model
from django.db import transaction, IntegrityError
from django.db.models import Avg, Count
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django.conf import settings
from django.core.mail import send_mail

from rest_framework import permissions, status
from rest_framework.authentication import TokenAuthentication
from rest_framework.authtoken.models import Token
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import PlaySession, Rating, PasswordResetToken
from .serializers import (
    UserSerializer,
    RegisterSerializer,
    LoginSerializer,
    PlaySessionSerializer,
    RatingSerializer,
)
from games.models import EscapeGame, GameStep

def _normalize(s: str) -> str:
    return (s or "").strip().lower()

User = get_user_model()


# ---------------- Auth ----------------
@auth_rate_limit

class RegisterView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        s = RegisterSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        username = s.validated_data["username"]
        email = s.validated_data.get("email") or ""
        password = s.validated_data["password"]
        if User.objects.filter(username=username).exists():
            return Response({"detail": "Username already exists."}, status=400)
        user = User.objects.create_user(username=username, email=email, password=password)
        token, _ = Token.objects.get_or_create(user=user)
        return Response({"token": token.key, "user": UserSerializer(user).data}, status=201)

@auth_rate_limit

class LoginView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        s = LoginSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        user = authenticate(
            request, username=s.validated_data["username"], password=s.validated_data["password"]
        )
        if not user:
            return Response({"detail": "Invalid credentials."}, status=400)
        token, _ = Token.objects.get_or_create(user=user)
        return Response({"token": token.key, "user": UserSerializer(user).data}, status=200)


class LogoutView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        Token.objects.filter(user=request.user).delete()
        return Response({"detail": "Logged out."}, status=200)


class MeView(APIView):
    authentication_classes = [TokenAuthentication]
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        u = request.user
        return Response({
            "id": u.id,
            "username": u.username,
            "email": u.email or "",
            "is_staff": u.is_staff,
            "is_superuser": u.is_superuser,
        })

@password_reset_rate_limit

class PasswordResetRequestView(APIView):
    """
    POST /api/auth/password-reset/request
    Body: {"email": "user@example.com"}
    Response: {"message": "Code sent if email exists"}
    """
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        email = request.data.get("email", "").strip()
        if not email:
            return Response(
                {"error": "Email requis"},
                status=status.HTTP_400_BAD_REQUEST
            )

        User = get_user_model()
        try:
            user = User.objects.get(email=email)
        except User.DoesNotExist:
            # Security: Don't reveal if email exists
            return Response(
                {"message": "Si l'email existe, un code a été envoyé"},
                status=status.HTTP_200_OK
            )

        # Invalidate previous tokens for this user
        PasswordResetToken.objects.filter(user=user, used=False).update(used=True)

        # Create new token
        reset_token = PasswordResetToken.objects.create(user=user)

        # Send email
        try:
            send_mail(
                subject="CityScape - Réinitialisation de mot de passe",
                message=f"""Bonjour {user.username},

Vous avez demandé une réinitialisation de votre mot de passe.

Votre code de vérification est : {reset_token.code}

Ce code est valide pendant 15 minutes.

Si vous n'avez pas demandé cette réinitialisation, ignorez cet email.

L'équipe CityScape
""",
                from_email=settings.DEFAULT_FROM_EMAIL,
                recipient_list=[user.email],
                fail_silently=False,
            )
        except Exception as e:
            log.error(f"Failed to send password reset email: {e}")
            return Response(
                {"error": "Erreur lors de l'envoi de l'email"},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )

        return Response(
            {"message": "Si l'email existe, un code a été envoyé"},
            status=status.HTTP_200_OK
        )

@password_reset_rate_limit

class PasswordResetConfirmView(APIView):
    """
    POST /api/auth/password-reset/confirm
    Body: {"email": "user@example.com", "code": "123456", "new_password": "newpass"}
    Response: {"message": "Password reset successful"}
    """
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        email = request.data.get("email", "").strip()
        code = request.data.get("code", "").strip()
        new_password = request.data.get("new_password", "")

        if not email or not code or not new_password:
            return Response(
                {"error": "Email, code et nouveau mot de passe requis"},
                status=status.HTTP_400_BAD_REQUEST
            )

        if len(new_password) < 8:
            return Response(
                {"error": "Le mot de passe doit contenir au moins 8 caractères"},
                status=status.HTTP_400_BAD_REQUEST
            )

        User = get_user_model()
        try:
            user = User.objects.get(email=email)
        except User.DoesNotExist:
            return Response(
                {"error": "Code invalide ou expiré"},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Find valid token
        try:
            reset_token = PasswordResetToken.objects.filter(
                user=user,
                code=code,
                used=False
            ).order_by('-created_at').first()

            if not reset_token or not reset_token.is_valid():
                return Response(
                    {"error": "Code invalide ou expiré"},
                    status=status.HTTP_400_BAD_REQUEST
                )
        except Exception:
            return Response(
                {"error": "Code invalide ou expiré"},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Reset password
        user.set_password(new_password)
        user.save()

        # Mark token as used
        reset_token.used = True
        reset_token.save()

        # Invalidate all other tokens for this user
        PasswordResetToken.objects.filter(user=user, used=False).update(used=True)

        return Response(
            {"message": "Mot de passe réinitialisé avec succès"},
            status=status.HTTP_200_OK
        )


# -------------- Gameplay utils --------------

def _normalize(s: str) -> str:
    """Normalisation pour comparer des réponses texte: insensible aux accents/espaces/casse."""
    if not s:
        return ""
    s = s.strip().lower()
    s = "".join(c for c in unicodedata.normalize("NFKD", s) if not unicodedata.combining(c))
    s = re.sub(r"[^a-z0-9]+", "", s)
    return s


def _step_payload(step: GameStep, hints_used_map: Dict[str, Any]) -> Dict[str, Any]:
    # ---- Rassemble la liste d'indices ----
    all_hints = list(getattr(step, "hints", []) or [])
    if not all_hints:
        single = (getattr(step, "hint", "") or "").strip()
        if single:
            all_hints = [single]

    # combien déjà utilisés pour cette step (stockés par step.id)
    used_count = 0
    try:
        if isinstance(hints_used_map, dict):
            v = hints_used_map.get(str(step.id), 0)
            if isinstance(v, bool):
                used_count = 1 if v else 0
            else:
                used_count = int(v or 0)
    except Exception:
        used_count = 0
    used_count = max(0, min(used_count, len(all_hints)))

    # Valeurs d'indices calculées AVANT base
    if step.answer_type == getattr(GameStep, "ANSWER_NARR", "narration"):
        hint_block = {
            "hint_available": False,
            "hints_total": 0,
            "hints_used": 0,
            "revealed_hints": [],
            "hint_penalty": 0,
        }
    else:
        hint_block = {
            "hint_available": bool(all_hints),
            "hints_total": int(len(all_hints)),
            "hints_used": int(used_count),
            "revealed_hints": list(all_hints[:used_count]),
            "hint_penalty": int(getattr(step, "hint_penalty", 0) or 0),
        }

    base = {
        "id": step.id,
        "order": step.order,
        "title": step.title,
        "text": step.text or "",
        "image_url": getattr(step, "image_url", None),
        "answer_type": step.answer_type,  # 'text' | 'mcq' | 'numeric' | 'matching' | 'narration'
        "is_final": bool(getattr(step, "is_final", False)),
    }
    base.update(hint_block)

    # Données spécifiques
    if step.answer_type == GameStep.ANSWER_MCQ:
        base["options"] = list(step.options or [])
    elif step.answer_type == GameStep.ANSWER_MATCH:
        base["matching_left"]  = list(getattr(step, "match_left",  []) or [])
        base["matching_right"] = list(getattr(step, "match_right", []) or [])
        # (on NE renvoie PAS match_pairs)

    return base


# -------------- Sessions (start/state/hint/answer) --------------

class StartSessionView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, escape_id: int):
        escape = get_object_or_404(EscapeGame, pk=escape_id)
        try:
            sess, created = PlaySession.objects.get_or_create(
                user=request.user,
                escape=escape,
                defaults={"current_step_index": 0, "hints_used": {}},
            )
        except IntegrityError:
            sess = PlaySession.objects.get(user=request.user, escape=escape)
            created = False

        if created and not sess.started_at:
            from django.utils import timezone
            sess.started_at = timezone.now()
            sess.save(update_fields=["started_at"])

        return Response(
            {
                "id": sess.id,
                "escape": escape.id,
                "started_at": sess.started_at.isoformat() if sess.started_at else None,
                "completed_at": sess.completed_at.isoformat() if sess.completed_at else None,
            },
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )


class SessionStateView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, escape_id: int):
        escape = get_object_or_404(EscapeGame, pk=escape_id)

        # 1) Récupérer OU créer la session (sans dupliquer)
        try:
            sess, created = PlaySession.objects.get_or_create(
                user=request.user,
                escape=escape,
                defaults={"current_step_index": 0, "hints_used": {}},
            )
        except IntegrityError:
            # Cas de course : si deux créations simultanées arrivent
            sess = PlaySession.objects.get(user=request.user, escape=escape)
            created = False

        # Date de démarrage si nouvelle session
        if created and not sess.started_at:
            sess.started_at = timezone.now()
            sess.save(update_fields=["started_at"])

        # 2) Étapes
        steps = list(GameStep.objects.filter(escape=escape).order_by("order", "id"))
        total = len(steps)

        # État courant
        idx = int(getattr(sess, "current_step_index", 0) or 0)
        finished = bool(getattr(sess, "completed_at", None)) or (idx >= total)

        hints_map = dict(getattr(sess, "hints_used", {}) or {})

        # 3) Payload de l’étape courante (si non terminé)
        step_payload = None
        step_index = idx
        if finished:
            # On normalise l’index à total quand c’est fini
            step_index = min(idx, total)
        else:
            # Clamp de sécurité
            if total > 0:
                step_index = max(0, min(idx, total - 1))
                step_payload = _step_payload(steps[step_index], hints_map)
            else:
                step_index = 0  # pas d'étapes

        # 4) Historique des étapes passées
        if finished:
            past_steps = [_step_payload(s, hints_map) for s in steps]
        else:
            past_steps = [_step_payload(s, hints_map) for s in steps[:step_index]]

        resp = {
            "ok": True,
            "finished": finished,
            "total_steps": total,
            "step_index": step_index,
            "step": step_payload,          # None si terminé
            "past_steps": past_steps,      # liste pour ta PastStepsPage
            "penalty": int(getattr(sess, "penalty", 0) or 0),
            "started_at": sess.started_at.isoformat() if sess.started_at else None,
        }
        if finished and getattr(sess, "completed_at", None):
            resp["finished_at"] = sess.completed_at.isoformat()

        return Response(resp, status=status.HTTP_200_OK)


class SessionHistoryView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, escape_id: int):
        escape = get_object_or_404(EscapeGame, pk=escape_id)

        # Récupère (ou crée) la session
        try:
            sess, _ = PlaySession.objects.get_or_create(
                user=request.user,
                escape=escape,
                defaults={"current_step_index": 0, "hints_used": {}},
            )
        except IntegrityError:
            sess = PlaySession.objects.get(user=request.user, escape=escape)

        steps_qs = GameStep.objects.filter(escape=escape).order_by("order", "id")
        total = steps_qs.count()
        idx = max(0, min(getattr(sess, "current_step_index", 0) or 0, max(total - 1, 0)))

        # Étapes “déjà réalisées” => [0 .. idx-1]
        past = list(steps_qs[:idx])

        hints_map = dict(getattr(sess, "hints_used", {}) or {})
        answers_map = dict(getattr(sess, "answers", {}) or {})

        def snapshot(step: GameStep) -> Dict[str, Any]:
            # --- Multi-indices (même logique que _step_payload) ---
            all_hints = list(getattr(step, "hints", []) or [])
            if not all_hints:
                single = (getattr(step, "hint", "") or "").strip()
                if single:
                    all_hints = [single]

            used_count = 0
            try:
                v = hints_map.get(str(step.id), 0)
                if isinstance(v, bool):
                    used_count = 1 if v else 0
                else:
                    used_count = int(v or 0)
            except Exception:
                used_count = 0
            used_count = max(0, min(used_count, len(all_hints)))

            if step.answer_type == getattr(GameStep, "ANSWER_NARR", "narration"):
                hint_block = {
                    "hint_available": False,
                    "hints_total": 0,
                    "hints_used": 0,
                    "revealed_hints": [],
                    "hint_penalty": 0,
                }
            else:
                hint_block = {
                    "hint_available": bool(all_hints),
                    "hints_total": int(len(all_hints)),
                    "hints_used": int(used_count),
                    "revealed_hints": list(all_hints[:used_count]),
                    "hint_penalty": int(getattr(step, "hint_penalty", 0) or 0),
                }

            base = {
                "id": step.id,
                "order": step.order,
                "title": step.title,
                "text": step.text or "",
                "image_url": getattr(step, "image_url", None),
                "answer_type": step.answer_type,
                "is_final": bool(getattr(step, "is_final", False)),
            }
            base.update(hint_block)

            # Joindre la réponse donnée si on l’a
            ans = answers_map.get(str(step.id))
            if isinstance(ans, dict):
                base["answer"] = ans

            # Données spécifiques (comme _step_payload)
            if step.answer_type == GameStep.ANSWER_MCQ:
                base["options"] = list(step.options or [])
            elif step.answer_type == GameStep.ANSWER_MATCH:
                base["matching_left"]  = list(getattr(step, "match_left",  []) or [])
                base["matching_right"] = list(getattr(step, "match_right", []) or [])
            return base

        data = [snapshot(s) for s in past]

        return Response(
            {
                "steps": data,
                "count": len(data),
                "total": total,
                "current_index": idx,
            },
            status=status.HTTP_200_OK,
        )




class SessionHintView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, escape_id: int):
        escape = get_object_or_404(EscapeGame, pk=escape_id)
        sess = (PlaySession.objects
                .filter(user=request.user, escape=escape, completed_at__isnull=True)
                .order_by("-id")
                .first())
        if not sess:
            return Response({"detail": "Session inactive. Démarrez d'abord."}, status=400)

        steps = list(GameStep.objects.filter(escape=escape).order_by("order", "id"))
        idx = int(getattr(sess, "current_step_index", 0) or 0)
        if idx >= len(steps):
            return Response({"detail": "Partie déjà terminée."}, status=400)

        st = steps[idx]

        # Pas d'indice pour narration
        if st.answer_type == getattr(GameStep, "ANSWER_NARR", "narration"):
            return Response({"detail": "Pas d'indice pour cette étape."}, status=400)

        # Récup liste d'indices (fallback sur hint)
        all_hints = list(getattr(st, "hints", []) or [])
        if not all_hints:
            single = (getattr(st, "hint", "") or "").strip()
            if single:
                all_hints = [single]
        if not all_hints:
            return Response({"detail": "Pas d'indice pour cette étape."}, status=400)

        hints_map = dict(sess.hints_used or {}) if isinstance(sess.hints_used, dict) else {}
        used = hints_map.get(str(st.id), 0)
        if isinstance(used, bool):
            used = 1 if used else 0
        try:
            used = int(used)
        except Exception:
            used = 0

        if used >= len(all_hints):
            return Response({"detail": "Tous les indices ont déjà été révélés."}, status=400)

        # Révéler le prochain (0-based)
        next_index = used
        try:
            next_hint = all_hints[next_index]
        except Exception:
            return Response({"detail": "Données d'indice invalides."}, status=400)

        hints_map[str(st.id)] = used + 1
        sess.hints_used = hints_map

        p = int(getattr(st, "hint_penalty", 0) or 0)
        if p > 0 and hasattr(sess, "penalty"):
            sess.penalty = int(getattr(sess, "penalty", 0) or 0) + p
            sess.save(update_fields=["hints_used", "penalty"])
        else:
            sess.save(update_fields=["hints_used"])

        return Response(
            {
                "hint": next_hint,
                "now_used_count": used + 1,           # 1-based, plus simple côté client
                "hints_total": len(all_hints),
                "penalty_minutes": p,
                "penalty_total": int(getattr(sess, "penalty", 0) or 0),
            },
            status=200,
        )





class SessionAnswerView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, escape_id: int):
        """
        Payload attendu:
        - 'text'     : { "answer": "..." }
        - 'mcq'      : { "selected_index": 2 }  (ou "index")
        - 'numeric'  : { "answer": "42" }
        - 'matching' : { "pairs": [[li,ri], ...] } ou [{"left_index": li, "right_index": ri}, ...]
        - 'narration': {}  (aucune réponse, accepté tel quel)
        """
        escape = get_object_or_404(EscapeGame, pk=escape_id)
        sess = (PlaySession.objects
                .filter(user=request.user, escape=escape, completed_at__isnull=True)
                .order_by("-id")
                .first())
        if not sess:
            return Response({"detail": "Session inactive. Démarrez d'abord."}, status=400)

        steps = list(GameStep.objects.filter(escape=escape).order_by("order", "id"))
        total = len(steps)
        idx = int(getattr(sess, "current_step_index", 0) or 0)
        if idx >= total:
            return Response({"detail": "Partie déjà terminée."}, status=400)

        st = steps[idx]
        ok = False

        # --- Vérification de la réponse ---
        if st.answer_type == GameStep.ANSWER_TEXT:
            user_answer = (request.data or {}).get("answer", "")
            ok = _normalize(user_answer) == _normalize(st.answer_text)

        elif st.answer_type == GameStep.ANSWER_MCQ:
            sel = (request.data or {}).get("selected_index")
            if sel is None:
                sel = (request.data or {}).get("index")
            try:
                sel = int(sel)
            except (TypeError, ValueError):
                sel = None
            ok = (sel is not None) and (st.correct_index is not None) and (sel == int(st.correct_index))

        elif st.answer_type == GameStep.ANSWER_NUM:
            # Numérique: compare un nombre (supporte "," ou ".")
            def _to_number(x):
                if x is None:
                    return None
                s = str(x).strip().replace(",", ".")
                try:
                    return float(s)
                except ValueError:
                    return None

            user_num = _to_number((request.data or {}).get("answer"))
            exp_num  = _to_number(getattr(st, "answer_text", None))
            ok = (user_num is not None and exp_num is not None and abs(user_num - exp_num) <= 0.0)

        elif st.answer_type == getattr(GameStep, "ANSWER_MATCH", "matching"):
            # pairs: [[li,ri], ...] ou [{"left_index": li, "right_index": ri}, ...]
            client_pairs = (request.data or {}).get("pairs") or (request.data or {}).get("match_pairs") or []
            pairs_norm = []
            if isinstance(client_pairs, (list, tuple)):
                for p in client_pairs:
                    if isinstance(p, (list, tuple)) and len(p) == 2:
                        li, ri = p
                    elif isinstance(p, dict) and "left_index" in p and "right_index" in p:
                        li, ri = p["left_index"], p["right_index"]
                    else:
                        return Response({"detail": "Format de paires invalide."}, status=400)
                    try:
                        li = int(li); ri = int(ri)
                    except (TypeError, ValueError):
                        return Response({"detail": "Indices entiers requis."}, status=400)
                    pairs_norm.append((li, ri))
            else:
                return Response({"detail": "Liste de paires requise."}, status=400)

            correct = set(tuple(x) for x in (getattr(st, "match_pairs", []) or []))
            given   = set(pairs_norm)
            ok = (given == correct)

        elif st.answer_type == getattr(GameStep, "ANSWER_NARR", "narration"):
            # Narration : pas de réponse → toujours "ok"
            ok = True

        else:
            return Response({"detail": "Type de réponse inconnu."}, status=400)

        # --- Mauvaise réponse -> pénalité configurable côté escape ---
        if not ok:
            penalize = bool(getattr(escape, "penalize_wrong_answers", False))
            per_min = int(getattr(escape, "wrong_answer_penalty", 0) or 0)
            applied = 0
            if penalize and per_min > 0 and hasattr(sess, "penalty"):
                sess.penalty = int(getattr(sess, "penalty", 0)) + per_min
                sess.save(update_fields=["penalty"])
                applied = per_min

            return Response(
                {
                    "ok": True,
                    "correct": False,
                    "penalty": int(getattr(sess, "penalty", 0)),
                    "applied_penalty": applied,
                },
                status=200,
            )

        # ---------------- Enregistrer la réponse acceptée ----------------
        answers_map = dict(sess.answers or {})
        entry = {"type": st.answer_type, "ts": timezone.now().isoformat()}

        if st.answer_type == GameStep.ANSWER_TEXT:
            entry["value"] = str((request.data or {}).get("answer", ""))

        elif st.answer_type == GameStep.ANSWER_MCQ:
            sel = (request.data or {}).get("selected_index")
            if sel is None:
                sel = (request.data or {}).get("index")
            try:
                sel = int(sel)
            except (TypeError, ValueError):
                sel = None
            opts = list(st.options or [])
            entry["selected_index"] = sel
            entry["selected_label"] = (opts[sel] if sel is not None and 0 <= sel < len(opts) else None)

        elif st.answer_type == GameStep.ANSWER_NUM:
            entry["value"] = str((request.data or {}).get("answer", ""))

        elif st.answer_type == getattr(GameStep, "ANSWER_MATCH", "matching"):
            client_pairs = (request.data or {}).get("pairs") or (request.data or {}).get("match_pairs") or []
            pairs_norm = []
            if isinstance(client_pairs, (list, tuple)):
                for p in client_pairs:
                    if isinstance(p, (list, tuple)) and len(p) == 2:
                        li, ri = p
                    else:
                        li, ri = p.get("left_index"), p.get("right_index")
                    pairs_norm.append([int(li), int(ri)])
            left  = list(getattr(st, "match_left",  []) or [])
            right = list(getattr(st, "match_right", []) or [])
            entry["pairs"] = pairs_norm
            entry["pairs_verbose"] = [
                {
                    "left_index": li,
                    "right_index": ri,
                    "left":  left[li]  if 0 <= li < len(left)  else None,
                    "right": right[ri] if 0 <= ri < len(right) else None,
                }
                for li, ri in pairs_norm
            ]

        elif st.answer_type == getattr(GameStep, "ANSWER_NARR", "narration"):
            entry["value"] = "narration"

        answers_map[str(st.id)] = entry
        sess.answers = answers_map
        # ----------------------------------------------------------------

        # --- Bonne réponse ---
        is_last = (idx >= total - 1)
        is_final_flag = bool(getattr(st, "is_final", False))
        finished = is_last or is_final_flag

        if finished:
            if not sess.completed_at:
                sess.completed_at = timezone.now()
            sess.current_step_index = min(idx + 1, total)
            # 👇 IMPORTANT: on sauvegarde aussi 'answers'
            sess.save(update_fields=["current_step_index", "completed_at", "answers"])
        else:
            sess.current_step_index = idx + 1
            # 👇 IMPORTANT: on sauvegarde aussi 'answers'
            sess.save(update_fields=["current_step_index", "answers"])

        final_msg = (getattr(escape, "victory_message", None) or "").strip()

        resp: Dict[str, Any] = {
            "ok": True,
            "correct": True,
            "finished": finished,
            "next_index": sess.current_step_index,
            "penalty": int(getattr(sess, "penalty", 0)),
        }
        if finished:
            resp["final_message"] = final_msg
            resp["finished_at"] = sess.completed_at.isoformat()

        return Response(resp, status=200)




# -------------- Ratings --------------

class CanRateView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, escape_id: int):
        escape = get_object_or_404(EscapeGame, pk=escape_id)
        has_completed = PlaySession.objects.filter(
            user=request.user, escape=escape, completed_at__isnull=False
        ).exists()
        already_rated = Rating.objects.filter(user=request.user, escape=escape).exists()
        return Response({"can_rate": bool(has_completed and not already_rated)}, status=200)

class ReportEscapeView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, escape_id: int):
        escape = get_object_or_404(EscapeGame, pk=escape_id)
        msg = (request.data.get("message") or "").strip()
        if not msg:
            return Response({"detail": "Message requis."}, status=400)

        user = request.user
        subject = f"[Signalement Escape] {escape.title} (id={escape.id})"
        body = (
            f"Escape: {escape.title} (id={escape.id})\n"
            f"Créateur: {getattr(escape.owner, 'username', None)} (id={getattr(escape.owner, 'id', None)})\n"
            f"Signalé par: {user.username} (id={user.id}, email: {user.email})\n"
            f"Date: {timezone.now().isoformat()}\n\n"
            f"Message:\n{msg}\n"
        )

        from_email = getattr(settings, "DEFAULT_FROM_EMAIL", "noreply@localhost")
        to = ["feedback.enigmapolis@gmail.com"]

        try:
            send_mail(subject, body, from_email, to, fail_silently=False)
        except Exception as e:
            return Response({"detail": f"Envoi email échoué: {e}"}, status=500)

        return Response({"ok": True}, status=201)

class RatingsListCreateView(APIView):
    permission_classes = [permissions.IsAuthenticatedOrReadOnly]

    def get(self, request, escape_id: int):
        escape = get_object_or_404(EscapeGame, pk=escape_id)
        qs = Rating.objects.filter(escape=escape).select_related("user").order_by("-id")
        data = [RatingSerializer(r).data for r in qs]
        return Response(data, status=status.HTTP_200_OK)

    def post(self, request, escape_id: int):
        # POST réservé aux utilisateurs authentifiés (IsAuthenticatedOrReadOnly couvre déjà ça,
        # mais on renvoie un 401 explicite pour être clair)
        if not request.user.is_authenticated:
            return Response({"detail": "Authentification requise."}, status=status.HTTP_401_UNAUTHORIZED)

        escape = get_object_or_404(EscapeGame, pk=escape_id)

        # On injecte l'escape depuis l'URL pour satisfaire le serializer
        payload = {
            "escape": escape.id,
            "stars": request.data.get("stars"),
            "comment": (request.data.get("comment") or "").strip(),
        }
        s = RatingSerializer(data=payload)
        s.is_valid(raise_exception=True)

        try:
            with transaction.atomic():
                rating = Rating.objects.create(
                    user=request.user,
                    escape=escape,
                    stars=s.validated_data["stars"],
                    comment=s.validated_data.get("comment", ""),
                )
        except IntegrityError:
            return Response(
                {"detail": "Vous avez déjà noté cet escape."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        agg = Rating.objects.filter(escape=escape).aggregate(
            avg=Avg("stars"),
            count=Count("id"),
        )

        return Response(
            {
                "rating": RatingSerializer(rating).data,
                "aggregate": {
                    "avg": float(agg["avg"] or 0.0),
                    "count": int(agg["count"] or 0),
                },
            },
            status=status.HTTP_201_CREATED,
        )
        
class CreatorFeedbackView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        """
        Payload attendu:
        {
          "message": "texte obligatoire",
          "subject": "optionnel",
          "page": "optionnel (ex: creator_page)",
          "escape_id": 123 (optionnel),
          "app_version": "optionnel",
          "extra": {...} (optionnel)
        }
        """
        msg = (request.data.get("message") or "").strip()
        if not msg:
            return Response({"detail": "message requis."}, status=400)

        subject = (request.data.get("subject") or "Feedback créateur").strip()
        page = (request.data.get("page") or "").strip()
        escape_id = request.data.get("escape_id")
        app_version = (request.data.get("app_version") or "").strip()
        extra = request.data.get("extra")

        user = request.user
        user_line = f"De: {getattr(user, 'username', user)} (id={getattr(user, 'id', '?')}, email={getattr(user, 'email', '')})"
        meta_lines = []
        if page:        meta_lines.append(f"Page: {page}")
        if escape_id:   meta_lines.append(f"Escape ID: {escape_id}")
        if app_version: meta_lines.append(f"App: {app_version}")
        if extra:       meta_lines.append(f"Extra: {extra}")

        body = "\n".join(
            [
                user_line,
                *meta_lines,
                "",
                "Message:",
                msg,
            ]
        )

        to_email = getattr(settings, "CREATOR_FEEDBACK_EMAIL", None) or "feedback.enigmapolis@gmail.com"
        from_email = getattr(settings, "DEFAULT_FROM_EMAIL", "noreply@example.com")

        try:
            send_mail(
                subject=subject,
                message=body,
                from_email=from_email,
                recipient_list=[to_email],
                fail_silently=False,
            )
        except Exception as e:
            return Response({"detail": f"Envoi email impossible: {e}"}, status=500)

        return Response({"ok": True}, status=200)


@google_signin_rate_limit
# -------------- Google Sign-In --------------

class GoogleSignInView(APIView):
    """
    Google Sign-In endpoint
    Receives Google ID token from client, verifies it, and creates/logs in user
    """
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        id_token = request.data.get("id_token", "").strip()

        if not id_token:
            return Response(
                {"error": "id_token requis"},
                status=status.HTTP_400_BAD_REQUEST
            )

        try:
            # Import google-auth library for token verification
            from google.oauth2 import id_token as google_id_token
            from google.auth.transport import requests as google_requests

            # Verify the token with CLIENT_ID to prevent token reuse from other apps
            from django.conf import settings
            idinfo = google_id_token.verify_oauth2_token(
                id_token,
                google_requests.Request(),
                audience=settings.GOOGLE_OAUTH_CLIENT_ID
            )

            # Extract user info from token
            google_user_id = idinfo.get('sub')  # Google user ID
            email = idinfo.get('email', '')
            email_verified = idinfo.get('email_verified', False)
            name = idinfo.get('name', '')
            given_name = idinfo.get('given_name', '')
            family_name = idinfo.get('family_name', '')

            if not email or not email_verified:
                return Response(
                    {"error": "Email non vérifié ou manquant"},
                    status=status.HTTP_400_BAD_REQUEST
                )

            User = get_user_model()

            # Try to find user by email
            user = User.objects.filter(email=email).first()

            if user:
                # User exists, log them in
                token, _ = Token.objects.get_or_create(user=user)
                return Response({
                    "token": token.key,
                    "user": UserSerializer(user).data
                }, status=status.HTTP_200_OK)
            else:
                # Create new user
                # Generate username from email or name
                base_username = email.split('@')[0]
                username = base_username
                counter = 1
                while User.objects.filter(username=username).exists():
                    username = f"{base_username}{counter}"
                    counter += 1

                # Create user (no password needed for Google users)
                user = User.objects.create_user(
                    username=username,
                    email=email,
                    first_name=given_name,
                    last_name=family_name
                )
                user.set_unusable_password()  # Google users don't need passwords
                user.save()

                # Create token
                token = Token.objects.create(user=user)

                return Response({
                    "token": token.key,
                    "user": UserSerializer(user).data
                }, status=status.HTTP_200_OK)  # Always 200 to prevent user enumeration

        except ValueError as e:
            # Invalid token
            return Response(
                {"error": f"Token Google invalide: {str(e)}"},
                status=status.HTTP_400_BAD_REQUEST
            )
        except Exception as e:
            log.error(f"Google Sign-In error: {e}")
            return Response(
                {"error": "Erreur lors de l'authentification Google"},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )