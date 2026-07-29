"""
Chargement et validation du schéma des questionnaires.

`schema.json` est la SOURCE DE VÉRITÉ unique (portée aussi dans l'app mobile).
Ce module la charge une fois, l'expose au reste du back (validation, CSV,
injection dans la page HTML) et fournit la validation d'une soumission.
"""
import json
import functools
from pathlib import Path

SCHEMA_PATH = Path(__file__).resolve().parent / "schema.json"

# Sentinelle utilisée dans schema.json pour référencer la liste des parcours
# sans la dupliquer. Remplacée à la volée par get_escapes() (aujourd'hui la
# liste statique du schéma, demain une requête sur EscapeGame — cf. brief 7.3).
ESCAPES_SENTINEL = "$escapes"

# Types dont la valeur stockée est un entier borné
INT_RANGES = {
    "likert": (1, 5),
    "nps": (0, 10),
}


class SurveyValidationError(Exception):
    """Erreur de validation d'une soumission (→ HTTP 400)."""


@functools.lru_cache(maxsize=1)
def _raw_schema():
    with open(SCHEMA_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def get_escapes():
    """Liste des parcours proposés au choix.

    Pour l'instant on lit la liste statique du schéma. Pour l'alimenter depuis
    la base (brief 7.3), remplacer le corps par une requête EscapeGame, ex :
        return [f"{e.title} ({e.city})" for e in EscapeGame.objects.filter(...)]
    """
    return list(_raw_schema().get("escapes", []))


def _resolve(node):
    """Remplace récursivement la sentinelle $escapes par la vraie liste."""
    if isinstance(node, dict):
        return {k: _resolve(v) for k, v in node.items()}
    if isinstance(node, list):
        return [_resolve(v) for v in node]
    if node == ESCAPES_SENTINEL:
        return get_escapes()
    return node


def load_schema():
    """Schéma complet, sentinelles résolues. Consommé par le front (injection)
    et par la route /api/survey/schema."""
    raw = _raw_schema()
    return {
        "config": raw.get("config", {}),
        "escapes": get_escapes(),
        "surveys": _resolve(raw.get("surveys", {})),
    }


def get_survey(key):
    return load_schema()["surveys"].get(key)


def _questions(survey):
    """Aplatit les questions d'un questionnaire en dict {id: question}.

    Inclut les questions masquées (`hidden`) : elles restent *connues* du
    serveur, donc acceptées si un client (app en transition) les envoie encore.
    Elles ne sont simplement plus rendues ni exigées (cf. _hidden_qids)."""
    out = {}
    for section in survey.get("sections", []):
        for q in section.get("questions", []):
            out[q["id"]] = q
    return out


def _hidden_qids(survey):
    """q.id des questions retirées du formulaire : flag `hidden` sur la question
    ou sur sa section. Ces questions ne peuvent pas bloquer un envoi (required)."""
    hidden = set()
    for section in survey.get("sections", []):
        sec_hidden = bool(section.get("hidden"))
        for q in section.get("questions", []):
            if sec_hidden or q.get("hidden"):
                hidden.add(q["id"])
    return hidden


def hidden_qids(key):
    """q.id retirés du formulaire (flag `hidden` sur la question ou sa section)
    pour un questionnaire donné. Sert à exclure ces éléments du rapport admin
    (colonnes CSV, indicateurs, réponses brutes). Les données restent en base :
    réafficher l'élément les fait réapparaître."""
    survey = get_survey(key)
    return _hidden_qids(survey) if survey else set()


def question_order(key, include_hidden=False):
    """Liste ordonnée des q.id d'un questionnaire (colonnes CSV).

    Par défaut, exclut les questions masquées (`hidden`) : elles ne doivent plus
    figurer dans le rapport admin. Passer include_hidden=True pour l'ordre complet."""
    survey = get_survey(key)
    if not survey:
        return []
    hidden = set() if include_hidden else _hidden_qids(survey)
    ids = []
    for section in survey.get("sections", []):
        for q in section.get("questions", []):
            if q["id"] not in hidden:
                ids.append(q["id"])
    return ids


def _is_visible(question, answers):
    """Réplique la logique client `visible()` : une question conditionnée par
    showIf n'est visible que si la réponse cible fait partie des valeurs `is`."""
    cond = question.get("showIf")
    if not cond:
        return True
    val = answers.get(cond["q"])
    return val is not None and val in cond["is"]


def _validate_value(question, value):
    """Valide/normalise une valeur selon le type de question. Renvoie la valeur
    normalisée ou lève SurveyValidationError."""
    qtype = question["type"]
    qid = question["id"]

    if qtype in INT_RANGES:
        lo, hi = INT_RANGES[qtype]
        # les booléens sont des int en Python : on les refuse explicitement
        if isinstance(value, bool) or not isinstance(value, int):
            raise SurveyValidationError(f"'{qid}' attend un entier {lo}–{hi}.")
        if not (lo <= value <= hi):
            raise SurveyValidationError(f"'{qid}' hors bornes ({lo}–{hi}).")
        return value

    if qtype in ("single", "balance"):
        options = question.get("options", [])
        if value not in options:
            raise SurveyValidationError(f"'{qid}' : valeur non prévue par le schéma.")
        return value

    if qtype in ("text", "shorttext"):
        if not isinstance(value, str):
            raise SurveyValidationError(f"'{qid}' attend du texte.")
        return value.strip()

    raise SurveyValidationError(f"'{qid}' : type de question inconnu.")


def validate_submission(survey_key, answers):
    """Valide une soumission contre le schéma. Le front n'est pas une garantie.

    - questionnaire inconnu → 400
    - q.id inconnu → 400
    - valeur hors bornes / hors options / mauvais type → 400
    - question obligatoire *visible* manquante → 400
    Les réponses des questions masquées (showIf non satisfait) sont ignorées,
    comme côté client.

    Renvoie le dict `reponses` nettoyé (valeurs normalisées, masquées retirées).
    """
    survey = get_survey(survey_key)
    if not survey:
        raise SurveyValidationError(f"Questionnaire inconnu : '{survey_key}'.")

    if not isinstance(answers, dict):
        raise SurveyValidationError("'reponses' doit être un objet.")

    questions = _questions(survey)

    # 1) Rejet des q.id inconnus
    unknown = set(answers) - set(questions)
    if unknown:
        raise SurveyValidationError(
            "Question(s) inconnue(s) : " + ", ".join(sorted(unknown))
        )

    # 2) Validation valeur par valeur
    cleaned = {}
    for qid, value in answers.items():
        cleaned[qid] = _validate_value(questions[qid], value)

    # 3) On retire les réponses aux questions masquées (cohérence avec le front)
    visible = {qid for qid, q in questions.items() if _is_visible(q, cleaned)}
    cleaned = {qid: v for qid, v in cleaned.items() if qid in visible}

    # 4) Obligatoires visibles manquants (on ignore les questions masquées)
    hidden = _hidden_qids(survey)
    missing = [
        qid for qid, q in questions.items()
        if q.get("required") and qid not in hidden
        and _is_visible(q, cleaned) and cleaned.get(qid) in (None, "")
    ]
    if missing:
        raise SurveyValidationError(
            "Réponse(s) obligatoire(s) manquante(s) : " + ", ".join(missing)
        )

    return cleaned
