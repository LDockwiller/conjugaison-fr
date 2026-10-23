#!/usr/bin/env python3
"""Conjugates a French verb, Bescherelle style, and prints JSON.

Usage: conjugue.py <verbe> [--pronominal]

<verbe> can be an infinitive ("aller"), a pronominal infinitive ("se laver",
"s'asseoir"), or a conjugated form ("vais", "fîmes"), which is traced back
to its infinitive. Unknown words get spelling suggestions.

Simple tenses come from Verbiste's templates (data/verbes.json, see
tools/build-data.py). Compound tenses, the auxiliary, elision and the
pronominal form are built here.
"""
import difflib
import json
import sys
import unicodedata
from pathlib import Path

DATA = json.loads((Path(__file__).resolve().parent / "data/verbes.json").read_text())
VERBS = DATA["verbs"]
TEMPLATES = DATA["templates"]

VOWELS = set("aeiouyàâäéèêëîïôöûüœæ")
PRONOUNS = ["je", "tu", "il", "nous", "vous", "ils"]
REFLEXIVE = ["me", "te", "se", "nous", "vous", "se"]
IMPERATIVE_PERSONS = [1, 3, 4]
IMPERATIVE_REFLEXIVE = ["toi", "nous", "vous"]

# Verbs conjugated with "être" in their compound tenses (when intransitive).
ETRE_VERBS = {
    "aller", "arriver", "advenir", "décéder", "devenir", "échoir", "entrer",
    "intervenir", "mourir", "naître", "partir", "parvenir", "provenir",
    "redevenir", "renaître", "repartir", "rester", "retomber", "revenir",
    "survenir", "tomber", "venir",
}
# Verbs that take "être" when intransitive, "avoir" with a direct object.
ETRE_OR_AVOIR = {
    "descendre", "monter", "passer", "redescendre", "remonter", "rentrer",
    "ressortir", "retourner", "sortir",
}
SECOND_GROUP_TEMPLATES = {"fin:ir", "ha:ïr", "fl:eurir", "amu:ïr"}

COMPOUND = {
    # compound tense: auxiliary's simple tense
    "ind_passe_compose": "ind_present",
    "ind_plus_que_parfait": "ind_imparfait",
    "ind_passe_anterieur": "ind_passe_simple",
    "ind_futur_anterieur": "ind_futur",
    "subj_passe": "subj_present",
    "subj_plus_que_parfait": "subj_imparfait",
    "cond_passe": "cond_present",
}

LAYOUT = [
    ("Indicatif", [
        ("Présent", "ind_present"), ("Passé composé", "ind_passe_compose"),
        ("Imparfait", "ind_imparfait"), ("Plus-que-parfait", "ind_plus_que_parfait"),
        ("Passé simple", "ind_passe_simple"), ("Passé antérieur", "ind_passe_anterieur"),
        ("Futur simple", "ind_futur"), ("Futur antérieur", "ind_futur_anterieur"),
    ]),
    ("Subjonctif", [
        ("Présent", "subj_present"), ("Passé", "subj_passe"),
        ("Imparfait", "subj_imparfait"), ("Plus-que-parfait", "subj_plus_que_parfait"),
    ]),
    ("Conditionnel", [
        ("Présent", "cond_present"), ("Passé", "cond_passe"),
    ]),
    ("Impératif", [
        ("Présent", "imperatif"), ("Passé", "imperatif_passe"),
    ]),
]


def fold(text):
    """Lowercase without accents, for forgiving matches ("etre" -> "être")."""
    return "".join(c for c in unicodedata.normalize("NFD", text.lower())
                   if unicodedata.category(c) != "Mn")


def starts_with_vowel(word, aspirate=False):
    if not word:
        return False
    c = word[0].lower()
    return c in VOWELS or (c == "h" and not aspirate)


def stem_and_template(infinitive):
    template, aspirate = VERBS[infinitive]
    suffix = template.split(":", 1)[1]
    return infinitive[: len(infinitive) - len(suffix)], TEMPLATES[template], bool(aspirate)


def simple_forms(infinitive, marked=False):
    """{tense: [[variants] per person]} with the stem applied. `marked` wraps
    each ending in [brackets] so the panel can highlight it."""
    stem, template, _ = stem_and_template(infinitive)
    if marked:
        return {tense: [[stem + "[" + v + "]" if v else stem for v in person] for person in persons]
                for tense, persons in template.items()}
    return {tense: [[stem + v for v in person] for person in persons]
            for tense, persons in template.items()}


def auxiliary_of(infinitive, pronominal):
    if pronominal or infinitive in ETRE_VERBS or infinitive in ETRE_OR_AVOIR:
        return "être"
    return "avoir"


def group_of(infinitive, template):
    if infinitive in ("être", "avoir"):
        return "auxiliaire"
    if infinitive.endswith("er") and infinitive != "aller":
        return "1er groupe"
    if template in SECOND_GROUP_TEMPLATES:
        return "2e groupe"
    return "3e groupe"


def subject(person, verb_form, aspirate, pronominal, subjunctive):
    """Builds "que je m'", "il se ", "j'" ... in front of verb_form."""
    words = []
    pronoun = PRONOUNS[person]
    if subjunctive:
        words.append("qu'" if pronoun.startswith("i") else "que ")
    if pronominal:
        refl = REFLEXIVE[person]
        elide_refl = refl in ("me", "te", "se") and starts_with_vowel(verb_form, aspirate)
        words.append(pronoun + " ")
        words.append(refl[0] + "'" if elide_refl else refl + " ")
    elif pronoun == "je" and starts_with_vowel(verb_form, aspirate):
        words.append("j'")
    else:
        words.append(pronoun + " ")
    return "".join(words)


def conjugate(infinitive, pronominal=False):
    _, _, aspirate = stem_and_template(infinitive)
    template = VERBS[infinitive][0]
    forms = simple_forms(infinitive)
    marked = simple_forms(infinitive, marked=True)
    aux = auxiliary_of(infinitive, pronominal)
    aux_forms = simple_forms(aux)
    pp = forms["part_passe"]  # [masc sing, masc plur, fem sing, fem plur]
    pp_ms = pp[0][0] if pp and pp[0] else ""
    pp_mp = pp[1][0] if len(pp) > 1 and pp[1] else pp_ms
    agrees = aux == "être"

    # Persons this verb has at all (impersonal verbs only have "il").
    personal = ["ind_present", "ind_imparfait", "ind_futur", "ind_passe_simple",
                "cond_present", "subj_present", "subj_imparfait"]
    persons = [p for p in range(6) if any(forms[t][p] for t in personal if len(forms[t]) > p)]

    def line(person, variants, subjunctive, shown=None):
        return subject(person, variants[0], aspirate, pronominal, subjunctive) + " / ".join(shown or variants)

    def participle_for(person):
        return pp_mp if agrees and person >= 3 else pp_ms

    tenses = {}
    for tense in ("ind_present", "ind_imparfait", "ind_passe_simple", "ind_futur",
                  "cond_present", "subj_present", "subj_imparfait"):
        subjunctive = tense.startswith("subj")
        tenses[tense] = [line(p, forms[tense][p], subjunctive, marked[tense][p])
                         for p in persons if forms[tense][p]]

    for tense, aux_tense in COMPOUND.items():
        subjunctive = tense.startswith("subj")
        tenses[tense] = [line(p, [aux_forms[aux_tense][p][0] + " " + participle_for(p)], subjunctive)
                         for p in persons if pp_ms]

    imperative = []
    imperative_past = []
    for i, p in enumerate(IMPERATIVE_PERSONS):
        variants = marked["imperatif"][i] if i < len(marked["imperatif"]) else []
        if not variants:
            continue
        if pronominal:
            imperative.append(" / ".join(v + "-" + IMPERATIVE_REFLEXIVE[i] for v in variants))
        else:
            imperative.append(" / ".join(variants))
            if pp_ms:
                imperative_past.append(aux_forms["imperatif"][i][0] + " " + participle_for(p))
    tenses["imperatif"] = imperative
    tenses["imperatif_passe"] = imperative_past

    modes = []
    for mode, layout in LAYOUT:
        rows = [{"name": name, "lines": tenses[key]} for name, key in layout if tenses[key]]
        if rows:
            modes.append({"name": mode, "tenses": rows})

    reflexive_inf = ""
    if pronominal:
        reflexive_inf = "s'" if starts_with_vowel(infinitive, aspirate) else "se "
    pp_present = forms["part_present"][0][0] if forms["part_present"] and forms["part_present"][0] else ""
    aux_inf = "être" if aux == "être" else "avoir"
    aux_present_part = "étant" if aux == "être" else "ayant"
    reflexive_ger = ("s'" if starts_with_vowel(pp_present, aspirate) else "se ") if pronominal else ""

    impersonal = [
        {"name": "Infinitif", "tenses": [
            {"name": "Présent", "lines": [reflexive_inf + infinitive]},
            {"name": "Passé", "lines": [("s'" if pronominal else "") + aux_inf + " " + pp_ms] if pp_ms else []},
        ]},
        {"name": "Participe", "tenses": [
            {"name": "Présent", "lines": [pp_present] if pp_present else []},
            {"name": "Passé", "lines": [", ".join(f[0] for f in pp if f)] if pp_ms else []},
        ]},
        {"name": "Gérondif", "tenses": [
            {"name": "Présent", "lines": ["en " + reflexive_ger + pp_present] if pp_present else []},
            {"name": "Passé", "lines": ["en " + ("s'" if pronominal else "") + aux_present_part + " " + pp_ms] if pp_ms else []},
        ]},
    ]
    for mode in impersonal:
        mode["tenses"] = [t for t in mode["tenses"] if t["lines"]]
    modes += [m for m in impersonal if m["tenses"]]

    aux_note = ""
    if not pronominal and infinitive in ETRE_OR_AVOIR:
        aux_note = "avoir quand il a un complément d'objet direct"
    elif not pronominal and len(persons) == 1:
        aux_note = "verbe impersonnel"

    return {
        "ok": True,
        "verb": infinitive,
        "title": reflexive_inf + infinitive,
        "pronominal": pronominal,
        "group": group_of(infinitive, template),
        "auxiliary": aux,
        "auxNote": aux_note,
        "model": template.replace(":", ""),
        "modes": modes,
    }


def reverse_lookup(word):
    """Infinitives having `word` among their simple forms."""
    hits = []
    for infinitive in VERBS:
        forms = simple_forms(infinitive)
        if any(word in variants for persons in forms.values() for variants in persons):
            hits.append(infinitive)
    return hits


def parse_query(raw):
    text = raw.strip().lower().replace("’", "'")
    pronominal = False
    for prefix in ("se ", "s'"):
        if text.startswith(prefix):
            text, pronominal = text[len(prefix):].strip(), True
            break
    return text, pronominal


def lookup(raw, force_pronominal=False):
    word, pronominal = parse_query(raw)
    pronominal = pronominal or force_pronominal
    if not word:
        return {"ok": False, "error": "empty", "suggestions": []}

    if word in VERBS:
        return conjugate(word, pronominal)

    folded = {}
    for infinitive in VERBS:
        folded.setdefault(fold(infinitive), []).append(infinitive)
    same = folded.get(fold(word), [])
    if len(same) == 1:
        return conjugate(same[0], pronominal)

    hits = reverse_lookup(word)
    if len(hits) == 1:
        result = conjugate(hits[0], pronominal)
        result["note"] = "« " + word + " » est une forme du verbe " + hits[0] + "."
        return result
    if hits:
        return {"ok": False, "error": "ambiguous", "query": word,
                "message": "« " + word + " » est une forme de plusieurs verbes.",
                "suggestions": hits[:12]}

    close = difflib.get_close_matches(fold(word), list(folded), n=8, cutoff=0.75)
    suggestions = same + [v for key in close for v in folded[key] if v not in same]
    return {"ok": False, "error": "notfound", "query": word,
            "message": "Verbe inconnu : « " + word + " ».",
            "suggestions": suggestions[:8]}


def main():
    args = [a for a in sys.argv[1:] if a != "--pronominal"]
    if not args:
        print("Usage: conjugue.py <verbe> [--pronominal]", file=sys.stderr)
        sys.exit(2)
    result = lookup(" ".join(args), "--pronominal" in sys.argv[1:])
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
