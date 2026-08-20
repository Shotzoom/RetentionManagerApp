# Retention Manager

A macOS app for managing subscription retention messages through [Apple's Retention Messaging API](https://developer.apple.com/documentation/retentionmessaging).

When a subscriber starts to cancel an auto-renewable subscription, the App Store can show a retention message — a value reminder, a switch-plan suggestion, or a promotional offer — chosen in real time by your server. This tool manages the full lifecycle of those messages:

- **Create** text, alternate-product, and promotional-offer messages, with live character counters for Apple's limits (66-char header, 144-char body)
- **Translate** messages to Spanish, French, and German automatically (on-device FoundationModels)
- **Upload** messages and images to Apple's sandbox or production environment
- **Sync** with Apple to track review states (PENDING / APPROVED / REJECTED) and default-message configuration
- **Set the Apple default** message per product/locale — the fallback Apple shows when your server doesn't respond in time
- **Configure your realtime endpoint** URL with Apple (sandbox and production)
- **Run Apple's performance test**, which must pass before production can be enabled
- **Export** messages as SQL insert statements for your server's database (`ITunesRetentionDefinitions`) or as CSV for backup/transfer between machines

## Requirements

- macOS 15+, Xcode 16+
- An Apple Developer account with **Retention Messaging API access granted** (request it via [Apple's form](https://developer.apple.com/contact/request/retention-messaging-api/) — endpoints return empty 404s until the grant is active)
- An **In-App Purchase key** (.p8) from App Store Connect → Users and Access → Integrations → In-App Purchase
- A server implementing the [Get Retention Message endpoint](https://developer.apple.com/documentation/retentionmessaging/setting-up-retention-messaging-endpoint) (must respond within ~700 ms)

## First Launch: Configuration

On first launch the app presents a configuration screen. Nothing sensitive is stored in the repo — all values live in local app storage on your Mac.

| Field | Where to find it |
|-------|------------------|
| Team ID | developer.apple.com/account → Membership (10 characters) |
| Issuer ID | App Store Connect → Users and Access → Integrations → In-App Purchase |
| Key ID | The ID of your In-App Purchase key |
| .p8 Private Key | Downloaded when you created the In-App Purchase key (import the file) |
| Bundle ID | The app whose subscriptions get retention messages |
| Product IDs | Comma-separated list of auto-renewable subscription product IDs |
| Sandbox Endpoint URL | Your server's Get Retention Message URL (optional here; also settable in Settings) |

### Creating the In-App Purchase key

1. In [App Store Connect](https://appstoreconnect.apple.com) (requires **Account Holder or Admin** role), go to **Users and Access → Integrations**
2. Under **Keys** in the sidebar, select **In-App Purchase**
3. Click **Generate In-App Purchase Key** (or **+**), name it, and click **Generate**
4. Click **Download Key** — ⚠️ the `.p8` downloads **only once**; Apple keeps no copy, so store it securely
5. Note the **Issuer ID** (top of that page) and the key's **Key ID** — the setup screen needs both

This key type is specific to the in-app purchase APIs (App Store Server API + Retention Messaging) — a general App Store Connect API key will not work. The key needs no additional permission configuration.

> **Internal shortcut**: type `golfshot` into the Team ID field and hit Save to load the internal default configuration from a bundled `DefaultConfig.json`.
>
> Both `DefaultConfig.json` and `.p8` key files are **gitignored and never committed**. For the shortcut to work on a fresh clone, obtain both from a teammate via a secure channel and place them in the `RetentionManager/` sources folder (next to `Configuration.swift`) before building — they're bundled automatically. `DefaultConfig.json` contains: `teamID`, `issuerID`, `keyID`, `p8FileName` (the .p8 filename without extension), `bundleID`, `sandboxRealtimeEndpointURL`, and `productIDs` (array). Without these files, the shortcut shows an error and you configure manually instead.

The configuration can be edited any time via **Settings (⌘, or the gear icon) → Edit Configuration**.

## Getting Fully Set Up and Tested

1. **Register your sandbox endpoint.** Settings → Realtime Endpoint → enter your sandbox URL → **Configure** (or **Fetch Current** to verify an existing registration). URLs must be HTTPS.
2. **Create your messages.** At minimum:
   - One message for your server to return in real time (e.g. a promotional offer)
   - One **text-only** message to be Apple's default fallback (promo/switch-plan messages cannot be defaults)
3. **Upload to Apple** (button on each message), then **Sync from Apple** until they show APPROVED. Sandbox approves automatically; production goes through review.
4. **Set the default.** Open the approved text message → **Set as Default**. Requires the message to be APPROVED; the app converts locales to App Store codes (e.g. `en` → `en-US`) automatically.
5. **Export to your server's database.** Export → SQL generates `DELETE` + `INSERT` statements for `dbo.ITunesRetentionDefinitions` (Apple-default messages are deliberately excluded — they're Apple's fallback, not served by your API). Use the **Copy** button to paste directly into your SQL client.
6. **Run the performance test.** Settings → Performance Test → enter the original transaction ID of an **active sandbox subscription** → **Initiate**, then **Check Results** until it reports PASS (success rate, latency percentiles, and failure reasons are shown). Apple fires test traffic at your *sandbox* endpoint; responses must beat the ~700 ms threshold.
7. **Go to production.** Once the test passes, switch the environment picker to Production, configure the production realtime URL, upload/approve production messages, and set production defaults.

## Environments

The Settings environment picker switches every API call between:

- **Sandbox** — `api.storekit-sandbox.apple.com` (auto-approval, performance tests)
- **Production** — `api.storekit.apple.com` (live customers, real review)

Messages, defaults, and endpoint URLs are configured **separately per environment**.

## Moving to Another Machine

The local database lives in the app's container and is not part of the repo. To migrate:

1. **Export → CSV** on the old machine (full backup format, includes Apple-default messages)
2. **Import** the CSV on the new machine — message identifiers are preserved
3. **Sync from Apple** — upload statuses, review states, and default-message flags are restored from Apple

Limitation: image binary data isn't included in CSV (only the image reference); re-add images manually if needed.

## Good to Know

- **Messages on Apple are immutable** — there's no update API. Editing content means delete + re-upload (and re-review in production). The in-app Edit button edits full content for local-only messages, and only the internal cancellation scenario (server-side metadata) for uploaded ones.
- **Deleting** offers "Delete from Apple & Locally" vs "Delete Locally Only" for uploaded messages.
- **External messages** (uploaded outside this app) appear as placeholders after sync — Apple's API doesn't return message content, only identifiers and states.
- **Identifiers are lowercased** to match Apple's normalization.
- If every API call returns an empty-bodied 404, your account's API access grant isn't active yet.
