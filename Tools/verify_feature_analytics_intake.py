#!/usr/bin/env python3
"""Explicit real Supabase contract/RLS acceptance checks. Inserts only test rows."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import uuid
from urllib.error import HTTPError
from urllib.request import Request, urlopen

INTAKE = 'https://ivhfuhxorppptyuofbgq.supabase.co/rest/v1/'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--key-file', type=Path, default=Path.home()/'.appfleet/sonance-analytics.json')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    key = json.loads(args.key_file.read_text())['publishable_key']
    if not key.startswith('sb_publishable_'):
        raise SystemExit('An insert-only publishable key is required, never an administrator credential.')

    def request(path, body=None):
        headers = {'apikey': key, 'Content-Type': 'application/json', 'Prefer': 'return=minimal'}
        data = json.dumps(body).encode() if body is not None else None
        try:
            with urlopen(Request(INTAKE+path, data=data, headers=headers), timeout=15) as response:
                return response.status, response.read()
        except HTTPError as error:
            return error.code, error.read()

    run = 'contract-'+uuid.uuid4().hex[:24]
    def row():
        return {'event_id': str(uuid.uuid4()), 'event_name': 'product_feature_used',
                'occurred_at': datetime.now(timezone.utc).isoformat(), 'app_id': 'sonance_eq',
                'platform': 'macos', 'app_version': 'contract-acceptance', 'build_number': run,
                'session_id': str(uuid.uuid4()), 'anonymous_id': str(uuid.uuid4()),
                'environment': 'test', 'source': 'client', 'schema_version': 2,
                'properties': {'feature_id': 'equalizer', 'outcome': 'succeeded',
                               'reason_code': 'none', 'collection_basis': 'explicit_opt_in'}}

    evidence = {'run': run, 'checked_at': datetime.now(timezone.utc).isoformat(), 'checks': []}
    valid = row()
    status, _ = request('app_product_events', valid)
    assert status == 201, f'Required real valid insert failed: HTTP {status}'
    evidence['checks'].append({'name': 'valid_test_insert', 'status': status, 'event_id': valid['event_id']})
    status, body = request('app_product_events', valid)
    assert status == 409 and json.loads(body).get('code') == '23505', 'Duplicate event ID was not rejected'
    evidence['checks'].append({'name': 'duplicate_id', 'status': status})

    invalid = []
    def rejection(name, mutate):
        item = row(); mutate(item); invalid.append((name, item))
    rejection('unknown_feature', lambda x: x['properties'].update(feature_id='unregistered_feature'))
    rejection('other_app_feature', lambda x: x['properties'].update(feature_id='transcription'))
    rejection('unbounded_extra_property', lambda x: x['properties'].update(custom_text='acceptance-only'))
    rejection('forbidden_content', lambda x: x['properties'].update(content='acceptance-only'))
    rejection('invalid_reason_for_success', lambda x: x['properties'].update(reason_code='permission_denied'))
    rejection('invalid_reason_for_failure', lambda x: x['properties'].update(outcome='failed'))
    rejection('missing_explicit_consent', lambda x: x['properties'].update(collection_basis='implicit'))
    rejection('unknown_app', lambda x: x.update(app_id='unregistered_app'))
    rejection('foreign_app_cannot_use_new_contract', lambda x: x.update(app_id='devforge'))
    rejection('wrong_platform', lambda x: x.update(platform='ios'))
    rejection('identified_user', lambda x: x.update(user_id=str(uuid.uuid4())))
    rejection('server_source', lambda x: x.update(source='server'))
    rejection('null_feature', lambda x: x['properties'].update(feature_id=None))
    rejection('array_properties', lambda x: x.update(properties=[]))
    rejection('free_text_feedback', lambda x: x.update(event_name='product_feedback_submitted', properties={
        'feature_id':'equalizer','feedback_reason':'arbitrary free text','collection_basis':'explicit_feedback'}))
    for name, item in invalid:
        status, body = request('app_product_events', item)
        code = json.loads(body).get('code')
        assert status in (400, 401, 403) and code in ('23514', '42501'), f'{name} failed closed incorrectly: HTTP {status}, code {code}'
        evidence['checks'].append({'name': name, 'status': status, 'database_code': code})

    for table in ['app_product_events','sonance_feature_usage_30d','sonance_feature_feedback_30d','sonance_analytics_health']:
        status, body = request(table+'?select=*&limit=1')
        assert status in (401, 403) and json.loads(body).get('code') == '42501', f'Anonymous reader access is not denied for {table}'
        evidence['checks'].append({'name': 'anonymous_read_denied:'+table, 'status': status})
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, indent=2)+'\n')
    args.output.chmod(0o600)
    print(f'{len(evidence["checks"])} real intake/security checks passed. Evidence: {args.output}')


if __name__ == '__main__':
    main()
