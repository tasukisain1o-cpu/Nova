# NOVA

## NOVA Clips update

Vertical snap feed, For You / Following / Saved, likes, threaded replies, creator moderation, follows, bookmarks, sharing and reports. Creator studio supports upload, covers from file or frame, drafts, publishing, title/caption/topics, audience, framing and comment/share/save controls. Per-video creator statistics include unique viewers, completions, watch time and attributed follows.


Single-file web messenger: HTML, CSS and JavaScript in `index.html`. Hosted at https://tasukisain1o-cpu.github.io/Nova/ and connected to Supabase project `xpdqwkenfckaghszybfk`.

## Implemented

- Email registration, confirmation, login, password recovery, email/password changes and sign-out on all devices through Supabase Auth.
- Empty new accounts; no seeded demo conversations or local-only messages.
- Personal dialogs, groups, channels, username search, invitations, channel subscriptions, member roles and mute settings.
- Realtime text messages, replies, edits, deletion and paginated message history. Client IDs make text retries idempotent.
- Private uploads, images, files, voice messages and round videos via MediaRecorder where supported. Recordings stop after 60 seconds. Camera/microphone require the user's browser permission.
- Feed of subscribed channel posts and followed profiles, optional topic-based recommendations, comments and likes; stories expire after 24 hours; video Clips.
- Profile, avatar, four two-color themes without purple, synced privacy/notification/interests settings, follow requests and blocks.
- Responsive desktop layout and four-section mobile navigation.
- Owner dashboard: aggregate statistics, report queues and an immutable status-change audit. Profiles, messages, posts, stories and Clips have report actions. Closing a report does not remove content.

## Database

Applied upgrade order: `database/20261014_nova_v1.sql`, `database/20261014_nova_v1_1.sql`, `database/20261014_nova_v1_2.sql`. These upgrade the original project's eight draft tables. The first migration is not a blank-database bootstrap. Read `database/README.md` before restoring or modifying the schema.

All 26 public tables have RLS. Three media buckets are private. The browser contains only the public publishable key. Never add a secret/service-role key to frontend code or GitHub.

The v1.2 invoker RPCs provide an RLS-filtered chat list and atomic replacement of the current user's interests. Realtime is enabled on 12 tables. App admin membership is held in a protected private table and is assigned only to @saintoclub after owner confirmation; GitHub or Supabase ownership does not automatically create an app account.

## Running

Open through an HTTP server or GitHub Pages. No build step is needed. Supabase JS 2.117.3 is loaded from jsDelivr with a pinned version and integrity hash. A network connection is required. Local storage holds session information managed by Supabase and the theme; it is not the message database.

Supabase Auth Site URL and allowed redirect: `https://tasukisain1o-cpu.github.io/Nova/`.

## Verification and remaining setup

- JavaScript parsed successfully with Node's VM parser.
- Browser checks: real library loads, login/registration/recovery screens; mobile registration at 390×844; main navigation, profile/theme, chat text escaping and send behavior with a local-only fixture (never published).
- Actual database transaction tests: bootstrap, membership isolation, channel publication permissions, blocked dialogs, private follows/media, immutable message identity, anonymous denial; fixtures rolled back. Additional v1.2 tests cover chat list membership isolation and interest normalization/deduplication.
- Actual end-to-end login and two-user message/media delivery still need testing with user-created accounts. No real password was created by the agent.
- The owner configured Gmail SMTP and registered a confirmed app account. Provider quotas still apply. Keep confirmation enabled. Provider credentials stay outside repository code.
- No production push notifications, live broadcasts, audio/video calls or phone/SMS authentication yet. Broadcast metadata does not implement a streaming service. No end-to-end encryption is claimed.
- Apply `database/20261014_nova_v1_3.sql` after v1.2 for the owner dashboard. Access is checked inside protected database functions. No private conversation contents or Auth credentials are exposed. Role assignment is a separate owner operation, never a frontend bootstrap.
- `database/test_admin_v1_3.sql` passed actual database checks for admin/member isolation, self-promotion denial, report transitions, auditing and anonymous denial in a rolled-back transaction. Local UI fixtures are never published.
- Post feed currently loads the latest 50 posts; Clips load in pages of 10 videos. Channel publications are made through the feed composer by selecting the channel. Chat messages are a separate data model.
- Media links are short-lived signed URLs; active pages refresh images and renew paused/failed audio/video URLs. Already-issued links remain usable until expiry.
- Add server-side rate limits/moderation, storage cleanup for abandoned uploads, backup/restore drills and observability before a broad production release.

This is a connected first version for functional testing, not a claim that every planned NOVA feature is complete.

## Clips limits and verification

Videos: up to 180 seconds and 50 MB. Files retain original encoding; MP4 H.264 is recommended for compatibility. No paid transcoding, HLS, music catalogue, effects or timeline editing is included. Recommendations use interests, followed authors and liked topics; this is a basic ranking system, not a TikTok-scale model. Watch timing includes server elapsed-time checks but is not a fraud-proof analytics service. Feed uses offset pagination with client deduplication; rankings can move between requests. Replacement covers may leave old files requiring later cleanup.

Database tests passed for visibility, drafts, Storage covers, owner edits, disabled comments, replies/moderation, likes/saves, subscription attribution/deduplication, watch timing and anonymous denial. Local browser tests used synthetic video and an isolated client fixture for playback, cover capture and draft saving. Actual mobile viewport emulation could not be verified in this browser session.

