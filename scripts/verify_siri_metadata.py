#!/usr/bin/env python3
"""Check extracted App Intents metadata in an Xcode-built Swaddle .app."""
import argparse
import json
import plistlib
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("app", type=Path)
args = parser.parse_args()
data = json.loads((args.app / "Metadata.appintents/extract.actionsdata").read_text())
actions, entities = data["actions"], data["entities"]
expected_actions = {
    "SearchCareHistoryIntent": "system.searchInApp",
    "OpenCareRecordIntent": "system.open",
    "OpenCareNoteIntent": "system.open",
    "OpenFeedingReportIntent": "system.open",
    "CreateCareNoteIntent": "notes.createNote",
}
expected_entities = {
    "CareNoteEntity": "notes.note",
    "CareNotesFolder": "notes.folder",
    "CareNotesAccount": "notes.account",
}

# Xcode 27.1 emits domain/name pairs; 27.2 also emits publicIdentifier.
schema_components = {
    "system.searchInApp": ("system", "SystemSearchInAppIntent"),
    "system.open": ("system", "OpenIntent"),
    "notes.createNote": ("notes", "CreateNoteIntent"),
    "notes.note": ("notes", "NoteEntity"),
    "notes.folder": ("notes", "FolderEntity"),
    "notes.account": ("notes", "AccountEntity"),
}

def has_schema(metadata, expected):
    return any(
        schema.get("publicIdentifier") == expected
        or (schema.get("domain"), schema.get("name")) == schema_components[expected]
        for schema in metadata.get("assistantDefinedSchemas", [])
    )

def require(condition, message):
    if not condition:
        raise SystemExit(message)

for name, schema in expected_actions.items():
    action = actions[name]
    require(has_schema(action, schema), f"Missing schema: {name}")
    require(action["visibilityMetadata"]["assistantOnly"], f"Action is not assistant-only: {name}")
    require(action["authenticationPolicy"] > 0, f"Action needs authentication: {name}")
    require(action["availabilityAnnotations"]["LNPlatformNameIOS"]["introducedVersion"] == "27.0", f"Missing iOS 27 gate: {name}")
for name, schema in expected_entities.items():
    require(has_schema(entities[name], schema), f"Missing schema: {name}")
for name in ("CareRecordEntity", "CareNoteEntity", "FeedingReportEntity"):
    entity = entities[name]
    require(not entity["transient"], f"Content must have a stable ID: {name}")
    require(entity["transferableContentTypes"]["exportableTypes"], f"Content export missing: {name}")
for name, action in actions.items():
    # ITMS-90626 rejects the word Siri in App Intent descriptions.
    description = {k: v for k, v in action.items() if "description" in k.lower()}
    require("siri" not in json.dumps(description).lower(), f"Invalid description: {name}")
require(len(data["autoShortcuts"]) == 8, "Existing voice phrase registrations changed")

# Check the compiler's actual intent bindings, including compatibility phrases.
expected_phrases = {
    "RecordDiaperIntent": {
        "Log a ${contents} diaper in ${applicationName}",
        "Record a ${contents} diaper in ${applicationName}",
        "Record a diaper in ${applicationName}",
        "Log a diaper with ${applicationName}",
        "Record ${contents} in ${applicationName}",
    },
    "RecordPumpingIntent": {
        "Log expressed milk in ${applicationName}",
        "Log a pumping session in ${applicationName}",
        "Record pumping in ${applicationName}",
    },
}
phrase_owners = {}
for shortcut in data["autoShortcuts"]:
    for phrase in shortcut["phraseTemplates"]:
        phrase_owners.setdefault(phrase["key"], set()).add(shortcut["actionIdentifier"])
for intent, phrases in expected_phrases.items():
    for phrase in phrases:
        require(phrase_owners.get(phrase) == {intent}, f"Missing or ambiguous phrase binding: {phrase}")

diaper = next(enum for enum in data["enums"] if enum["identifier"] == "DiaperKind")
synonym_owners = {
    case["identifier"] for case in diaper["cases"]
    if any(synonym["key"] == "Wet and dirty" for synonym in case["displayRepresentation"].get("synonyms", []))
}
require(synonym_owners == {"both"}, "Wet and dirty must resolve only to the combined diaper choice")

# Renaming a shortcut's first phrase also renames its localization lookup key.
# Check the built resources, so a stale catalog key cannot silently drop translations.
root = Path(__file__).resolve().parents[1]
shortcut_catalog = json.loads((root / "AppShortcuts.xcstrings").read_text())["strings"]
local_catalog = json.loads((root / "Localizable.xcstrings").read_text())["strings"]
localized_phrase_count = 0
for primary_phrase in ("Log a ${contents} diaper in ${applicationName}", "Log expressed milk in ${applicationName}"):
    for locale, translation in shortcut_catalog[primary_phrase]["localizations"].items():
        if locale == "en":
            continue  # The source language uses the extracted phrase templates.
        resources = plistlib.loads((args.app / f"{locale}.lproj/AppShortcuts.strings").read_bytes())
        for index, phrase in enumerate(translation["stringSet"]["values"]):
            key = f"#!SET#!_{primary_phrase}[{index}]"
            require(resources.get(key) == phrase, f"Missing compiled shortcut phrase: {locale}: {key}")
            localized_phrase_count += 1
for locale, translation in local_catalog["Wet and dirty"]["localizations"].items():
    resources = plistlib.loads((args.app / f"{locale}.lproj/Localizable.strings").read_bytes())
    require(resources.get("Wet and dirty") == translation["stringUnit"]["value"], f"Missing compiled diaper synonym: {locale}")

widget_data = json.loads((args.app / "PlugIns/LittleLogWidgetsExtension.appex/Metadata.appintents/extract.actionsdata").read_text())
for bundle, metadata in [("app", data), ("widget", widget_data)]:
    action = metadata["actions"]["WidgetDiaperIntent"]
    require(action["allowedTargets"] == [{"type": 1}], f"Widget writes must execute in the main app: {bundle}")
    require(action["authenticationPolicy"] == 1, f"Widget writes must require authentication: {bundle}")
    require(not action["openAppWhenRun"] and action["supportedModes"] == 9, f"Widget background/dynamic modes changed: {bundle}")
    require(not action["isDiscoverable"], f"Internal widget actions must not clutter voice discovery: {bundle}")
    require({p["name"] for p in action["parameters"]} == {"target", "action", "command", "undo"}, f"Widget command parameters changed: {bundle}")
print(json.dumps({"actions": len(actions), "schemaActions": expected_actions, "schemaEntities": expected_entities,
                  "appShortcuts": len(data["autoShortcuts"]), "descriptionCheck": "passed",
                  "diaperAndPumpingPhraseBindings": "passed", "combinedDiaperSynonym": "passed",
                  "compiledLocalizedDiaperAndPumpingPhrases": localized_phrase_count,
                  "widgetExecutionAndAuthentication": "passed"}, indent=2))
