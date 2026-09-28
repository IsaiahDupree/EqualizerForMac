#!/usr/bin/env python3
"""Validate and publish App Store listing copy through the App Store Connect API.

The source of truth for the next Sonance EQ release is kept here in English and French. The tool is
fail-closed: local validation requires no credentials, live inspection is read-only with ``--dry-run``,
and writes are allowed only for a version in PREPARE_FOR_SUBMISSION.

Examples:
  python3 Tools/asc/metadata.py --validate-only
  python3 Tools/asc/metadata.py --version 1.0.6 --dry-run
  python3 Tools/asc/metadata.py --version 1.0.6 --apply
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import re

from api import api, get_app


APP_NAME = "Sonance EQ"
SUPPORT_URL = "https://github.com/IsaiahDupree/EqualizerForMac"
MARKETING_URL = "https://isaiahdupree.github.io/sonance-apps/sonance-eq/"
PRIVACY_URL = "https://isaiahdupree.github.io/sonance-apps/privacy/"
EDITABLE_VERSION_STATES = {"PREPARE_FOR_SUBMISSION"}


@dataclass(frozen=True)
class AppStoreCopy:
    locale: str
    subtitle: str
    description: str
    keywords: str
    promotional_text: str
    whats_new: str


LOCALIZATIONS = {
    "en-US": AppStoreCopy(
        locale="en-US",
        subtitle="Tune every app on your Mac",
        description=(
            "Sonance EQ equalizes everything your Mac plays — Spotify, Safari and Chrome, Zoom, "
            "games, even system sounds — before it reaches your speakers or headphones. No audio "
            "driver, no kernel extension, no reboot.\n\n"
            "FEATURES\n"
            "• System-wide EQ via Core Audio process taps (macOS 14.4+)\n"
            "• Parametric editor with a live response curve — drag bands to shape frequency, gain, "
            "Q and type\n"
            "• Filter shapes: peaking, low/high shelf, variable-slope low/high cut (6–96 dB/oct), "
            "notch, band-pass and all-pass\n"
            "• 8,850 AutoEq headphone corrections — search your model and apply instantly\n"
            "• Linear-phase mode (zero phase distortion) and Mid-Side EQ\n"
            "• Per-app EQ, an app volume mixer with per-app output routing, and an audio recorder\n"
            "• Preset import/export, bypass A/B and master preamp\n\n"
            "Built for people who care how their Mac sounds. Audio is processed live on your device "
            "and is never sent anywhere."
        ),
        keywords=(
            "equalizer,audio,sound,parametric,headphones,AutoEq,bass,treble,music,mixer,volume,"
            "loudness,boost"
        ),
        promotional_text=(
            "Tune every app on your Mac with precise system-wide EQ, 8,850 AutoEq headphone "
            "corrections, per-app mixing, and no audio driver."
        ),
        whats_new=(
            "Adds a lightweight App Store update indicator, more complete French localization, "
            "and locale-aware purchase diagnostics."
        ),
    ),
    "fr-FR": AppStoreCopy(
        locale="fr-FR",
        subtitle="Égaliseur audio pour Mac",
        description=(
            "Sonance EQ égalise tout ce que votre Mac lit — Spotify, Safari et Chrome, Zoom, les jeux "
            "et même les sons du système — avant que le signal n’atteigne vos enceintes ou votre "
            "casque. Aucun pilote audio, aucune extension du noyau, aucun redémarrage.\n\n"
            "FONCTIONNALITÉS\n"
            "• Égalisation de tout le système grâce aux process taps de Core Audio (macOS 14.4+)\n"
            "• Éditeur paramétrique avec courbe de réponse en direct — réglez la fréquence, le gain, "
            "le facteur Q et le type de chaque bande\n"
            "• Filtres en cloche, plateaux grave/aigu, coupes grave/aigu à pente variable "
            "(6 à 96 dB/oct), coupe-bande, passe-bande et passe-tout\n"
            "• 8 850 corrections AutoEq pour casques — recherchez votre modèle et appliquez-les "
            "instantanément\n"
            "• Mode à phase linéaire (sans distorsion de phase) et égalisation Mid-Side\n"
            "• Égalisation par app, mixeur de volume avec sortie par app et enregistreur audio\n"
            "• Import/export de préréglages, comparaison avec contournement et préampli principal\n\n"
            "Conçu pour celles et ceux qui soignent le son de leur Mac. Le traitement audio reste en "
            "temps réel sur votre appareil et n’est jamais envoyé ailleurs."
        ),
        keywords=(
            "son,basses,aigus,casque,écouteurs,musique,paramétrique,volume,AutoEq,spatial,"
            "applications,enceinte"
        ),
        promotional_text=(
            "Réglez le son de chaque app avec un égaliseur système précis, 8 850 corrections AutoEq "
            "pour casques, un mixeur par app et aucun pilote audio."
        ),
        whats_new=(
            "Ajoute un indicateur discret de mise à jour, une localisation française plus complète "
            "et des diagnostics d’achat associés à la langue active."
        ),
    ),
}


def indexed_words(value: str) -> set[str]:
    return set(re.findall(r"[^\W_]+", value.casefold(), flags=re.UNICODE))


def validate_copy(copy: AppStoreCopy) -> None:
    errors: list[str] = []
    keyword_bytes = len(copy.keywords.encode("utf-8"))
    keyword_terms = copy.keywords.split(",")

    if len(copy.subtitle) > 30:
        errors.append(f"subtitle is {len(copy.subtitle)} characters (max 30)")
    if len(copy.description) > 4_000:
        errors.append(f"description is {len(copy.description)} characters (max 4000)")
    if keyword_bytes > 100:
        errors.append(f"keywords are {keyword_bytes} UTF-8 bytes (max 100)")
    if len(copy.promotional_text) > 170:
        errors.append(f"promotional text is {len(copy.promotional_text)} characters (max 170)")
    if len(copy.whats_new) > 4_000:
        errors.append(f"what's new is {len(copy.whats_new)} characters (max 4000)")
    if any(not term or term != term.strip() for term in keyword_terms):
        errors.append("keywords must be non-empty comma-separated terms with no spaces around commas")

    folded_terms = [term.casefold() for term in keyword_terms]
    duplicates = sorted({term for term in folded_terms if folded_terms.count(term) > 1})
    if duplicates:
        errors.append(f"duplicate keywords: {', '.join(duplicates)}")

    visible_words = indexed_words(APP_NAME) | indexed_words(copy.subtitle)
    repeated = sorted(visible_words & indexed_words(copy.keywords))
    if repeated:
        errors.append(f"keywords repeat indexed title/subtitle words: {', '.join(repeated)}")

    if errors:
        raise ValueError(f"{copy.locale}: " + "; ".join(errors))


def validate_all() -> None:
    if set(LOCALIZATIONS) != {"en-US", "fr-FR"}:
        raise ValueError("English and French metadata are both required")
    for copy in LOCALIZATIONS.values():
        validate_copy(copy)


def summarize() -> None:
    for copy in LOCALIZATIONS.values():
        print(
            f"  ✓ {copy.locale}: subtitle {len(copy.subtitle)}/30 chars · "
            f"keywords {len(copy.keywords.encode('utf-8'))}/100 bytes · "
            f"promo {len(copy.promotional_text)}/170 chars"
        )


def request(path: str, type_: str, resource_id: str, attrs: dict, *, apply: bool) -> None:
    if not apply:
        print(f"    · would PATCH {type_} {resource_id}: {', '.join(sorted(attrs))}")
        return
    api("PATCH", path, {"data": {"type": type_, "id": resource_id, "attributes": attrs}})


def upsert_app_info_localization(info_id: str, existing: list[dict], copy: AppStoreCopy, *, apply: bool) -> None:
    loc = next((item for item in existing if item["attributes"]["locale"] == copy.locale), None)
    attrs = {"subtitle": copy.subtitle, "privacyPolicyUrl": PRIVACY_URL}
    if loc:
        request(
            f"/v1/appInfoLocalizations/{loc['id']}",
            "appInfoLocalizations",
            loc["id"],
            attrs,
            apply=apply,
        )
    elif not apply:
        print(f"    · would CREATE app info localization {copy.locale}")
    else:
        api("POST", "/v1/appInfoLocalizations", {"data": {
            "type": "appInfoLocalizations",
            "attributes": {"locale": copy.locale, "name": APP_NAME, **attrs},
            "relationships": {"appInfo": {"data": {"type": "appInfos", "id": info_id}}},
        }})


def fill_app_info(app_id: str, version_state: str, *, apply: bool) -> None:
    infos = api("GET", f"/v1/apps/{app_id}/appInfos").get("data", [])
    matches = [
        info for info in infos
        if version_state in {
            info["attributes"].get("state"),
            info["attributes"].get("appStoreState"),
        }
    ]
    if len(matches) != 1:
        raise RuntimeError(
            f"expected one app info record in {version_state}, found {len(matches)}"
        )
    info = matches[0]
    existing = api("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations?limit=200").get("data", [])
    for copy in LOCALIZATIONS.values():
        upsert_app_info_localization(info["id"], existing, copy, apply=apply)


def find_version(app_id: str, version_string: str) -> dict:
    versions = api(
        "GET",
        f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=MAC_OS&limit=200",
    ).get("data", [])
    version = next(
        (item for item in versions if item["attributes"].get("versionString") == version_string),
        None,
    )
    if not version:
        raise RuntimeError(f"App Store version {version_string} does not exist yet")
    return version


def upsert_version_localization(version_id: str, existing: list[dict], copy: AppStoreCopy, *, apply: bool) -> None:
    loc = next((item for item in existing if item["attributes"]["locale"] == copy.locale), None)
    attrs = {
        "description": copy.description,
        "keywords": copy.keywords,
        "promotionalText": copy.promotional_text,
        "supportUrl": SUPPORT_URL,
        "marketingUrl": MARKETING_URL,
        "whatsNew": copy.whats_new,
    }
    if loc:
        request(
            f"/v1/appStoreVersionLocalizations/{loc['id']}",
            "appStoreVersionLocalizations",
            loc["id"],
            attrs,
            apply=apply,
        )
    elif not apply:
        print(f"    · would CREATE version localization {copy.locale}")
    else:
        api("POST", "/v1/appStoreVersionLocalizations", {"data": {
            "type": "appStoreVersionLocalizations",
            "attributes": {"locale": copy.locale, **attrs},
            "relationships": {
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}
            },
        }})


def fill_version(version: dict, *, apply: bool) -> None:
    version_string = version["attributes"].get("versionString")
    state = version["attributes"].get("appStoreState")
    print(f"  · version {version_string} [{state}]")
    if apply and state not in EDITABLE_VERSION_STATES:
        raise RuntimeError(
            f"refusing to edit version {version_string} in {state}; expected PREPARE_FOR_SUBMISSION"
        )
    existing = api(
        "GET",
        f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations?limit=200",
    ).get("data", [])
    for copy in LOCALIZATIONS.values():
        upsert_version_localization(version["id"], existing, copy, apply=apply)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", help="Exact macOS version to inspect or update, for example 1.0.6")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--validate-only", action="store_true", help="Validate local copy without Apple credentials")
    mode.add_argument("--dry-run", action="store_true", help="Read Apple state and print proposed writes")
    mode.add_argument("--apply", action="store_true", help="Publish metadata to an editable App Store version")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    validate_all()
    summarize()
    if args.validate_only:
        return 0
    if not args.version:
        raise SystemExit("--version is required unless --validate-only is used")
    if not args.dry_run and not args.apply:
        raise SystemExit("choose --dry-run or --apply")

    app = get_app()
    if not app:
        raise RuntimeError("App Store app record is missing")
    print(f"App {app['attributes']['name']} ({app['id']})")
    version = find_version(app["id"], args.version)
    version_state = version["attributes"].get("appStoreState")
    if args.apply and version_state not in EDITABLE_VERSION_STATES:
        raise RuntimeError(
            f"refusing to edit version {args.version} in {version_state}; "
            "expected PREPARE_FOR_SUBMISSION"
        )
    fill_app_info(app["id"], version_state, apply=args.apply)
    fill_version(version, apply=args.apply)
    print("✓ metadata applied" if args.apply else "✓ dry run complete — no App Store changes made")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, ValueError) as error:
        raise SystemExit(f"✗ {error}") from error
