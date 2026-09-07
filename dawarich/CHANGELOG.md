# Changelog

## 1.14.3-1

- Upgrade base image to Dawarich [1.14.0](https://github.com/Freika/dawarich/releases/tag/1.14.0), [1.14.1](https://github.com/Freika/dawarich/releases/tag/1.14.1), [1.14.2](https://github.com/Freika/dawarich/releases/tag/1.14.2) and [1.14.3](https://github.com/Freika/dawarich/releases/tag/1.14.3). The headline is a Video Studio that turns the route on your map, or a trip, into a short MP4, and Polish, Catalan and Simplified Chinese joined the languages under Settings → General
- **The Video Studio needs an https address to work.** It encodes the video in your browser, using an interface browsers only hand out on a secure page, so opening Home Assistant at `http://homeassistant.local:8123` gets you "unsupported browser" whichever browser you use. Through Nabu Casa, or your own https reverse proxy, it works. Nothing else in the app depends on it. Videos that you save are stored in `/data` next to your imports and exports, so they end up in Home Assistant backups as well: the 10 newest per account are kept and files older than 30 days are removed
- **Slow first boot again, and your monthly distances will change.** A phone that replays a stale position after landing could bill a trip as dozens of instant intercontinental flights, so bursts like that are now flagged and any leg faster than 1200 km/h stops counting towards distance. Every history is re-checked in the background after the upgrade and the affected tracks and stats are rebuilt, so expect high CPU for a while and past monthly totals to move. A new index over your points is built during the upgrade as well, so give the loading page time and please do not restart the add-on while it is up. The background worker now waits for all of that to finish before it starts, so a busy disk cannot make one of the database changes time out and leave the app restarting in a loop. Your points, trips and imports are untouched
- Cities where your phone reported infrequently are counted again, so a home that had dropped out of your statistics comes back and time spent will generally go up. **Your existing months now repair themselves**, a few at a time in the background, instead of waiting until you press "Update stats" on the Stats page. Points in the United States, and a handful of other countries whose name the geocoder spells differently, were quietly missing from the countries you have visited and are repaired the same way. The "Max Gap Between Points" map setting is retired, its job now runs the same way for everyone. No app config changes required

## 1.13.1-1

- Upgrade base image to Dawarich [1.13.1](https://github.com/Freika/dawarich/releases/tag/1.13.1). The Tiled rendering beta now draws Tracks, Routes and Fog of War as well, so only the Scratch map still falls back to loading everything up front. It stays off until you switch it on under Map v2 → Settings
- **Slow first boot, then a background job that can run for hours.** Device and importer details move out of the points table into a shared one, which makes a large history noticeably smaller on disk. Existing points are converted in the background after the upgrade: expect high CPU for a while, and the database to grow before it shrinks, so check the drive has room. Your points, tracks, visits and stats are untouched, nothing changes in the app while it runs, and the app boots normally whether or not it finishes
- Each account can now pick its own geocoding provider (Photon, Geoapify, Nominatim or LocationIQ) under Settings → Integrations. With `reverse_geocoding` enabled in the app configuration, those options still win and the picker only shows what is already in use. Reverse geocoding also now uses one background worker instead of up to five, which only slows anything down if you point the app at your own Photon server
- No app config changes required

## 1.13.0-3

- **Stop the background job worker logging hundreds of Redis timeouts a day.** Redis saves to disk once a second, and on the SD cards and USB drives Home Assistant hosts usually run on, that write can take several seconds whenever something else is busy on the same disk. Redis pauses while it happens, and Sidekiq gave up after 3 seconds and reconnected. It now waits 10
- No job was ever lost to this and nothing about your data or your config changes, the log just becomes readable again

## 1.13.0-2

- **Fix the new "Tiled rendering" beta not working in the Home Assistant sidebar.** The map builds its tile address from the browser address bar, which leaves out the ingress path, so every tile came back as a 404 from Home Assistant itself and the map said "Could not load map tiles". The built-in proxy now corrects that address, and the same correction keeps the API key attached to the request. Tiles were already fine on port 3000 and stay that way
- Nothing else changes: the beta is still off until you switch it on, and no app config changes are required. If you already tried it on 1.13.0-1, reload the map page once

## 1.13.0-1

- Upgrade base image to Dawarich [1.13.0](https://github.com/Freika/dawarich/releases/tag/1.13.0). Nothing changes unless you go looking for it, the one new feature is off until you switch it on
- **New "Tiled rendering" beta** under Map v2 → Settings. Points are drawn from vector tiles, so a wide date range only loads what is on screen. It does not work through the Home Assistant sidebar: the map asks for its tiles at the wrong address there and reports "Could not load map tiles". Open the app on port 3000 to try it, otherwise leave it off
- The upgrade drops three indexes on the points table that 1.12.2 made redundant, which frees disk space and makes storing every new point a little cheaper. Your points, tracks, visits and stats are untouched, and the migration verifies the replacement index is healthy before it removes anything
- No app config changes required

## 1.12.2-2

- **PostgreSQL now checkpoints every 30 minutes instead of every 5.** The upstream default flushed the dirty buffer cache twelve times an hour for the few hundred kB the app writes in between. On the SD cards and USB SSDs most Home Assistant hosts run on, that burst of fsyncs can stall the disk for seconds, and nothing else on the machine gets to write while it lasts. Your data is no less safe: a commit is made durable by the write-ahead log, and a checkpoint only decides how much of that log has to be replayed after an unclean shutdown
- **Redis no longer writes RDB snapshots.** It already appends to disk every second, so the default rule of snapshotting whenever 10000 keys change in a minute forked and rewrote the whole dataset every minute or two without making anything safer, and background job traffic alone kept it firing. Backups and restores are unaffected, they use the append-only file
- No app config changes required

## 1.12.2-1

- Upgrade base image to Dawarich [1.12.2](https://github.com/Freika/dawarich/releases/tag/1.12.2)
- **Slow first boot again:** two new anomaly rules (visit reports that arrive after you already left, and cold cell-tower fixes with no motion data) are applied to every existing history in the background, and the affected tracks and stats are rebuilt. Expect high CPU for a while, your points are not touched
- Before the app starts, the upgrade also rebuilds an index on the points table. On a large history that can take several minutes, during which you get the loading page. Let it finish, do not restart the app
- **Distance for past months stays as it is.** A jump across a tracking gap no longer counts towards daily and monthly distance, but only for new data. To apply it to what you already have, run Map v2 → Settings → Recalculate tracks & stats once
- Google Timeline phone exports keep altitude, accuracy and speed from `rawSignals` again. Points already imported keep their empty values, and importing the same file again skips them, so delete the old import first if you want those fields filled
- Fixes: the map no longer jumps to a place you just left, the Tracks layer toggle survives a page reload, the Family page no longer fails on old points without a timestamp, and exports no longer fail on legacy places without coordinates
- No app config changes required

## 1.12.1-1

- Upgrade base image to Dawarich [1.12.0](https://github.com/Freika/dawarich/releases/tag/1.12.0) and [1.12.1](https://github.com/Freika/dawarich/releases/tag/1.12.1). The old Leaflet map is gone, `/map` now always opens the MapLibre map, so a browser without WebGL can no longer show a map. German, Spanish and French were added, switchable under Settings → General
- **Slow first boot again:** visit and transportation detection were rewritten, and the upgrade re-detects every account in the background. Expect high CPU for a while, your points are not touched. Old visits and tracks keep their previous detection until that finishes
- No app config changes required

## 1.11.0-3

- **Fix export and import files being stored outside `/data`, where no backup saw them and every app update threw them away.** `ln -sf` puts the link inside an existing directory instead of replacing it, and the Dawarich image ships a `storage/.keep`, so the link landed at `/var/app/storage/storage`. Present since 1.3.3-1. **Your location history is not affected:** points, tracks, trips, visits, places and stats all live in PostgreSQL under `/data/postgres` and are backed up as usual. What was lost are export downloads and the archived original file of an import ([#17](https://github.com/thomdev-j/homeassistant-app-dawarich/issues/17))
- Already stranded files cannot be rescued by this update, which recreates the container first. To keep them, run this **before updating**: `docker exec $(docker ps --format '{{.Names}}' | grep dawarich) sh -c 'find /var/app/storage -mindepth 1 -maxdepth 1 ! -name .keep ! -name storage -exec mv -n {} /data/dawarich/storage/ \;'`

## 1.11.0-2

- **Rails commands now work from a shell in the app.** `rails runner`, `rails console` and rake tasks failed with `OTP_ENCRYPTION_PRIMARY_KEY required in production`, which looks like a broken install but is not: Dawarich derives its OTP encryption keys from `SECRET_KEY_BASE`, and app options are resolved at startup and passed to the services through s6 rather than baked into the image, so a `docker exec` shell never saw them. Interactive shells now load that environment, and a `dawarich-rails` wrapper is included — `docker exec -it app_5ba57643_dawarich dawarich-rails runner "…"`. See _Running Rails commands_ in the docs ([#16](https://github.com/thomdev-j/homeassistant-app-dawarich/issues/16))

## 1.11.0-1

- Upgrade base image to Dawarich 1.11.0 — see upstream release notes for [1.10.2](https://github.com/Freika/dawarich/releases/tag/1.10.2), [1.10.3](https://github.com/Freika/dawarich/releases/tag/1.10.3), and [1.11.0](https://github.com/Freika/dawarich/releases/tag/1.11.0)
- **Slow first boot:** 1.11.0 re-checks every point against new GPS noise rules and rebuilds tracks and stats. Expect high CPU and disk load for a while — let it finish
- **The Accuracy Threshold setting is gone.** Any saved value is ignored, and points it used to hide come back
- Fixes the crash loop some instances hit upgrading to 1.10.1 (dropping the legacy `points.latitude`/`longitude` columns could not get its lock)
- No addon config changes required

## 1.10.1-2

- **Fix data loss when restoring a Home Assistant backup.** Backups exclude the raw PostgreSQL files (`backup_exclude: postgres/**`) and ship a `pg_dumpall` dump instead, but nothing ever imported that dump again — a restored app came up with a freshly initialized, empty database and every recorded location was silently gone, even though the dump sat unused in `/data/dawarich/backup.sql`. The app now imports it on the first start after a restore and logs how many users and points came back. The import only runs into a database nobody has used yet (a freshly initialized cluster, or one where no user ever signed in, nothing was imported and fewer than 1000 points exist), so it can never overwrite data on an app that is already in use
- Fix a partial `pg_dumpall` being packed into a backup as if it were complete: the dump is written to a temporary file and only moved into place once it succeeds. A failed dump now fails the backup instead of quietly shipping an unusable one
- Report a failing admin-user creation instead of swallowing it. `admin_password` shorter than Dawarich's 12-character minimum made `User.create!` raise "Password is too short"; the error scrolled past in the log and the app started with **no account to log in with**, which looks exactly like a forgotten password. The password length is now checked at startup and a failure is reported explicitly
- Set `DOMAIN` (from the first entry of `application_hosts`) so Dawarich can build absolute URLs in Devise mails. Without it, an account that got locked after 10 failed logins hit `Missing host to link to!` while rendering the unlock mail and the login page returned HTTP 500

## 1.10.1-1

- Upgrade base image to Dawarich 1.10.1 — see upstream release notes for [1.8.0](https://github.com/Freika/dawarich/releases/tag/1.8.0), [1.8.1](https://github.com/Freika/dawarich/releases/tag/1.8.1), [1.9.0](https://github.com/Freika/dawarich/releases/tag/1.9.0), [1.9.1](https://github.com/Freika/dawarich/releases/tag/1.9.1), [1.9.2](https://github.com/Freika/dawarich/releases/tag/1.9.2), [1.10.0](https://github.com/Freika/dawarich/releases/tag/1.10.0), and [1.10.1](https://github.com/Freika/dawarich/releases/tag/1.10.1)
- **Breaking (1.10.1):** the legacy `latitude`/`longitude` columns on the `points` table are dropped. The automatic migration first copies any legacy-only coordinates into `lonlat`, so no data is lost. This runs on first boot via the addon's `db:migrate` step; existing installs already store geodata in `lonlat` (`STORE_GEODATA=true`)
- **Behavior change (1.8.0):** declining a visit now permanently deletes it (the underlying location points are kept). The "Declined" filter and Restore action were removed
- **Data no longer persisted (1.10.1):** raw import source data (`raw_data`), FIT/TCX health metrics (heart rate, cadence, power, temperature), and Google Takeout place labels are no longer stored
- New features across 1.8–1.10: stay-point visit detection (opt-in per user), Fog of War per-hexagon reveal, AirTrail flight history on Map v2, redesigned trip detail with replay scrubber and per-day notes, public track sharing and live-location sharing, **Poster Studio** (printable travel posters, PNG/PDF export), PWA install to home screen, custom Map v2 colors, mobile settings sync API, Google Photos sidecar geotagging, and transportation-mode detection for TCX and Google Takeout imports
- Poster Studio adds ~100 MB to the image and requires server-side rendering; it works on this addon's 64-bit builds (aarch64/amd64) and is unavailable only on 32-bit ARM
- Upstream lowered its default `WEB_CONCURRENCY` to 1 and `BACKGROUND_PROCESSING_CONCURRENCY` to 3 (1.10.0). The addon still sets `background_processing_concurrency` explicitly (default 5), so that is unchanged; `WEB_CONCURRENCY` is left at the new upstream default, which trims idle memory on the Raspberry Pi (upstream idle footprint dropped ~843 → ~690 MB)
- No addon config changes required. New optional upstream env vars are intentionally not exposed: `PLACE_VISITS_THROTTLE_SECONDS`, `SMTP_SSL`/`SMTP_AUTHENTICATION` (the addon sends no email), `PUID`/`PGID` (the addon runs Rails, Postgres, Redis and Sidekiq under its own s6-managed users, not the upstream container user), and `CHIBICHANGE_WIDGET_HOST`/`CHIBICHANGE_SLUG` (the "What's New" widget)

## 1.7.11-3

- Fix reverse geocoding failing with `Geocoder::NetworkError` on networks that advertise IPv6 but have no working IPv6 egress. `api.geoapify.com` is Cloudflare-fronted and publishes AAAA records; Ruby's geocoder connected to the dead IPv6 address first and failed every job, while `curl` (and the startup healthcheck) silently fell back to IPv4 via Happy Eyeballs. The container now prefers IPv4 (`/etc/gai.conf`), so the geocoder resolves IPv4 first; IPv6 is only reordered, not disabled. The startup Geoapify healthcheck now forces IPv4 so it reflects the path the geocoder actually takes ([#11](https://github.com/thomdev-j/homeassistant-app-dawarich/issues/11))

## 1.7.11-2

- Fix imports failing with "Unknown error" / "No files were successfully uploaded" on files larger than ~1 MB. The bundled nginx proxy had no `client_max_body_size` set, so it fell back to the 1 MB default and rejected the ActiveStorage upload with HTTP 413 (`client intended to send too large body`). The limit is now removed and large upload bodies stream straight to Rails instead of buffering into the RAM-backed tmpfs ([#10](https://github.com/thomdev-j/homeassistant-app-dawarich/issues/10))

## 1.7.11-1

- Upgrade base image to Dawarich 1.7.11 — see upstream [1.7.9](https://github.com/Freika/dawarich/releases/tag/1.7.9), [1.7.10](https://github.com/Freika/dawarich/releases/tag/1.7.10), and [1.7.11](https://github.com/Freika/dawarich/releases/tag/1.7.11) release notes
- New Map v2 features: H3 **Hexagons** heatmap layer, area-selection bulk delete (incl. anomalies), area Edit button, GPX/GeoJSON trip downloads, hover tooltips on family member markers (1.7.9–1.7.11)
- Real-time Photon place suggestions: one Place per visit (was up to 25 candidates); `POST /api/v1/visits/:id/select_place` to swap; `place_visits` table will be removed in a follow-up release (1.7.9)
- New **Minimum visit duration** setting (default 5 min, replaces hardcoded 3 min); visit detection now ignores drive-bys and respects your enabled transportation modes; smart density fill fixed (1.7.10)
- Many fixes: overlapping tracks reconciled, late-arriving points reabsorbed, real-time family location updates, duplicate-import skip surfaced, Stats/Insights no longer 500 without `JWT_SECRET_KEY`, area geometry validation, two unused `points` indexes dropped on upgrade (frees several GB on large installs), 9 CVE-fix gem bumps (1.7.9–1.7.11)
- Addon: on first boot after upgrade, runs the upstream-recommended `dawarich:backfill_place_names` and `dawarich:cleanup_suggested_places` rake tasks once (gated by a marker file in `/data`) so existing installs get the new Place data populated
- New optional upstream env `OIDC_PKCE_ENABLED` is not exposed in the addon (off by default); request it if you need PKCE for an OIDC provider

## 1.7.8-2

- Show the Dawarich sidebar panel for non-admin Home Assistant users (`panel_admin: false`). Dawarich's own login still applies, so non-admin HA users will need their own Dawarich credentials.

## 1.7.8-1

- Upgrade base image to Dawarich 1.7.8 — see upstream [1.7.8](https://github.com/Freika/dawarich/releases/tag/1.7.8) release notes
- Fix multi-user creation failing with "Password is too short" — default password for auto-created users (and the `admin_password` config default) is now `changemeplease` (14 chars), meeting Dawarich's 12-char minimum

## 1.7.7-1

- Upgrade base image to Dawarich 1.7.7 — see upstream [1.7.2](https://github.com/Freika/dawarich/releases/tag/1.7.2), [1.7.3](https://github.com/Freika/dawarich/releases/tag/1.7.3), [1.7.4](https://github.com/Freika/dawarich/releases/tag/1.7.4), [1.7.5](https://github.com/Freika/dawarich/releases/tag/1.7.5), [1.7.6](https://github.com/Freika/dawarich/releases/tag/1.7.6), and [1.7.7](https://github.com/Freika/dawarich/releases/tag/1.7.7) release notes
- Security audit fixes: path-traversal in archive import, OAuth account-link consent, SSRF blocklist for Immich/PhotoPrism URLs, 2FA brute-force rate limit, stored XSS sanitization, 12-char minimum password length, 256-bit API keys (1.7.3)
- Map v2: delete-from-card, manual transportation-mode correction, bulk visit confirm/decline, trip recalculate button, heatmap visible at city zoom, mobile safe-area fit (1.7.2, 1.7.5, 1.7.6)
- Polarsteps and Google "Timeline Edits.json" Takeout imports; clearer errors on unsupported uploads (1.7.3, 1.7.6)
- Visit suggestions now triggered by live tracking (Dawarich iOS app, OwnTracks, Overland, Traccar), not just imports (1.7.5)
- Many timezone, track-merge, stats, and reverse-geocoding fixes; duplicate-tracks prevention (1.7.5–1.7.7)
- No env-variable changes required for this addon — Prometheus migration to Yabeda (1.7.7) only affects setups with `PROMETHEUS_EXPORTER_ENABLED=true`; `JWT_SECRET_KEY` no longer required (1.7.4)

## 1.7.1-1

- Upgrade base image to Dawarich 1.7.1 — see upstream [1.7.0](https://github.com/Freika/dawarich/releases/tag/1.7.0) and [1.7.1](https://github.com/Freika/dawarich/releases/tag/1.7.1) release notes for user-facing changes

## 1.6.1-1

- Upgrade base image to Dawarich 1.6.1
- Immich photo enrichment with geodata (1.6.0)
- Two-factor authentication with TOTP and backup codes (1.6.0)
- GPS noise filtering, map layer management, "Day per Country" analytics (1.5.0)
- Family page map, visit confirmation buttons, visual redesign (1.4.0)
- 50+ bug fixes across 1.4.0–1.6.1 including deadlock fixes, memory crash on large imports, and compressed zip import failures

## 1.3.4-2

- Add `photon_api_key` config option for Dawarich Patreon supporters using `photon.dawarich.app`
- Fix startup crash (exit 22) when geocoding API test fails
- Public Photon instance (`photon.komoot.io`) now supports reverse geocoding

## 1.3.4-1

- Upgrade base image to Dawarich 1.3.4
- Family location sharing, redesigned onboarding, geocoding and UI fixes

## 1.3.3-70

- Fix Photon host format — strip protocol prefix, set `PHOTON_API_USE_HTTPS` separately per Dawarich docs

## 1.3.3-69

- Add Geoapify API startup test to verify API key works

## 1.3.3-68

- Fix Geoapify/Photon env vars being set simultaneously — now mutually exclusive

## 1.3.3-67

- Default `reverse_geocoding` to `false` — public Photon instance does not support reverse geocoding
- Document provider options: Geoapify (free API key), self-hosted Photon, Dawarich Patreon

## 1.3.3-66

- Add Photon API connectivity test on startup with debug logging

## 1.3.3-65

- Add reverse geocoding support with `reverse_geocoding` toggle, `photon_api_host`, and `geoapify_api_key` config options
- Test geocoding API on startup and log result
- Fix `FATAL: role "root" does not exist` log warnings during startup

## 1.3.3-62

- Remove polling fallback — tracker now uses real-time SSE exclusively
- Remove `ha_polling_interval` and `ha_polling_interval_stationary` config options
- Add configurable GPS drift filter (`ha_min_distance`, default 10m) — prevents stationary phones from generating spurious data points due to GPS signal fluctuation. Set to `0` to disable.

## 1.3.3-60

- Rewrite HA tracker to use real-time SSE event stream
- Persist session cookies for 1 year to prevent unexpected logouts
- Extend Devise remember-me token to 1 year with sliding expiry

## 1.3.3-56

- Show friendly loading page instead of raw 502 Bad Gateway while Dawarich starts up

## 1.3.3-55

- Rename "addon" to "app" throughout docs and metadata to match Home Assistant's updated terminology
- Fix logout not fully signing out: clear stale session cookies at root path and flush Turbo page cache on sign-out

## 1.3.3-53

- Add multi-user device tracking: use `:Name` suffix in `ha_tracked_entities` to create separate Dawarich users per household member
- Grant admin privileges to the configured admin user automatically
- Fix CSRF 422 errors on login/logout via ingress
- Fix ingress compatibility for forms, redirects, and WebSocket connections
- Fix navigation and login/logout via HTTPS reverse proxies (e.g. Cloudflare tunnel)
- Add graceful Sidekiq shutdown to avoid interrupted background jobs
- Bail out on database migration failure instead of starting with broken state
- Remove `secret_key_base`, `photon_api_host`, and `geoapify_api_key` from addon config (auto-generated or configurable in Dawarich UI)
- Suppress Redis memory overcommit warning in logs
- Clean up stale API key files when entity config changes
- Default timezone changed to `Etc/UTC`
- Comprehensive README with quickstart guide, configuration reference, hardware requirements, and FAQ

## 1.3.3-1

- Initial release
- Based on Dawarich v1.3.3
- Bundled PostgreSQL 17 + PostGIS, Redis 7.4
- s6-overlay process supervision
- Auto-generated SECRET_KEY_BASE persisted across restarts
- Home Assistant backup support with pg_dumpall
