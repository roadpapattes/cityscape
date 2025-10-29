# games/views_creator.py
from typing import Any, Dict, Set
import re

from django.db import transaction
from django.shortcuts import get_object_or_404
from rest_framework import viewsets, permissions, status, serializers
from rest_framework.decorators import action
from rest_framework.response import Response

from .models import EscapeGame, GameStep


def _field_names(model) -> Set[str]:
    names: Set[str] = set()
    for f in model._meta.get_fields():
        if getattr(f, "concrete", False) and getattr(f, "attname", None):
            names.add(f.name)
        elif hasattr(f, "name"):
            names.add(f.name)
    return names


# Champs du modèle (pour filtrer proprement les payloads)
EG_FIELD_NAMES = _field_names(EscapeGame)
GS_FIELD_NAMES = _field_names(GameStep)


# ----------------- Serializers -----------------

class EscapeGameSerializer(serializers.ModelSerializer):
    class Meta:
        model = EscapeGame
        fields = "__all__"
        read_only_fields = tuple(
            n for n in ("id", "created_at", "rating", "owner") if n in EG_FIELD_NAMES
        )


class GameStepSerializer(serializers.ModelSerializer):
    class Meta:
        model = GameStep
        fields = "__all__"
        # on empêche de changer l'escape par PATCH (assigné côté serveur à la création)
        read_only_fields = ("id", "escape",)

    def validate(self, attrs):
        """
        - Cohérence des champs selon answer_type.
        - Unicité (escape, order) côté API (en plus de la contrainte DB).
        - Si is_last = True, final_message et rating_code (4 chiffres) requis.
        """
        # --- answer_type ---
        at = attrs.get("answer_type", getattr(self.instance, "answer_type", GameStep.ANSWER_TEXT))

        if at == GameStep.ANSWER_TEXT:
            txt = attrs.get("answer_text", getattr(self.instance, "answer_text", "")) or ""
            if not str(txt).strip():
                raise serializers.ValidationError({"answer_text": 'Requis pour "Texte libre".'})
        elif at == GameStep.ANSWER_MCQ:
            opts = attrs.get("options", getattr(self.instance, "options", []))
            if opts is None:
                opts = []
            if not isinstance(opts, (list, tuple)):
                raise serializers.ValidationError({"options": "Doit être une liste de chaînes."})
            if len(opts) < 2:
                raise serializers.ValidationError({"options": "Au moins 2 options requises."})
            ci = attrs.get("correct_index", getattr(self.instance, "correct_index", None))
            if ci is None or not isinstance(ci, int) or ci < 0 or ci >= len(opts):
                raise serializers.ValidationError({"correct_index": "Indice hors bornes."})
        else:
            raise serializers.ValidationError({"answer_type": "Valeur invalide."})

        # --- unicité (escape, order) ---
        escape = attrs.get("escape") or getattr(self.instance, "escape", None) or self.context.get("escape")
        order = attrs.get("order") or getattr(self.instance, "order", None)
        if escape is not None and order is not None:
            qs = GameStep.objects.filter(escape=escape, order=order)
            if self.instance is not None:
                qs = qs.exclude(pk=self.instance.pk)
            if qs.exists():
                raise serializers.ValidationError({"order": "Cet ordre est déjà utilisé pour cet escape."})

        # --- étape finale ---
        is_last = attrs.get("is_last", getattr(self.instance, "is_last", False))
        if is_last:
            fm = attrs.get("final_message", getattr(self.instance, "final_message", "")) or ""
            rc = attrs.get("rating_code", getattr(self.instance, "rating_code", "")) or ""
            if not fm.strip():
                raise serializers.ValidationError({"final_message": "Requis si Dernière étape."})
            if not re.fullmatch(r"\d{4}", rc):
                raise serializers.ValidationError({"rating_code": "Code à 4 chiffres requis."})

        return attrs

    def create(self, validated_data):
        """
        Injecte l'escape (read-only) fourni par la vue via context.
        Empêche escape=NULL.
        """
        escape = self.context.get("escape")
        if escape is None:
            raise serializers.ValidationError({"escape": "Escape manquant pour la création de l'étape."})
        validated_data["escape"] = escape
        return super().create(validated_data)


# ----------------- Utils internes -----------------

def _normalize_orders(escape: EscapeGame):
    """
    Recompacte les ordres à 1..N en gardant l'ordre actuel.
    """
    steps = list(GameStep.objects.filter(escape=escape).order_by("order", "id"))
    for i, s in enumerate(steps, start=1):
        if s.order != i:
            GameStep.objects.filter(pk=s.pk).update(order=i)


# ----------------- ViewSet principal -----------------

class CreatorEscapeViewSet(viewsets.ModelViewSet):
    """
    /api/creator/escapes/              [GET, POST]
    /api/creator/escapes/{pk}/         [GET, PATCH, PUT, DELETE]
    /api/creator/escapes/{pk}/publish/ [POST]  -> admin uniquement

    Steps imbriqués :
    /api/creator/escapes/{pk}/steps/                 [GET (list), POST (create)]
    /api/creator/escapes/{pk}/steps/{step_id}/       [GET, PATCH, DELETE]
    """
    serializer_class = EscapeGameSerializer
    permission_classes = [permissions.IsAuthenticated]

    # ---------- queryset & list ----------
    def get_queryset(self):
        qs = EscapeGame.objects.all()
        # Admin voit tout, sinon seulement ses propres jeux (si owner existe)
        if "owner" in EG_FIELD_NAMES and not (self.request.user.is_staff or self.request.user.is_superuser):
            qs = qs.filter(owner=self.request.user)
        return qs

    def list(self, request, *args, **kwargs):
        qs = self.get_queryset()
        # Filtre status côté admin (?status=draft|published|archived|all)
        st = request.query_params.get("status")
        if (request.user.is_staff or request.user.is_superuser) and st and st != "all" and "status" in EG_FIELD_NAMES:
            qs = qs.filter(status=st)
        ser = self.get_serializer(qs, many=True)
        return Response(ser.data)

    # ---------- outils payload ----------
    def _filtered_payload(self, data: Dict[str, Any]) -> Dict[str, Any]:
        return {k: v for k, v in data.items() if k in EG_FIELD_NAMES}

    def _filtered_payload_step(self, data: Dict[str, Any]) -> Dict[str, Any]:
        out: Dict[str, Any] = {k: v for k, v in data.items() if k in GS_FIELD_NAMES}
        # tolère options en string JSON
        opts = out.get("options")
        if isinstance(opts, str):
            try:
                import json
                val = json.loads(opts)
                if isinstance(val, list):
                    out["options"] = val
            except Exception:
                pass
        return out

    def _incoming_dict(self, request) -> Dict[str, Any]:
        d: Dict[str, Any] = {}
        # DRF parse déjà, mais on normalise listes singleton
        for k in request.data.keys():
            v = request.data.get(k)
            d[k] = v[0] if isinstance(v, list) and len(v) == 1 else v
        return d

    # ---------- CRUD escape ----------
    def create(self, request, *args, **kwargs):
        raw = self._incoming_dict(request)
        raw.pop("steps", None)  # toléré côté client
        data = self._filtered_payload(raw)

        ser = self.get_serializer(data=data)
        ser.is_valid(raise_exception=True)

        extra = {}
        if "status" in EG_FIELD_NAMES and not ser.validated_data.get("status"):
            extra["status"] = "draft"
        if "owner" in EG_FIELD_NAMES:
            extra["owner"] = request.user

        obj = ser.save(**extra)
        return Response(self.get_serializer(obj).data, status=status.HTTP_201_CREATED)

    def update(self, request, *args, **kwargs):
        partial = kwargs.pop("partial", False)
        instance = self.get_object()

        raw = self._incoming_dict(request)
        raw.pop("steps", None)
        data = self._filtered_payload(raw)
        for ro in ("id", "created_at", "rating", "owner"):
            data.pop(ro, None)

        ser = self.get_serializer(instance, data=data, partial=partial)
        ser.is_valid(raise_exception=True)
        obj = ser.save()
        return Response(self.get_serializer(obj).data)

    def partial_update(self, request, *args, **kwargs):
        kwargs["partial"] = True
        return self.update(request, *args, **kwargs)

    @action(detail=True, methods=["post"], url_path="publish")
    def publish(self, request, pk=None):
        obj = self.get_object()

        if not (request.user.is_staff or request.user.is_superuser):
            return Response({"detail": "Only admins can publish."},
                            status=status.HTTP_403_FORBIDDEN)

        if "status" not in EG_FIELD_NAMES:
            return Response({"detail": "Le champ 'status' n'existe pas sur EscapeGame."},
                            status=status.HTTP_400_BAD_REQUEST)

        setattr(obj, "status", "published")
        obj.save(update_fields=["status"])
        return Response({"ok": True, "status": getattr(obj, "status", None)})

    # ---------- Steps : list/create ----------
    @action(detail=True, methods=["get", "post"], url_path="steps")
    def steps(self, request, pk=None):
        escape = self.get_object()

        if request.method == "GET":
            qs = GameStep.objects.filter(escape=escape).order_by("order", "id")
            return Response(GameStepSerializer(qs, many=True).data)

        # POST create
        raw = self._incoming_dict(request)
        data = self._filtered_payload_step(raw)

        # si order non fourni -> append à la fin
        if not data.get("order"):
            last = GameStep.objects.filter(escape=escape).order_by("-order").first()
            data["order"] = (last.order + 1) if last else 1

        ser = GameStepSerializer(data=data, context={"escape": escape})
        ser.is_valid(raise_exception=True)
        with transaction.atomic():
            step = ser.save()
            # Si cette étape est marquée comme "dernière", on désactive les autres
            if getattr(step, "is_last", False):
                GameStep.objects.filter(escape=escape).exclude(pk=step.pk).update(is_last=False)
            _normalize_orders(escape)
        return Response(GameStepSerializer(step).data, status=status.HTTP_201_CREATED)

    # ---------- Step : get/patch/delete ----------
    @action(detail=True, methods=["get", "patch", "delete"], url_path=r"steps/(?P<step_id>\d+)")
    def step_detail(self, request, pk=None, step_id=None):
        escape = self.get_object()
        step = get_object_or_404(GameStep, pk=step_id, escape=escape)

        if request.method == "GET":
            return Response(GameStepSerializer(step).data)

        if request.method == "PATCH":
            raw = self._incoming_dict(request)
            data = self._filtered_payload_step(raw)
            # RO
            data.pop("escape", None)
            data.pop("id", None)

            ser = GameStepSerializer(step, data=data, partial=True, context={"escape": escape})
            ser.is_valid(raise_exception=True)
            with transaction.atomic():
                step = ser.save()
                # Si cette étape est la "dernière", on désactive ce flag sur les autres
                if getattr(step, "is_last", False):
                    GameStep.objects.filter(escape=escape).exclude(pk=step.pk).update(is_last=False)
                _normalize_orders(escape)
            return Response(GameStepSerializer(step).data)

        # DELETE
        with transaction.atomic():
            step.delete()
            _normalize_orders(escape)
        return Response(status=status.HTTP_204_NO_CONTENT)
