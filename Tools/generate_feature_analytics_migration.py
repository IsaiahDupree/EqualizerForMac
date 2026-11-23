#!/usr/bin/env python3
"""Render the reviewed migration from the Swift catalog. Does not access a database."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--catalog', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
contract = json.loads(args.catalog.read_text())
catalog = json.dumps(contract, separators=(',', ':'), sort_keys=True)
assert '$catalog$' not in catalog
apps = ', '.join("'" + key + "'" for key in contract['apps'])

sql = f'''-- Sonance content-free feature usage and voluntary feedback.
-- Generated from the shared Swift catalog; reviewed before application.
-- Existing apps, event contracts, grants, RLS restrictions and rows are preserved.
BEGIN;

CREATE OR REPLACE FUNCTION public.sonance_feature_payload_valid(p_app text, p_event text, p_properties jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE PARALLEL SAFE SECURITY INVOKER
SET search_path = '' AS $function$
  SELECT CASE WHEN jsonb_typeof(p_properties) IS DISTINCT FROM 'object' THEN false ELSE COALESCE((
    ($catalog${catalog}$catalog$::jsonb -> 'apps' -> p_app -> 'features') ? (p_properties ->> 'feature_id')
    AND jsonb_typeof(p_properties -> 'feature_id') = 'string'
    AND CASE p_event
      WHEN 'product_feature_used' THEN
        p_properties ?& ARRAY['feature_id','outcome','reason_code','collection_basis']
        AND (p_properties - ARRAY['feature_id','outcome','reason_code','collection_basis']) = '{{}}'::jsonb
        AND p_properties ->> 'collection_basis' = 'explicit_opt_in'
        AND jsonb_typeof(p_properties -> 'outcome') = 'string'
        AND jsonb_typeof(p_properties -> 'reason_code') = 'string'
        AND ($catalog${catalog}$catalog$::jsonb -> 'outcome_reasons' -> (p_properties ->> 'outcome')) ? (p_properties ->> 'reason_code')
      WHEN 'product_feedback_submitted' THEN
        p_properties ?& ARRAY['feature_id','feedback_reason','collection_basis']
        AND (p_properties - ARRAY['feature_id','feedback_reason','collection_basis']) = '{{}}'::jsonb
        AND p_properties ->> 'collection_basis' = 'explicit_feedback'
        AND jsonb_typeof(p_properties -> 'feedback_reason') = 'string'
        AND ($catalog${catalog}$catalog$::jsonb -> 'feedback_reasons') ? (p_properties ->> 'feedback_reason')
      ELSE false END
  ), false) END
$function$;
REVOKE ALL ON FUNCTION public.sonance_feature_payload_valid(text,text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sonance_feature_payload_valid(text,text,jsonb) TO anon, authenticated, service_role;

-- Extend the three shared checks without reproducing or weakening other apps' contracts.
DO $extend$
DECLARE item record; previous text;
BEGIN
  FOR item IN SELECT * FROM (VALUES
    ('app_product_events_app_check', $$app_id IN ('sonance_eq','sonance_scribe','sonance_align','sonance_preflight')$$),
    ('app_product_events_name_check', $$app_id IN ({apps}) AND event_name IN ('product_feature_used','product_feedback_submitted')$$),
    ('app_product_events_required_properties_check', $$event_name IN ('product_feature_used','product_feedback_submitted') AND public.sonance_feature_payload_valid(app_id,event_name,properties)$$)
  ) AS additions(constraint_name, extension_expression)
  LOOP
    SELECT pg_get_constraintdef(oid) INTO STRICT previous FROM pg_constraint
      WHERE conrelid = 'public.app_product_events'::regclass AND conname = item.constraint_name;
    EXECUTE format('ALTER TABLE public.app_product_events DROP CONSTRAINT %I', item.constraint_name);
    EXECUTE format('ALTER TABLE public.app_product_events ADD CONSTRAINT %I CHECK ((%s) OR (%s)) NOT VALID',
      item.constraint_name, substring(previous FROM 7), item.extension_expression);
    EXECUTE format('ALTER TABLE public.app_product_events VALIDATE CONSTRAINT %I', item.constraint_name);
  END LOOP;
END $extend$;

ALTER TABLE public.app_product_events ADD CONSTRAINT app_product_events_sonance_feature_payload_check CHECK (
  event_name NOT IN ('product_feature_used','product_feedback_submitted') OR (
    app_id IN ({apps})
    AND public.sonance_feature_payload_valid(app_id,event_name,properties)
    AND user_id IS NULL AND source = 'client'
    AND workflow_id IS NULL AND workflow_name IS NULL AND workflow_version IS NULL
    AND ((app_id = 'sonance_align' AND platform = 'ios')
      OR (app_id = 'diagram_studio' AND platform IN ('macos','ios'))
      OR (app_id NOT IN ('sonance_align','diagram_studio') AND platform = 'macos'))
  )
) NOT VALID;
ALTER TABLE public.app_product_events VALIDATE CONSTRAINT app_product_events_sonance_feature_payload_check;
ALTER TABLE public.app_product_events ADD CONSTRAINT app_product_events_sonance_new_apps_check CHECK (
  app_id NOT IN ('sonance_eq','sonance_scribe','sonance_align','sonance_preflight')
  OR event_name IN ('product_feature_used','product_feedback_submitted')
) NOT VALID;
ALTER TABLE public.app_product_events VALIDATE CONSTRAINT app_product_events_sonance_new_apps_check;

-- Keep each original policy expression intact and append only the four new Sonance scopes.
DO $policies$
DECLARE item record; previous text;
BEGIN
  FOR item IN SELECT polname FROM pg_policy
    WHERE polrelid = 'public.app_product_events'::regclass
      AND polname IN ('app_product_events_anon_insert','app_product_events_authenticated_insert')
  LOOP
    SELECT pg_get_expr(polwithcheck,polrelid) INTO STRICT previous FROM pg_policy
      WHERE polrelid = 'public.app_product_events'::regclass AND polname = item.polname;
    EXECUTE format('ALTER POLICY %I ON public.app_product_events WITH CHECK ((%s) OR
      (user_id IS NULL AND event_name IN (''product_feature_used'',''product_feedback_submitted'') AND
       ((app_id IN (''sonance_eq'',''sonance_scribe'',''sonance_preflight'') AND platform = ''macos'')
        OR (app_id = ''sonance_align'' AND platform = ''ios''))))', item.polname, previous);
  END LOOP;
END $policies$;

CREATE VIEW public.sonance_feature_catalog WITH (security_invoker=true) AS
SELECT app.key AS app_id, app.value ->> 'title' AS app_name, feature.value AS feature_id
FROM jsonb_each($catalog${catalog}$catalog$::jsonb -> 'apps') AS app
CROSS JOIN LATERAL jsonb_array_elements_text(app.value -> 'features') AS feature;

CREATE VIEW public.sonance_feature_events WITH (security_invoker=true) AS
WITH classified AS (
 SELECT event_id, app_id, platform, app_version, build_number, anonymous_id, session_id,
        occurred_at, received_at, event_name,
  CASE
   WHEN event_name = 'product_feature_used' THEN properties ->> 'feature_id'
   WHEN event_name = 'app_opened' THEN 'app_open'
   WHEN app_id = 'sonance_mixer' AND event_name = 'audio_channel_adjusted' THEN
    CASE properties ->> 'adjustment_type' WHEN 'volume' THEN 'volume' WHEN 'mute' THEN 'mute' WHEN 'reset' THEN 'channel_reset' END
   WHEN app_id = 'sonance_mixer' AND event_name = 'output_route_changed' THEN 'output_routing'
   WHEN app_id IN ('sonance_recorder','sonance_voice') THEN
    CASE event_name WHEN 'recording_source_selected' THEN 'recording_source'
      WHEN 'recording_format_selected' THEN 'recording_format'
      WHEN 'recording_started' THEN 'recording' WHEN 'recording_saved' THEN 'recording'
      WHEN 'recording_failed' THEN 'recording' WHEN 'recording_revealed' THEN 'recording_reveal'
      WHEN 'voice_monitoring_started' THEN 'monitoring' WHEN 'voice_settings_applied' THEN 'voice_settings' END
   WHEN app_id = 'diagram_studio' THEN
    CASE event_name WHEN 'diagram_opened' THEN 'diagram_open' WHEN 'diagram_created' THEN 'diagram_create'
      WHEN 'diagram_import_completed' THEN 'diagram_import' WHEN 'diagram_remixed' THEN 'diagram_remix'
      WHEN 'diagram_version_restored' THEN 'diagram_restore'
      WHEN 'diagram_export_started' THEN 'diagram_export' WHEN 'diagram_export_completed' THEN 'diagram_export'
      WHEN 'diagram_export_cancelled' THEN 'diagram_export' WHEN 'diagram_export_failed' THEN 'diagram_export' END
  END AS feature_id,
  CASE WHEN event_name = 'product_feature_used' THEN properties ->> 'outcome'
       WHEN event_name IN ('recording_started','diagram_export_started') THEN 'started'
       WHEN event_name IN ('recording_failed','diagram_export_failed') THEN 'failed'
       WHEN event_name = 'diagram_export_cancelled' THEN 'cancelled' ELSE 'succeeded' END AS outcome,
  CASE WHEN event_name = 'product_feature_used' THEN properties ->> 'reason_code'
       WHEN event_name IN ('recording_failed','diagram_export_failed') THEN 'operation_failed'
       WHEN event_name = 'diagram_export_cancelled' THEN 'user_cancelled' ELSE 'none' END AS reason_code,
  CASE WHEN event_name = 'product_feature_used' THEN 'explicit_opt_in' ELSE 'legacy_version_dependent' END AS collection_basis
 FROM public.app_product_events
 WHERE environment = 'production' AND app_id IN ({apps})
   AND occurred_at <= now() + interval '5 minutes'
)
SELECT * FROM classified WHERE feature_id IS NOT NULL;

CREATE VIEW public.sonance_feature_usage_30d WITH (security_invoker=true) AS
SELECT app_id, feature_id,
 count(*) FILTER (WHERE outcome = 'started') AS started_actions,
 count(*) FILTER (WHERE outcome = 'succeeded') AS successful_actions,
 count(*) FILTER (WHERE outcome = 'failed') AS failed_actions,
 count(*) FILTER (WHERE outcome = 'blocked') AS blocked_actions,
 count(*) FILTER (WHERE outcome = 'cancelled') AS cancelled_actions,
 count(DISTINCT anonymous_id) AS observed_installations,
 max(occurred_at) AS last_observed_at
FROM public.sonance_feature_events
WHERE occurred_at >= now() - interval '30 days'
GROUP BY app_id, feature_id;

CREATE VIEW public.sonance_feature_feedback_30d WITH (security_invoker=true) AS
SELECT app_id, properties ->> 'feature_id' AS feature_id,
       properties ->> 'feedback_reason' AS feedback_reason, count(*) AS responses,
       max(occurred_at) AS last_response_at
FROM public.app_product_events
WHERE event_name = 'product_feedback_submitted' AND environment = 'production'
  AND app_id IN ({apps}) AND occurred_at >= now() - interval '30 days'
  AND occurred_at <= now() + interval '5 minutes'
GROUP BY app_id, properties ->> 'feature_id', properties ->> 'feedback_reason';

CREATE VIEW public.sonance_analytics_health WITH (security_invoker=true) AS
SELECT apps.app_id, apps.app_name, count(e.event_id) AS production_events_30d,
       count(DISTINCT e.anonymous_id) FILTER (WHERE e.event_name <> 'product_feedback_submitted') AS observed_installations_30d,
       count(e.event_id) FILTER (WHERE e.event_name = 'product_feature_used') AS new_feature_events_30d,
       count(e.event_id) FILTER (WHERE e.event_name = 'product_feedback_submitted') AS feedback_responses_30d,
       max(e.received_at) AS last_received_at,
       array_remove(array_agg(DISTINCT e.app_version || ' (' || e.build_number || ')'),NULL) AS observed_versions,
       CASE WHEN count(e.event_id) = 0 THEN 'no_production_observations_yet'
            WHEN count(e.event_id) FILTER (WHERE e.event_name = 'product_feature_used') = 0 THEN 'legacy_collection_only'
            ELSE 'new_feature_collection_observed' END AS collection_state
FROM (SELECT DISTINCT app_id, app_name FROM public.sonance_feature_catalog) apps
LEFT JOIN public.app_product_events e ON e.app_id = apps.app_id AND e.environment = 'production'
  AND e.occurred_at >= now() - interval '30 days' AND e.occurred_at <= now() + interval '5 minutes'
GROUP BY apps.app_id, apps.app_name;

REVOKE ALL ON public.sonance_feature_catalog, public.sonance_feature_events,
 public.sonance_feature_usage_30d, public.sonance_feature_feedback_30d, public.sonance_analytics_health
 FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.sonance_feature_catalog, public.sonance_feature_events,
 public.sonance_feature_usage_30d, public.sonance_feature_feedback_30d, public.sonance_analytics_health TO service_role;

COMMENT ON VIEW public.sonance_feature_usage_30d IS 'Observed actions and app installations, not people or proof of audible success. Missing rows are unknown, not zero use. Production only.';
COMMENT ON VIEW public.sonance_feature_feedback_30d IS 'Voluntary fixed-choice responses. Feedback with usage sharing off has a fresh ID per response; never interpret as distinct people or all-user motives.';
COMMENT ON VIEW public.sonance_analytics_health IS 'Observations do not prove release status or complete instrumentation. Compare exact app/build with the release ledger.';

-- Scope retention to these eight apps; leave every other product's retention untouched.
SELECT cron.schedule('sonance-product-events-retention-13mo', '23 4 * * *',
  $retention$DELETE FROM public.app_product_events WHERE app_id IN ({apps})
    AND received_at < now() - interval '13 months';$retention$);
COMMIT;
'''
args.output.write_text(sql)
print(f'Generated {args.output.name}: {len(contract["apps"])} app scopes; existing constraints preserved.')
