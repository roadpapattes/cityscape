# games/views_creator.py
from typing import Any, Dict, Set
from django.db import transaction
from django.shortcuts import get_object_or_404
from rest_framework import viewsets, permissions, status, serializers
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAdminUser, IsAuthenticated

from .serializers import (
    EscapeGameSerializer,
    CreatorEscapeListSerializer,
)
from .models import EscapeGame, GameStep


def _field_names(model) -> Set[str]:
    names: Set[str] = set()
    for f in model._meta.get_fields():
        if getattr(f, "concrete", False) and getattr(f, "attname", None):
            names.add(f.name)
        elif hasattr(f, "name"):
            names.add(f.name)
    return names


EG_FIELD_NAMES = _field_names(EscapeGame)
GS_FIELD_NAMES = _field_names(GameStep)


def _normalize_orders(escape: EscapeGame):
    steps = list(GameStep.objects.filter(escape=escape).order_by("order", "id"))
    for i, s in enumerate(steps, start=1):
        if s.order != i:
            GameStep.objects.filter(pk=s.pk).update(order=i)

def user_can_view_escape(user, escape: EscapeGame) -> bool:
    if not getattr(escape, "is_private", False):
        return True
    if user.is_authenticated and (user.is_staff or user.is_superuser):
        return True
    owner = getattr(escape, "owner", None)
    if owner and user.is_authenticated and owner == user:
        return True
    # allowed_users (ManyToMany)
    return user.is_authenticated and escape.allowed_users.filter(pk=user.pk).exists()

# ----------------- Serializer local pour GameStep -----------------

class GameStepSerializer(serializers.ModelSerializer):
    class Meta:
        model = GameStep
        fields = "__all__"
        read_only_fields = ("id", "escape",)

    # --- Normalisation de sortie : toujours une liste pour 'hints' ---
    def to_representation(self, instance):
        data = super().to_representation(instance)

        # Force hints comme liste, même s'il n'y a qu'un seul indice
        stored_hints = list(getattr(instance, "hints", []) or [])
        if not stored_hints:
            single = (getattr(instance, "hint", "") or "").strip()
            if single:
                stored_hints = [single]
        data["hints"] = stored_hints

        # Assure que 'hint' n'est jamais None (compat UI)
        data["hint"] = (getattr(instance, "hint", "") or "")

        return data

    def validate(self, attrs):
        at = attrs.get("answer_type", getattr(self.instance, "answer_type", GameStep.ANSWER_TEXT))

        # ---- valeurs existantes si PATCH partiel ----
        answer_text   = attrs.get("answer_text",   getattr(self.instance, "answer_text",   "")) or ""
        options       = attrs.get("options",       getattr(self.instance, "options",       [])) or []
        correct_index = attrs.get("correct_index", getattr(self.instance, "correct_index", None))

        match_left  = attrs.get("match_left",  getattr(self.instance, "match_left",  [])) or []
        match_right = attrs.get("match_right", getattr(self.instance, "match_right", [])) or []
        match_pairs = attrs.get("match_pairs", getattr(self.instance, "match_pairs", [])) or []

        # ---- HINTS (multi) ----
        raw_hints   = attrs.get("hints", getattr(self.instance, "hints", [])) or []
        single_hint = attrs.get("hint", getattr(self.instance, "hint", "")) or ""

        clean_hints = []
        if isinstance(raw_hints, (list, tuple)):
            clean_hints = [str(x).strip() for x in raw_hints if str(x).strip()]
        if not clean_hints and single_hint.strip():
            clean_hints = [single_hint.strip()]

        # Si le modèle a un champ JSON 'hints', on privilégie la liste
        if hasattr(GameStep, "hints"):
            attrs["hints"] = clean_hints
            # 'hint' uniquement si pas de liste ; sinon string vide
            attrs["hint"] = "" if clean_hints else single_hint.strip()
        else:
            # fallback: pas de champ JSON 'hints' → garder 'hint' (éventuellement joindre la liste)
            attrs.pop("hints", None)
            attrs["hint"] = single_hint.strip() if single_hint else ("; ".join(clean_hints) if clean_hints else "")

        # ---- Validation selon le type ----
        if at in (GameStep.ANSWER_TEXT, getattr(GameStep, "ANSWER_CAESAR", "cesar")):
            if not str(answer_text).strip():
                raise serializers.ValidationError({"answer_text": 'Requis pour "Texte libre".'})
            attrs["options"] = []
            attrs["correct_index"] = None
            attrs["match_left"] = []
            attrs["match_right"] = []
            attrs["match_pairs"] = []

        elif at == GameStep.ANSWER_MCQ:
            if not isinstance(options, (list, tuple)):
                raise serializers.ValidationError({"options": "Doit être une liste de chaînes."})
            opt_clean = [str(o).strip() for o in options if str(o).strip()]
            if len(opt_clean) < 2:
                raise serializers.ValidationError({"options": "Au moins 2 options non vides requises."})
            if correct_index is None or not isinstance(correct_index, int) or correct_index < 0 or correct_index >= len(opt_clean):
                raise serializers.ValidationError({"correct_index": "Indice hors bornes."})
            attrs["options"] = opt_clean
            attrs["answer_text"] = ""
            attrs["match_left"] = []
            attrs["match_right"] = []
            attrs["match_pairs"] = []

        elif at == GameStep.ANSWER_NUM:
            s = str(answer_text).strip()
            if not s:
                raise serializers.ValidationError({"answer_text": 'Requis pour "Numérique".'})
            try:
                n = int(s)
            except (TypeError, ValueError):
                raise serializers.ValidationError({"answer_text": "Doit être un entier (ex: 12)."})
            attrs["answer_text"] = str(n)
            attrs["options"] = []
            attrs["correct_index"] = None
            attrs["match_left"] = []
            attrs["match_right"] = []
            attrs["match_pairs"] = []

        elif at == GameStep.ANSWER_MATCH:
            if not isinstance(match_left, (list, tuple)) or not all(str(x).strip() for x in match_left):
                raise serializers.ValidationError({"match_left": "Liste non vide de libellés requis."})
            if not isinstance(match_right, (list, tuple)) or not all(str(x).strip() for x in match_right):
                raise serializers.ValidationError({"match_right": "Liste non vide de libellés requis."})

            pairs_norm = []
            if isinstance(match_pairs, (list, tuple)):
                for p in match_pairs:
                    if isinstance(p, (list, tuple)) and len(p) == 2:
                        li, ri = p
                    elif isinstance(p, dict) and "left_index" in p and "right_index" in p:
                        li, ri = p["left_index"], p["right_index"]
                    else:
                        raise serializers.ValidationError({"match_pairs": "Forme invalide (attendu [[li,ri], ...] ou objets left_index/right_index)."})
                    try:
                        li = int(li); ri = int(ri)
                    except (TypeError, ValueError):
                        raise serializers.ValidationError({"match_pairs": "Indices entiers requis."})
                    if li < 0 or li >= len(match_left) or ri < 0 or ri >= len(match_right):
                        raise serializers.ValidationError({"match_pairs": "Indice hors bornes."})
                    pairs_norm.append([li, ri])
            else:
                raise serializers.ValidationError({"match_pairs": "Liste de paires requise."})

            if len(pairs_norm) != len(match_left):
                raise serializers.ValidationError({"match_pairs": "Il faut autant de paires que d’éléments à gauche (appariement 1–1)."})

            lis = [li for li, _ in pairs_norm]
            ris = [ri for _, ri in pairs_norm]
            if len(set(lis)) != len(lis) or len(set(ris)) != len(ris):
                raise serializers.ValidationError({"match_pairs": "Chaque élément (gauche et droite) ne doit être apparié qu'une seule fois."})

            attrs["match_left"]  = [str(x).strip() for x in match_left]
            attrs["match_right"] = [str(x).strip() for x in match_right]
            attrs["match_pairs"] = pairs_norm

            attrs["answer_text"] = ""
            attrs["options"] = []
            attrs["correct_index"] = None

        elif at == getattr(GameStep, "ANSWER_NARR", "narration"):
            # Narration : non interactif → neutralise
            attrs["answer_text"]   = ""
            attrs["options"]       = []
            attrs["correct_index"] = None
            attrs["match_left"]    = []
            attrs["match_right"]   = []
            attrs["match_pairs"]   = []
            # indices désactivés en narration
            if hasattr(GameStep, "hints"):
                attrs["hints"] = []
            attrs["hint"] = ""
            attrs["hint_penalty"] = 0

        else:
            raise serializers.ValidationError({"answer_type": "Valeur invalide."})

        # Unicité (escape, order)
        escape = attrs.get("escape") or getattr(self.instance, "escape", None) or self.context.get("escape")
        order = attrs.get("order") or getattr(self.instance, "order", None)
        if escape is not None and order is not None:
            qs = GameStep.objects.filter(escape=escape, order=order)
            if self.instance is not None:
                qs = qs.exclude(pk=self.instance.pk)
            if qs.exists():
                raise serializers.ValidationError({"order": "Cet ordre est déjà utilisé pour cet escape."})

        return attrs

    def create(self, validated_data):
        esc = self.context.get("escape")
        if esc is not None:
            validated_data["escape"] = esc
        return super().create(validated_data)

    def update(self, instance, validated_data):
        validated_data.pop("escape", None)
        return super().update(instance, validated_data)



# ----------------- ViewSet principal -----------------

class CreatorEscapeViewSet(viewsets.ModelViewSet):
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = EscapeGameSerializer

    # ⬇️ NEW: repasse l’escape en draft quand un step change si statut published/rejected
    def _revert_to_draft_if_needed(self, escape: EscapeGame):
        cur = getattr(escape, "status", "draft")
        if cur in ("published", "rejected"):
            setattr(escape, "status", "draft")
            update_fields = ["status"]
            if hasattr(escape, "reject_reason"):
                setattr(escape, "reject_reason", "")
                update_fields.append("reject_reason")
            escape.save(update_fields=update_fields)

    def get_queryset(self):
        qs = (
            EscapeGame.objects
            .all()
            .select_related("owner")
            .prefetch_related("creator_steps")  # related_name sur GameStep.escape
            .order_by("-created_at")
        )

        user = self.request.user
        if not (user.is_staff or user.is_superuser):
            qs = qs.filter(owner=user)

        st = self.request.query_params.get("status")
        if st and st != "all":
            qs = qs.filter(status=st)
        return qs

    def get_serializer_class(self):
        if self.action == "list":
            return CreatorEscapeListSerializer
        return EscapeGameSerializer

    def list(self, request, *args, **kwargs):
        qs = self.get_queryset()
        ser = CreatorEscapeListSerializer(qs, many=True, context={"request": request})
        return Response(ser.data)

    def _filtered_payload(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Allow model fields AND serializer-only keys we care about.
        """
        EXTRA_KEYS = {"allowed_usernames"}  # serializer write-only key
        if not EG_FIELD_NAMES:
            out = dict(data)
        else:
            out = {k: v for k, v in data.items() if (k in EG_FIELD_NAMES or k in EXTRA_KEYS)}
        return out

    def _filtered_payload_step(self, data: Dict[str, Any]) -> Dict[str, Any]:
        if not GS_FIELD_NAMES:
            out = dict(data)
        else:
            out = {k: v for k, v in data.items() if k in GS_FIELD_NAMES}

        # tolérer options/matching en string JSON
        import json
        for key in ("options", "match_left", "match_right", "match_pairs", "hints"):
            val = out.get(key)
            if isinstance(val, str):
                try:
                    parsed = json.loads(val)
                    out[key] = parsed
                except Exception:
                    # Petit filet de sécurité : si c'est un string non JSON et qu'on attend une liste,
                    # on l'emballe dans une liste (utile pour 'hints' à 1 seul élément envoyé en string).
                    if key == "hints" and val.strip():
                        out[key] = [val.strip()]
        return out

    def _incoming_dict(self, request) -> Dict[str, Any]:
        """
        - Si body JSON: ne jamais aplatir les listes (on renvoie tel quel).
        - Si form/multipart: on aplatit seulement les clés *non* multi-valeurs.
        """
        # JSON → on renvoie directement un dict standard
        ct = (request.content_type or "").lower()
        if "application/json" in ct:
            return dict(request.data)

        # Form/multipart → aplatir sauf pour les clés multi
        MULTI_KEYS = {
            "options", "match_left", "match_right", "match_pairs",
            "hints", "allowed_usernames",
        }

        d: Dict[str, Any] = {}
        # Quand c'est une QueryDict, getlist existe
        getlist = getattr(request.data, "getlist", None)
        if callable(getlist):
            for k in request.data.keys():
                vals = request.data.getlist(k)
                if k in MULTI_KEYS:
                    d[k] = vals
                else:
                    d[k] = vals[0] if len(vals) == 1 else vals
            return d

        # Fallback générique
        for k in request.data.keys():
            v = request.data.get(k)
            if isinstance(v, list) and k not in MULTI_KEYS and len(v) == 1:
                d[k] = v[0]
            else:
                d[k] = v
        return d

    # ---------- CRUD escape ----------
    def create(self, request, *args, **kwargs):
        if request.user.is_staff or request.user.is_superuser:
            return Response(
                {"detail": "Les administrateurs ne peuvent pas créer des escapes. Utilisez un compte créateur."},
                status=status.HTTP_403_FORBIDDEN,
            )

        raw = self._incoming_dict(request)
        raw.pop("steps", None)
        data = self._filtered_payload(raw)

        ser = EscapeGameSerializer(data=data, context={"request": request})
        ser.is_valid(raise_exception=True)

        extra = {}
        if hasattr(EscapeGame, "status"):
            extra["status"] = "draft"
        if hasattr(EscapeGame, "owner"):
            extra["owner"] = request.user

        obj = ser.save(**extra)
        return Response(EscapeGameSerializer(obj, context={"request": request}).data, status=status.HTTP_201_CREATED)

    def update(self, request, *args, **kwargs):
        if request.user.is_staff or request.user.is_superuser:
            return Response(
                {"detail": "Les administrateurs ne peuvent pas modifier le contenu des escapes."},
                status=status.HTTP_403_FORBIDDEN,
            )

        instance = self.get_object()
        owner = getattr(instance, "owner", None)
        if owner and owner != request.user:
            return Response({"detail": "Vous n'êtes pas propriétaire de cet escape."}, status=status.HTTP_403_FORBIDDEN)

        raw = self._incoming_dict(request)
        raw.pop("steps", None)
        data = self._filtered_payload(raw)

        data.pop("status", None)
        data.pop("reject_reason", None)

        cur = getattr(instance, "status", "draft")
        if cur == "submitted":
            return Response(
                {"detail": "Escape soumis : modification interdite tant que la modération n'a pas répondu."},
                status=status.HTTP_403_FORBIDDEN,
            )

        for ro in ("id", "created_at", "rating", "owner"):
            data.pop(ro, None)

        partial = kwargs.pop("partial", False)
        ser = EscapeGameSerializer(instance, data=data, partial=partial, context={"request": request})
        ser.is_valid(raise_exception=True)
        obj = ser.save()

        if cur in ("published", "rejected"):
            setattr(obj, "status", "draft")
            update_fields = ["status"]
            if hasattr(obj, "reject_reason"):
                setattr(obj, "reject_reason", "")
                update_fields.append("reject_reason")
            obj.save(update_fields=update_fields)

        return Response(EscapeGameSerializer(obj, context={"request": request}).data)

    def partial_update(self, request, *args, **kwargs):
        kwargs["partial"] = True
        return self.update(request, *args, **kwargs)

    # ---------- Publish ----------
    @action(detail=True, methods=["post"], url_path="publish", permission_classes=[IsAdminUser])
    def publish(self, request, pk=None):
        obj = self.get_object()
        steps_qs = GameStep.objects.filter(escape=obj).order_by("order", "id")
        if steps_qs.count() < 2:
            return Response({"detail": "Il faut au moins 2 étapes pour publier."},
                            status=status.HTTP_400_BAD_REQUEST)
        setattr(obj, "status", "published")
        obj.save(update_fields=["status"])
        return Response({"ok": True, "status": getattr(obj, "status", None)})

    # ---------- Submit (créateur) ----------
    @action(detail=True, methods=["post"], url_path="submit", permission_classes=[IsAuthenticated])
    def submit(self, request, pk=None):
        obj = self.get_object()
        owner = getattr(obj, "owner", None)
        if owner and owner != request.user:
            return Response({"detail": "Vous n'êtes pas propriétaire de cet escape."}, status=status.HTTP_403_FORBIDDEN)

        cur = getattr(obj, "status", "draft")
        if cur != "draft":
            return Response({"detail": f"Soumission impossible depuis l'état: {cur}"}, status=status.HTTP_400_BAD_REQUEST)

        steps_qs = GameStep.objects.filter(escape=obj).order_by("order", "id")
        if steps_qs.count() < 2:
            return Response({"detail": "Il faut au moins 2 étapes pour soumettre."}, status=status.HTTP_400_BAD_REQUEST)

        setattr(obj, "status", "submitted")
        update_fields = ["status"]
        if hasattr(obj, "reject_reason"):
            setattr(obj, "reject_reason", "")
            update_fields.append("reject_reason")
        obj.save(update_fields=update_fields)

        return Response({"ok": True, "status": getattr(obj, "status", None)}, status=status.HTTP_200_OK)

    # ---------- Moderation ----------
    @action(detail=True, methods=["post"], url_path="reject", permission_classes=[IsAdminUser])
    def reject(self, request, pk=None):
        obj = self.get_object()
        cur = getattr(obj, "status", None)

        if cur not in ("submitted", "published"):
            return Response({"detail": f"Statut non rejetable: {cur}"}, status=status.HTTP_400_BAD_REQUEST)

        reason = (request.data.get("reason") or "").strip()
        if not reason:
            return Response({"detail": "Le motif de rejet est requis."}, status=status.HTTP_400_BAD_REQUEST)

        setattr(obj, "status", "rejected")
        update_fields = ["status"]

        wrote_reason = False
        for name in ("reject_reason", "rejection_reason", "moderation_reason", "reason"):
            if hasattr(obj, name):
                setattr(obj, name, reason)
                update_fields.append(name)
                wrote_reason = True
                break

        obj.save(update_fields=update_fields)

        return Response(
            {
                "ok": True,
                "status": getattr(obj, "status", None),
                "reject_reason": reason if wrote_reason else "",
            },
            status=status.HTTP_200_OK,
        )

    @action(detail=True, methods=["post"], url_path="approve", permission_classes=[IsAdminUser])
    def approve(self, request, pk=None):
        obj = self.get_object()
        cur = getattr(obj, "status", None)

        if cur != "submitted":
            return Response({"detail": f"Statut non approuvable: {cur}"}, status=status.HTTP_400_BAD_REQUEST)

        steps_qs = GameStep.objects.filter(escape=obj).order_by("order", "id")
        if steps_qs.count() < 2:
            return Response({"detail": "Il faut au moins 2 étapes pour publier."}, status=status.HTTP_400_BAD_REQUEST)

        setattr(obj, "status", "published")
        update_fields = ["status"]
        if hasattr(obj, "reject_reason"):
            setattr(obj, "reject_reason", "")
            update_fields.append("reject_reason")
        obj.save(update_fields=update_fields)

        return Response({"ok": True, "status": getattr(obj, "status", None)}, status=status.HTTP_200_OK)

    # ---------- Steps : list/create ----------
    @action(detail=True, methods=["get", "post"], url_path="steps")
    def steps(self, request, pk=None):
        escape = self.get_object()

        if request.method == "GET":
            qs = GameStep.objects.filter(escape=escape).order_by("order", "id")
            return Response(GameStepSerializer(qs, many=True).data)

        # 🔒 Admins ne créent pas
        if request.user.is_staff or request.user.is_superuser:
            return Response(
                {"detail": "Les administrateurs ne peuvent pas créer des étapes."},
                status=status.HTTP_403_FORBIDDEN,
            )

        # 🔒 Propriétaire uniquement
        owner = getattr(escape, "owner", None)
        if owner and owner != request.user:
            return Response(
                {"detail": "Vous n'êtes pas propriétaire de cet escape."},
                status=status.HTTP_403_FORBIDDEN,
            )

        # 🔒 Optionnel : interdire si soumis (cohérent avec update escape)
        cur = getattr(escape, "status", "draft")
        if cur == "submitted":
            return Response(
                {"detail": "Escape soumis : modification interdite tant que la modération n'a pas répondu."},
                status=status.HTTP_403_FORBIDDEN,
            )

        raw = self._incoming_dict(request)
        data = self._filtered_payload_step(raw)

        if not data.get("order"):
            last = GameStep.objects.filter(escape=escape).order_by("-order").first()
            data["order"] = (last.order + 1) if last else 1

        ser = GameStepSerializer(data=data, context={"escape": escape})
        ser.is_valid(raise_exception=True)
        with transaction.atomic():
            step = ser.save()  # create() injecte escape
            _normalize_orders(escape)

        # ⬇️ NEW : repasse en draft si nécessaire
        self._revert_to_draft_if_needed(escape)

        return Response(GameStepSerializer(step).data, status=status.HTTP_201_CREATED)

    # ---------- Step : get/patch/delete ----------
    @action(detail=True, methods=["get", "patch", "delete"], url_path=r"steps/(?P<step_id>\d+)")
    def step_detail(self, request, pk=None, step_id=None):
        escape = self.get_object()
        step = get_object_or_404(GameStep, pk=step_id, escape=escape)

        if request.method == "GET":
            return Response(GameStepSerializer(step).data)

        # 🔒 Admins ne modifient/suppriment pas
        if request.user.is_staff or request.user.is_superuser:
            return Response(
                {"detail": "Les administrateurs ne peuvent pas modifier/supprimer des étapes."},
                status=status.HTTP_403_FORBIDDEN,
            )

        # 🔒 Propriétaire
        owner = getattr(escape, "owner", None)
        if owner and owner != request.user:
            return Response(
                {"detail": "Vous n'êtes pas propriétaire de cet escape."},
                status=status.HTTP_403_FORBIDDEN,
            )

        if request.method == "PATCH":
            # 🔒 Optionnel : interdire si soumis
            cur = getattr(escape, "status", "draft")
            if cur == "submitted":
                return Response(
                    {"detail": "Escape soumis : modification interdite tant que la modération n'a pas répondu."},
                    status=status.HTTP_403_FORBIDDEN,
                )

            raw = self._incoming_dict(request)
            data = self._filtered_payload_step(raw)
            data.pop("escape", None)
            data.pop("id", None)

            ser = GameStepSerializer(step, data=data, partial=True, context={"escape": escape})
            ser.is_valid(raise_exception=True)
            with transaction.atomic():
                step = ser.save()
                _normalize_orders(escape)

            # ⬇️ NEW : repasse en draft si nécessaire
            self._revert_to_draft_if_needed(escape)

            return Response(GameStepSerializer(step).data)

        # DELETE
        # 🔒 Optionnel : interdire si soumis
        cur = getattr(escape, "status", "draft")
        if cur == "submitted":
            return Response(
                {"detail": "Escape soumis : modification interdite tant que la modération n'a pas répondu."},
                status=status.HTTP_403_FORBIDDEN,
            )

        with transaction.atomic():
            step.delete()
            _normalize_orders(escape)

        # ⬇️ NEW : repasse en draft si nécessaire
        self._revert_to_draft_if_needed(escape)

        return Response(status=status.HTTP_204_NO_CONTENT)

    # ---------- Step : déplacer d'un cran (haut/bas) ----------
    @action(detail=True, methods=["post"], url_path=r"steps/(?P<step_id>\d+)/move")
    def move_step(self, request, pk=None, step_id=None):
        """
        Échange l'ordre de cette étape avec sa voisine immédiate (haut/bas).

        Fait exprès de ne PAS passer par GameStepSerializer.save() : un swap
        classique en 2 PATCH successifs (chacun passant par validate() +
        _normalize_orders()) entre en collision avec la contrainte d'unicité
        (escape, order) — la voisine détient encore l'ordre cible au moment
        du 1er appel, et _normalize_orders() annule toute valeur temporaire
        "hors plage" dès qu'elle tourne après une écriture individuelle.
        Ici, les 3 écritures se font dans la MÊME transaction, sans repasser
        par la vue/le serializer entre chacune, donc _normalize_orders() ne
        s'exécute qu'une fois à la toute fin, une fois le swap réellement
        posé en base.
        """
        escape = self.get_object()

        if request.user.is_staff or request.user.is_superuser:
            return Response(
                {"detail": "Les administrateurs ne peuvent pas modifier des étapes."},
                status=status.HTTP_403_FORBIDDEN,
            )
        owner = getattr(escape, "owner", None)
        if owner and owner != request.user:
            return Response(
                {"detail": "Vous n'êtes pas propriétaire de cet escape."},
                status=status.HTTP_403_FORBIDDEN,
            )
        cur = getattr(escape, "status", "draft")
        if cur == "submitted":
            return Response(
                {"detail": "Escape soumis : modification interdite tant que la modération n'a pas répondu."},
                status=status.HTTP_403_FORBIDDEN,
            )

        step = get_object_or_404(GameStep, pk=step_id, escape=escape)
        direction = (request.data or {}).get("direction")
        if direction not in ("up", "down"):
            return Response({"detail": "direction doit être 'up' ou 'down'."}, status=400)

        steps = list(GameStep.objects.filter(escape=escape).order_by("order", "id"))
        idx = next((i for i, s in enumerate(steps) if s.pk == step.pk), None)
        if idx is None:
            return Response({"detail": "Étape introuvable."}, status=404)

        new_idx = idx - 1 if direction == "up" else idx + 1
        if new_idx < 0 or new_idx >= len(steps):
            return Response({"detail": "Déplacement impossible (déjà en bout de liste)."}, status=400)

        other = steps[new_idx]
        step_order, other_order = step.order, other.order

        with transaction.atomic():
            TEMP_ORDER = 2_000_000_000  # hors de toute plage d'order réelle
            GameStep.objects.filter(pk=step.pk).update(order=TEMP_ORDER)
            GameStep.objects.filter(pk=other.pk).update(order=step_order)
            GameStep.objects.filter(pk=step.pk).update(order=other_order)
            _normalize_orders(escape)

        self._revert_to_draft_if_needed(escape)

        fresh = GameStep.objects.filter(escape=escape).order_by("order", "id")
        return Response(GameStepSerializer(fresh, many=True).data)
