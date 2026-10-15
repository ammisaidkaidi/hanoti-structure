"""Offline syntax/ACL checks only. Requires pglast==8.6; NEVER connects or executes SQL."""
from pathlib import Path
import json
import re
from pglast import parse_sql, parse_plpgsql

root = Path(__file__).resolve().parents[3] / 'hanoti' / 'data'
tests = Path(__file__).resolve().parents[1]
manifest = json.loads((tests / 'fixtures/routines-manifest.json').read_text())
for path in sorted((root / 'migrations/hanouti').glob('*.sql')):
    parse_sql(path.read_text())
for filename in sorted({entry['file'] for entry in manifest}):
    text = (root / 'migrations/hanouti' / filename).read_text()
    parse_sql(text)
    # libpg_query's standalone PL parser cannot resolve user-defined composite argument types.
    # A record stand-in checks BODY GRAMMAR only; PostgreSQL must later validate real types/tables.
    grammar_text = text.replace('p_definition settings.setting_definitions,', 'p_definition record,')
    bodies = parse_plpgsql(grammar_text)
    expected = [entry for entry in manifest if entry['file'] == filename]
    assert len(bodies) == len(expected), (filename, 'body count')
    assert len(re.findall(r'^LANGUAGE plpgsql VOLATILE SECURITY DEFINER$', text, re.M)) == len(expected), filename
    assert text.count('SET search_path = pg_catalog, pg_temp') == len(expected), filename
    for entry in expected:
        assert f"REVOKE ALL ON FUNCTION {entry['signature']} FROM PUBLIC;" in text
    assert not re.search(r'\bEXECUTE\s+(?:format|\$|\w+\s*;)', text, re.I), filename
    print(f'{filename}: {len(bodies)} routine bodies parsed (grammar only).')
for name in ('010_erp_routine_catalog.sql', '020_erp_routine_privileges.sql'):
    parse_sql((root / 'seeds' / name).read_text())
    print(f'{name}: parsed, NOT executed.')
for path in sorted((tests / 'sql').glob('erp_routines*.sql')):
    fixture='\n'.join(line for line in path.read_text().splitlines() if not line.startswith('\\'))
    parse_sql(fixture)
    parse_plpgsql(fixture)
    print(f'{path.name}: parsed, NOT run.')
print('No live schema, privilege, behavior or concurrency validation.')
