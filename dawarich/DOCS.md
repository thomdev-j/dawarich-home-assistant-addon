# Dawarich Home Assistant App

**This app runs a full [Dawarich](https://github.com/Freika/dawarich) instance directly on your Home Assistant OS device** — a self-hosted alternative to Google Timeline. No separate server or Docker Compose setup needed. Just install, and you have location tracking with full control of your data.

## Overview

Everything is bundled into a single app container:

- **PostgreSQL 17 + PostGIS** — spatial database
- **Redis 7.4** — cache and job queue
- **Dawarich** — Rails web application
- **Sidekiq** — background job processor
- **Nginx** — ingress reverse proxy

## Installation

1. Add this repository to your Home Assistant app store
2. Install the Dawarich app (the image is roughly 1.1 GB — initial download may take a while)
3. Adjust configuration options (see below)
4. Start the app — first boot initializes the database and compiles assets, subsequent starts are fast (under 15 seconds)
5. Open the web UI via the sidebar panel or at `http://<your-ha-ip>:3000`
6. Log in with the admin credentials from your app config

## Configuration

### General

| Option | Default | Description |
|---|---|---|
| `admin_email` | `admin@dawarich.local` | Email address used to log into Dawarich as admin. |
| `admin_password` | `changemeplease` | Password for the admin account. **Change this!** Only used on first creation — change password through the Dawarich UI after that. |
| `time_zone` | `Etc/UTC` | Timezone for the application (e.g., `America/New_York`, `Europe/Berlin`). |
| `database_password` | `dawarich` | Internal PostgreSQL password. Not exposed externally. |
| `application_hosts` | `homeassistant.local,localhost` | Comma-separated hostnames/IPs Rails accepts. Only needed for direct port 3000 access — ingress works without it. Add your HA IP if you get "blocked host" errors. |
| `background_processing_concurrency` | `5` | Sidekiq worker threads (1-20). Lower on constrained devices like Raspberry Pi 3. |

### Device Tracking

The app subscribes to Home Assistant's real-time event stream and pushes location updates to Dawarich the instant your device reports a new position. No polling, no delays — just set `ha_tracked_entities` and it works.

| Option | Default | Description |
|---|---|---|
| `ha_tracked_entities` | _(empty)_ | Comma-separated list of `device_tracker.*` entity IDs to track. Leave empty to disable. |
| `ha_min_distance` | `10` | Minimum distance in meters before a new position is recorded (0-1000). Filters GPS drift when stationary. Set to `0` to disable. |
| `ingress_auto_login` | `auto` | Sign users in from their Home Assistant account when opening the app from the sidebar. `auto` is on for new installs and off for existing ones, `on`/`off` decide it yourself. Users are matched through `ha_tracked_entities`, then by the account named after them, and anyone still unmatched gets their own new account. Passwords and the admin account keep working. |

**Basic usage** — track a single device under the admin user:
```
ha_tracked_entities: "device_tracker.my_phone"
```

**Multi-user** — create separate Dawarich users per person by adding a `:Name` suffix:
```
ha_tracked_entities: "device_tracker.my_phone:Alice, device_tracker.partner_phone:Bob"
```

This creates `alice@dawarich.local` and `bob@dawarich.local` with default password `changemeplease`. Each device's location data is sent to its own user. Users can change their password after first login via the Dawarich settings page — but **not their email** (see [Important Notes](#important-notes)). Once multiple users exist, you can use Dawarich's built-in **Family** feature to see everyone on a shared map with different colors.

Entities without a `:Name` suffix use the admin user. You can mix both styles:
```
ha_tracked_entities: "device_tracker.my_phone:Alice, device_tracker.tablet"
```

#### How It Works

The tracker subscribes to Home Assistant's Server-Sent Events stream for real-time `state_changed` events. Location updates are pushed to Dawarich the moment your phone reports a new position to HA — no polling delay. Check the app logs for `connected — receiving real-time state changes` to confirm it's active.

Duplicate locations (same lat/lon) are always skipped. Positions closer than `ha_min_distance` meters (default: 10m) to the last recorded point are also filtered to prevent GPS drift noise.

### Reverse Geocoding

Reverse geocoding converts GPS coordinates into place names. Disabled by default — just enable `reverse_geocoding` to use the public [Photon](https://github.com/komoot/photon) instance (no key needed). Alternatively, use a self-hosted Photon, Dawarich Patreon (`photon.dawarich.app`), or [Geoapify](https://www.geoapify.com/). The app tests the API on startup and logs whether it's reachable.

| Option | Default | Description |
|---|---|---|
| `reverse_geocoding` | `false` | Enable reverse geocoding. Requires a working provider. |
| `photon_api_host` | `https://photon.komoot.io` | Photon instance URL. Public instance, self-hosted, or Dawarich Patreon (`photon.dawarich.app`). |
| `photon_api_key` | _(empty)_ | API key for Photon. Required for Dawarich Patreon supporters using `photon.dawarich.app`. |
| `geoapify_api_key` | _(empty)_ | If set, uses Geoapify instead of Photon. |

### Important Notes

- **`application_hosts`** must include the hostname/IP you use to access the UI, or Rails will reject requests (not needed for ingress)
- **`secret_key_base`** is auto-generated on first start and stored in `/data/dawarich/secret_key_base` — sessions are invalidated if this file is deleted
- **Admin user** is created on first start with the configured email/password. The password is only set on creation — changing it in the app config won't update an existing user. Use the Dawarich UI to change passwords.
- **Distance units (km/mi)** are a per-user setting inside Dawarich, not an app option. Open the map → **Settings** button (left edge, shortcut `S`) → **Appearance → Distance Unit**. The `DISTANCE_UNIT` environment variable from older Docker Compose setups no longer exists upstream. It can also be set through the API: `curl -X PATCH "http://<ha-ip>:3000/api/v1/settings?api_key=YOUR_KEY" -H "Content-Type: application/json" -d '{"settings":{"maps":{"distance_unit":"mi"}}}'`
- **Do not change the auto-generated email addresses** (`admin@dawarich.local`, `alice@dawarich.local`, …) in the Dawarich UI under _Account settings_. The addon matches users by email on every start, so if you rename one, the next restart no longer recognizes it and creates a fresh duplicate account under the original email. Location tracking then silently flows to the new (empty) account while your renamed one stops receiving points. Change the **password** in the UI if you like, but leave the email as-is. (To use a real email, set `admin_email` in the app config *before first start*.)

## Running Rails Commands

Maintenance commands from the Dawarich documentation (`rails runner`, `rails console`, rake tasks) need the app's runtime environment. App options are only known at startup, so they are handed to the services by s6 rather than baked into the image — a plain shell does not have them, and Rails stops with `OTP_ENCRYPTION_PRIMARY_KEY required in production`. Use the bundled wrapper, which loads the environment first:

```bash
# Look up the container name first — it is app_… on current Home Assistant
# versions and addon_… on older ones:
docker ps --format '{{.Names}}' | grep dawarich

docker exec -it app_5ba57643_dawarich dawarich-rails runner "Visit.suggested.destroy_all"
docker exec -it app_5ba57643_dawarich dawarich-rails console
```

An interactive shell works too — `docker exec -it app_5ba57643_dawarich bash` loads the same environment, so `cd /var/app && bundle exec rails ...` behaves the way the upstream docs describe. It has to be an *interactive* shell: `bash -c '…'` deliberately does not load it, so the add-on's own service scripts are unaffected.

This needs Docker access, which the _Terminal & SSH_ app only has with protection mode turned off.

> **Do not** set `OTP_ENCRYPTION_PRIMARY_KEY` by hand or regenerate `SECRET_KEY_BASE` to get past that error. The OTP encryption keys are derived from that secret, so changing it makes any existing two-factor data impossible to decrypt.

## Data Persistence

All data is stored under `/data/` and survives app restarts and updates:

- `/data/postgres/` — PostgreSQL data directory
- `/data/redis/` — Redis persistence files
- `/data/dawarich/storage/` — User uploads and exports
- `/data/dawarich/secret_key_base` — Auto-generated secret key
- `/data/dawarich/api_keys/` — Per-entity API keys for HA tracking

## Backups

Home Assistant backups are supported:

- **Pre-backup:** PostgreSQL is dumped to `/data/dawarich/backup.sql` via `pg_dumpall`
- **Post-backup:** The SQL dump is cleaned up to save disk space
- Raw PostgreSQL files (`postgres/**`) are excluded from the backup — only the SQL dump is included

To restore from backup, the app detects the SQL dump on startup and imports it. Because the raw PostgreSQL files are not part of the backup, a restore hands the app an empty data directory plus that dump, and the import is what brings your history back — watch the app log for `Database restored: … user(s), … point(s)` on the first start after a restore.

To protect data you have not backed up, the import only runs into a database nobody has used yet (a fresh cluster, or one where no user has ever signed in, nothing has been imported and fewer than 1000 points exist). If you restore a backup onto an app that already holds data, the log says so and your existing data is left alone — restore into a fresh install instead.

## Network Security

- PostgreSQL binds to `localhost` only — port 5432 is **not** exposed outside the container
- Redis binds to `localhost` only — port 6379 is **not** exposed outside the container
- Only port 3000 (web UI) is exposed
- The app supports Home Assistant ingress for secure access without exposing port 3000

## Troubleshooting

### App won't start
- Check the app logs in Home Assistant for error messages
- Ensure you have enough disk space (PostgreSQL needs at least 100MB)

### Can't access web UI
- Verify your hostname/IP is in `application_hosts`
- Check that port 3000 is not blocked by your network
- Try using the ingress panel in the HA sidebar instead

### HA Tracker not sending data
- Check app logs for "HA Tracker:" messages
- Verify entity IDs exist in Home Assistant (Developer Tools → States)
- Ensure the entities have GPS attributes (latitude/longitude)

### Data import fails
- Check Sidekiq is running in the app logs
- Large imports may take significant time — check background job status in the Dawarich UI
