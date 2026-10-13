#!/usr/bin/env python3
"""Apply the reviewed Spanish copy and singular/plural forms to native catalogs."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COPY = json.loads((ROOT / 'ReferenceData/Localization/es-reviewed.json').read_text())
IDENTITIES = {'', '%@', '%@ · %@', '%@ %@', '°F', '°C', 'kg', 'cm', 'in', 'mL', 'oz', 'Siri', 'Swaddle', 'SWADDLE'}
PLURALS = {
    '%lld bottles': ('%lld bottle', '%lld biberón'),
    '%lld diapers': ('%lld diaper', '%lld pañal'),
    '%lld notes': ('%lld note', '%lld nota'),
    '%lld changes': ('%lld change', '%lld cambio'),
    '%lld feeds': ('%lld feed', '%lld toma'),
    '%lld diaper changes': ('%lld diaper change', '%lld cambio de pañal'),
    '%lld days': ('%lld day', '%lld día'),
    '%lld months': ('%lld month', '%lld mes'),
    '%lld sessions': ('%lld session', '%lld sesión'),
    '%lld pumping sessions': ('%lld pumping session', '%lld sesión de extracción'),
    '%@ · %lld sessions': ('%@ · %lld session', '%1$@ · %2$lld sesión'),
    '%lld entries imported for %@': ('%lld entry imported for %@', '%1$lld registro importado para %2$@'),
    '%lld pumping sessions imported for %@': ('%lld pumping session imported for %@', '%1$lld sesión de extracción importada para %2$@'),
    '%lld entries need details before saving.': ('%lld entry needs details before saving.', 'Faltan detalles en %lld registro antes de guardar.'),
    'Review %lld entries': ('Review %lld entry', 'Revisar %lld registro'),
    'Save %lld entries': ('Save %lld entry', 'Guardar %lld registro'),
    'Save %lld entries for %@': ('Save %lld entry for %@', 'Guardar %1$lld registro para %2$@'),
    'Save %lld pumping sessions for %@': ('Save %lld pumping session for %@', 'Guardar %1$lld sesión de extracción para %2$@'),
    'Save %lld sessions': ('Save %lld session', 'Guardar %lld sesión'),
    'Mixed · %lld selected': ('Mixed · %lld selected', 'Mixto · %lld seleccionado'),
    'Preserving %lld pending uploads': ('Preserving %lld pending upload', 'Conservando %lld envío pendiente'),
    'Verified %lld iCloud records': ('Verified %lld iCloud record', '%lld registro de iCloud verificado'),
}

def unit(value):
    return {'stringUnit': {'state': 'translated', 'value': value}}

for filename in ['Localizable.xcstrings', 'LittleLogWidgets/Localizable.xcstrings']:
    path = ROOT / filename
    catalog = json.loads(path.read_text())
    missing = []
    for key, entry in catalog['strings'].items():
        if entry.get('extractionState') == 'stale':
            continue
        if key in IDENTITIES:
            entry['shouldTranslate'] = False
            entry.setdefault('localizations', {})['es'] = unit(key)
            continue
        if key not in COPY:
            missing.append(key)
            continue
        entry.setdefault('localizations', {})['es'] = unit(COPY[key])
        if key in PLURALS:
            en_one, es_one = PLURALS[key]
            en_other = entry.get('localizations', {}).get('en', {}).get('stringUnit', {}).get('value', key)
            for language, one, other in [('en', en_one, en_other), ('es', es_one, COPY[key])]:
                entry['localizations'][language] = {'variations': {'plural': {'one': unit(one), 'other': unit(other)}}}
    path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + '\n')
    print(filename, 'missing:', missing)
    if missing:
        raise SystemExit(1)

shortcuts = {
    'Get recent activity in ${applicationName}': ['Consultar actividad reciente en ${applicationName}'],
    'How much did my baby eat in ${applicationName}': ['Cuánto comió mi bebé en ${applicationName}', 'Cuánto comió ${child} en ${applicationName}', 'Consultar totales de alimentación en ${applicationName}'],
    'Record a bottle in ${applicationName}': ['Registrar un biberón en ${applicationName}', 'Registrar el biberón en ${applicationName}', 'Anotar un biberón en ${applicationName}', 'Anotar un biberón con ${applicationName}'],
    'Record a diaper in ${applicationName}': ['Registrar un pañal en ${applicationName}', 'Anotar un pañal con ${applicationName}', 'Registrar ${contents} en ${applicationName}'],
    'Record pumping in ${applicationName}': ['Registrar extracción en ${applicationName}'],
    'Record the usual bottle in ${applicationName}': ['Registrar el biberón habitual en ${applicationName}'],
    'Start breastfeeding in ${applicationName}': ['Iniciar lactancia en ${applicationName}'],
    'When was the last feed in ${applicationName}': ['Cuándo fue la última toma en ${applicationName}', 'Cuándo comió ${child} por última vez en ${applicationName}'],
}
path = ROOT / 'AppShortcuts.xcstrings'
catalog = json.loads(path.read_text())
assert set(shortcuts) == set(catalog['strings'])
for key, values in shortcuts.items():
    catalog['strings'][key]['localizations']['es'] = {'stringSet': {'state': 'translated', 'values': values}}
path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + '\n')
