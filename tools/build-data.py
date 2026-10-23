#!/usr/bin/env python3
"""Converts Verbiste's French XML data into data/verbes.json.

Usage: tools/build-data.py verbs-fr.xml conjugations-fr.xml > data/verbes.json

Both XML files come from Verbiste by Pierre Sarrazin (GPL-2.0-or-later),
as shipped by verbecc (https://github.com/bretttolbert/verbecc). The JSON
keeps only what conjugue.py needs:
  verbs:     {infinitive: [template, aspirate_h]}
  templates: {template: {tense: [[variant, ...] per person]}}
"""
import json
import sys
import xml.etree.ElementTree as ET

TENSES = {
    ("Infinitif", "infinitif-présent"): "infinitif",
    ("Indicatif", "présent"): "ind_present",
    ("Indicatif", "imparfait"): "ind_imparfait",
    ("Indicatif", "futur-simple"): "ind_futur",
    ("Indicatif", "passé-simple"): "ind_passe_simple",
    ("Conditionnel", "présent"): "cond_present",
    ("Subjonctif", "présent"): "subj_present",
    ("Subjonctif", "imparfait"): "subj_imparfait",
    ("Imperatif", "imperatif-présent"): "imperatif",
    ("Participe", "participe-présent"): "part_present",
    ("Participe", "participe-passé"): "part_passe",
}


def main(verbs_path, conj_path):
    verbs = {}
    for v in ET.parse(verbs_path).getroot().iter("v"):
        verbs[v.findtext("i")] = [v.findtext("t"), 1 if v.find("aspirate-h") is not None else 0]

    templates = {}
    for t in ET.parse(conj_path).getroot().iter("template"):
        out = {}
        for mode in t:
            for tense in mode:
                key = TENSES.get((mode.tag, tense.tag))
                if key:
                    out[key] = [[i.text or "" for i in p.findall("i")] for p in tense.findall("p")]
        templates[t.get("name")] = out

    json.dump({"verbs": verbs, "templates": templates}, sys.stdout,
              ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
