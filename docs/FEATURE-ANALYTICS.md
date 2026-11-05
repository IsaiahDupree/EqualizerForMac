# Sonance feature analytics

The first-party `SonanceAnalytics` Swift package is shared by EQ, Mixer, Recorder,
Voice, Diagram Studio, Scribe, Align and Preflight. Other repositories pin its Git
revision; there is no external analytics SDK. The typed feature catalog is exported
by `swift run --jobs 1 analytics-contract` and is also enforced at the database.

Usage sharing is off until explicitly enabled in Feedback & Analytics. It records
named actions and their started/succeeded/failed/cancelled/blocked outcomes. Never
call `capture` on a render loop, audio callback, slider tick or search keystroke.
Capture completion only after the real operation returns successfully. An app
control being applied does not establish that the user heard the intended sound.

Feedback is a separate, explicit Submit action with fixed feature and experience
choices. It can be submitted with usage sharing off; each such item uses a new ID.
These responses explain the respondent's experience, not every customer's motives.
No raw text, audio, transcript, diagram, room geometry or measurement, filename,
search term, third-party app name or device identity is accepted by this package.

The anonymous ID is per app installation, never a person count or cross-app ID.
Events include version/build, platform, event/session IDs, timestamp, environment
and the allowed choices. Turning sharing off cancels this collector's requests and
removes unsent observations and the local identifier. Requests already received
cannot be recalled. Debug, development and test data must be excluded from usage
reports. Older released builds retain their previously declared collection until
customers install the update; do not claim a rollout from a source commit alone.

## Build configuration

Inject `SONANCE_ANALYTICS_PUBLISHABLE_KEY` as an Xcode build setting and expand it
into Info.plist as `SonanceAnalyticsPublishableKey`. A local environment override
is supported for development. The only production destination is the existing
shared Supabase project's insert-only `app_product_events` REST endpoint. The SDK
rejects foreign hosts and secret/service-role keys. Missing configuration disables
delivery and the feedback UI reports that state. Release preparation must check
the exact built app's Info.plist and privacy manifest before upload.

Do not put administrator or reader credentials into any app. Reports use owner
access; app clients can insert events but cannot read reports or other events.
Server views preserve the previous Mixer/Recorder/Voice/Diagram measurements and
normalize their existing event names; do not send a second event for those same
completed actions. New permission/attempt observations fill previously missing
steps. Keep the historical and consent-first measurement periods distinguishable
by app version/build and the `collection_basis` field.

## Validation

`swift test --jobs 1` exercises a real loopback HTTP intake backed by SQLite,
including retries with stable IDs, duplicate acknowledgement, redirect refusal,
default-off collection, explicit feedback and consent revocation. No URLProtocol
or provider mocks are used. Native apps must also build with the pinned package.
Live acceptance rows use `environment=test` and are excluded from owner reports.

Retention: raw product events are retained for at most 13 months by the shared
analytics retention job. Aggregates contain no source content. See the portfolio
privacy policy for customer contact and deletion options.
