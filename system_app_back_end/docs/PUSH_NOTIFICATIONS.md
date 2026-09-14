# iPhone notifications and foreground refresh

The app paints its cached topic first, refreshes navigation and current content, and reconciles section attention. While foreground, the existing five-second file/task poll also refreshes topics, types, tags, views and AI actions once a minute. Resume requests a full refresh; concurrent requests are coalesced. Background polling stops. A phone sidebar overlay covers stale navigation during full refresh; an editor overlay appears only while replacing changed content. DocumentSync retains dirty edits and conflict handling. Entry focus is explicit; remote replacements restore the previous paragraph position without requesting focus or reopening a dismissed keyboard.

## One-time database setup

Run [`027_push_devices.sql`](../migrations/027_push_devices.sql) in the existing database. From local `psql` connected to that database:

```psql
\i '/Users/tsoof/dev/system_app/system_app_back_end/migrations/027_push_devices.sql'
```

Alternatively paste the SQL file's contents into your database SQL editor. The app never applies migrations automatically. Push stays disabled until `APNS_ENABLED=true` and all required settings exist.

## Apple and server setup

1. In Apple Developer, enable **Push Notifications** for the app's existing explicit App ID and regenerate its provisioning profile. In Xcode, confirm Runner's signing team and bundle identifier. The checked-in entitlement uses `APS_ENVIRONMENT`: development for Debug, production for Release/Profile.
2. Create an APNs signing key in Apple Developer and store the `.p8` as a server secret file. Configure these values on the web service **and the notification cron service**: `APNS_ENABLED=true`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC` (the exact app bundle ID), and `APNS_KEY_FILE` (absolute secret-file path). Install the updated requirements. Never put the key in Git or in Flutter.
3. Create a separate Render cron, every minute, using the same repository and `DATABASE_URL`. Command: `cd system_app_back_end && python scripts/send_push_notifications.py`. Keep the existing automation cron. Separate execution lets notifications observe committed window state while an AI action is still running.
4. Rebuild and sign the iPhone app, then allow notifications. Debug uses the APNs sandbox; TestFlight/App Store use production. If installing a Release build with a **development** provisioning profile, set `APS_ENVIRONMENT=development` and `APNS_ENVIRONMENT=sandbox` for that build. These must match the signed profile. A simulator/unsigned compile cannot verify actual APNs delivery.

## Delivery behavior

- `/push-devices/register` associates one installation with its selected presentation workspace and language. Profile changes replace that association. This follows the app's existing profile system; it does not add authentication.
- The independent minute dispatcher reads live section/task state. New attention produces an alert and a badge equal to the number of sections needing attention. Completing tasks sends the updated badge, including zero. An aggregate notification uses a collapse ID to avoid a stack of stale section banners.
- Accepted state is stored per installation; unchanged state sends nothing. Transient failures retry on the next tick with **current** state. Invalid tokens are disabled. Delivery holds a row lock to serialize concurrent cron workers and profile changes. APNs acceptance is not proof that the device displayed the message; network/OS delivery can be delayed.
- Notification payloads contain a section title and a generic task reminder, not journal content. Hebrew and English follow the app language.
- Foreground reconciliation sets the badge directly and removes old delivered section banners. Once enrolled, the app stops producing duplicate local section notifications. A backend outage retains the last enrollment flag; registrations retry on full refresh. Profile changes require connectivity before their server association can update.
- No silent background execution is required: iOS receives the visible notification and badge while the app is closed. APNs credentials and the cron are required; changing frontend code alone cannot enable that.

## Verification before enabling broadly

On a signed physical iPhone: open a timed section while the app is closed; verify its reminder and badge. Complete its tasks on the laptop; verify the badge clears within the next delivery cycle. Reopen the phone and confirm current sidebar dots/content, no duplicate local banner, and no keyboard reopening after a remote refresh. Switch presentation profiles and confirm subsequent notifications follow the new profile. Deny/re-enable notification permission and verify registration recovers.

Apple references: [APNs requests](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns), [token authentication](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns).
