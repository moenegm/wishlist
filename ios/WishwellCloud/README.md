# Wishwell (iCloud)

The iPhone/iPad app, rebuilt on iCloud. The Rails-backed app in `../Wishwell` stays as it is until this one ships. Open `Wishwell.xcodeproj`, scheme `Wishwell`. It uses the original bundle ID `com.nujoomdigital.wishwell` and displays as **Wishwell**, so it ships as an update to the existing app. Installing it on a device replaces the Rails-backed build there.

## Storage

- SwiftData maintains the local library; Apple's CloudKit mirroring handles private-database uploads, downloads, and offline changes.
- Container: `iCloud.com.nujoomdigital.wishwell`. Enable iCloud/CloudKit and Push Notifications for the app identifier in the developer account. Background remote notifications are declared.
- Every CloudKit model property has a default or is optional, relationships are optional and have inverses, and UUIDs do not use unsupported uniqueness constraints.
- The local store URL is partitioned by a SHA-256 digest of the CloudKit user record ID. Account-change notifications close the displayed library; reopening verifies the matching identity. A device's unchanged iCloud Drive identity permits an offline reopen of an already verified account when the user record lookup fails specifically for network reasons. A new identity never inherits the previous account's cached store.
- The optional on-device library has its own store with CloudKit explicitly disabled. It is not silently uploaded into an account later. Transfer via backup/import is an explicit action.
- A failed store initialization is shown rather than silently replacing the library with an empty store. Save failures roll back and are shown. Core Data mirroring events provide sync status; enabling iCloud is not represented as proof that all changes have uploaded.
- Lists are private by default. The Rails visibility flag is deliberately not converted into a public CloudKit record. A public copy exists only after the owner turns on the Public switch for that list; backups and imports never restore a publication ID. Sharing a text copy uses an explicit system share sheet and creates a copy, not a live collaborative list.

## Included

Lists/categories, wishes, moving wishes between lists, three store/link-price options (typed web addresses open as links and show as the store's site), reversible fulfillment, a fulfilled-items filter, local profile with a framed photo, a Light/Dark/Match phone appearance setting, JSON backup/export, duplicate-safe restore, and an opt-in read-only copy from the website. No account password is needed for normal use.

Website import creates a temporary bearer session with the old service, copies only the signed-in user's lists/options/fulfilled flags, and attempts to revoke that session before returning. Passwords/tokens are not persisted. Previously imported list IDs are skipped to preserve local edits. Imported lists are private. The website is not modified or shut down.

## Circle and gifts

Wishwell is for helping family and friends buy each other gifts, so the social side is small on purpose. It uses CloudKit's public database and is on (`WishwellSocialEnabled = true` in `Info.plist`; set it to `false` to ship without it). See `CloudKit/README.md` for record types and permissions.

- **Public account:** one switch under Your profile in Settings. It publishes the name and photo; turning it off removes the public profile, public lists and everything the person added.
- **Circle:** a grid of the people you've added, searchable by name. Tapping someone shows their public lists.
- **Public lists:** a Public switch on each list and when creating one. Making a list private keeps its record with only the IDs of its wishes, so "I'm getting this" marks survive and come back if the list is made public again.
- **"I'm getting this":** marks a wish on someone else's list. Other people see who; the owner only sees "Someone might be getting this". Marks are stored in the `WWLike` record type (likes are no longer used), as a `GiftClaim` payload. Undoing keeps the record, marked inactive, so the owner can be told the wish is open again.
- **Blocking and reporting** profiles and lists.

The circle, people's lists and notifications are kept on the phone (`WishwellCircle.json` in Application Support) so screens open instantly and refresh in the background. A new account never sees the previous account's copy.

## Notifications

Notifications come from nujoomdigital.com (the NujoomDigitalSite repository, `Wishwell::PushController`), not CloudKit subscriptions, which never delivered. The app registers each phone's push token with the site and reports every follow and claim it saves; the site reads the record from the public database with a CloudKit server-to-server key to confirm it, writes the message itself and sends it through Apple's push service. Each notification carries the list and wish or the person it's about, and raises the app icon's number, which the app resets to its real unread count.

When a list or wish is deleted, moved or marked fulfilled, the owner's app reports it first; the site notes who was getting those wishes, then tells them a minute later only if iCloud shows the change really happened. The owner never learns who.

A background refresh task keeps the icon's number current and, on phones not registered with the site, shows its own banners.

Xcode builds use the development CloudKit environment and Apple's push sandbox; App Store builds use production for both. The site needs its own server key for each CloudKit environment.

## Support Wishwell

Optional one-time tips use StoreKit 2, signed transaction verification, handling of cancellation/pending approval, unfinished transactions, and transaction completion. No feature depends on paying. Create these as **consumable** products in App Store Connect ($0.99, $2.99, $4.99):

- `com.nujoomdigital.wishwell.tip.small`
- `com.nujoomdigital.wishwell.tip.medium`
- `com.nujoomdigital.wishwell.tip.large`

The UI uses Apple's localized product names and prices. When products are not configured, it says so and does not simulate a purchase. `Wishwell.storekit` holds local tip products for trying the tip jar from Xcode.

## Privacy and support

The privacy policy is the Wishwell section of https://nujoomdigital.com/privacy and support is https://nujoomdigital.com/support#wishwell (both in the NujoomDigitalSite repository); Settings links to both and to contact@nujoomdigital.com. The App Store privacy answers are in `AppStore/app-privacy.md`.

## Tests

`swift test --package-path ios/WishwellCloud` from the repo root runs the storage and social tests on macOS against isolated in-memory databases. The social tests cover authorship and impersonation attempts, edits to other people's records, stale republishing, account switches mid-operation, report privacy, blocking, profile removal, gift claims (who sees what, duplicates, undo, iCloud's search lagging behind a new claim), private lists, new-wish notifications and kept notices. They don't exercise Apple's server-side permissions.

The simulator UI tests use the debug-only `--social-preview` argument (an on-device library plus made-up people in memory, never contacting CloudKit) and `--local-preview`. `--social-preview` also works on a phone for trying the circle.

Opt-in device tests (`TEST_RUNNER_WISHWELL_LIVE_SOCIAL=1`) run against the development CloudKit service with two accounts; see `CloudKit/README.md`. Debug-only launch arguments for diagnosis: `--social-live-check`, `--dump-social` (prints what iCloud holds for your lists), `--check-activity` (runs the background check in the foreground).

## Before release

1. Deploy the development schema to production and assign the Moderator role there.
2. Create a production CloudKit server-to-server key and add it to the site's credentials as `cloudkit_production_key_id` / `cloudkit_production_key`.
3. Create the tip products, test them in the sandbox, and complete the App Store listing, privacy answers and review notes.
4. Archive a Release build and upload it.
