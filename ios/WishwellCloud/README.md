# Wishwell iCloud conversion preview

This is a separate iPhone/iPad app while the Rails-backed app in `../Wishwell` remains operational. Open `Wishwell.xcodeproj`, scheme `Wishwell`. The preview uses bundle ID `com.nujoomdigital.wishwell.icloudpreview` and displays as **Wishwell Preview**, so testing does not replace the existing app or its Keychain sessions.

## Storage

- SwiftData maintains the local library; Apple's CloudKit mirroring handles private-database uploads, downloads, and offline changes.
- Container: `iCloud.com.nujoomdigital.wishwell`. Enable iCloud/CloudKit and Push Notifications for the preview identifier in the developer account. Background remote notifications are declared.
- Every CloudKit model property has a default or is optional, relationships are optional and have inverses, and UUIDs do not use unsupported uniqueness constraints.
- The local store URL is partitioned by a SHA-256 digest of the CloudKit user record ID. Account-change notifications close the displayed library; reopening verifies the matching identity. A device's unchanged iCloud Drive identity permits an offline reopen of an already verified account when the user record lookup fails specifically for network reasons. A new identity never inherits the previous account's cached store.
- The optional on-device library has its own store with CloudKit explicitly disabled. It is not silently uploaded into an account later. Transfer via backup/import is an explicit action.
- A failed store initialization is shown rather than silently replacing the library with an empty store. Save failures roll back and are shown. Core Data mirroring events provide sync status; enabling iCloud is not represented as proof that all changes have uploaded.
- All lists are private in this preview. The Rails visibility flag is deliberately not converted into a public CloudKit record. Sharing a text copy uses an explicit system share sheet and creates a copy, not a live collaborative list.

## Included

Lists/categories, wishes, moving wishes between lists, three store/link-price options, reversible fulfillment, a fulfilled-items filter, local profile/photo, JSON backup/export, duplicate-safe restore, and an opt-in read-only copy from the website. No account password is needed for normal use.

Website import creates a temporary bearer session with the old service, copies only the signed-in user's lists/options/fulfilled flags, and attempts to revoke that session before returning. Passwords/tokens are not persisted. Previously imported list IDs are skipped to preserve local edits. Imported lists are private. Profiles, follows, likes, comments, and notification history are not migrated in this first pass. The website is not modified or shut down.

## Support Wishwell

Optional one-time tips use StoreKit 2, signed transaction verification, handling of cancellation/pending approval, unfinished transactions, and transaction completion. No entitlement or feature depends on paying. Create these as **consumable** products in App Store Connect:

- `com.nujoomdigital.wishwell.tip.small`
- `com.nujoomdigital.wishwell.tip.medium`
- `com.nujoomdigital.wishwell.tip.large`

The UI uses Apple's localized product names and prices. When products are not configured or available, it says so and does not simulate a purchase. Prices, agreements, banking/tax setup, sandbox transactions, and product submission remain release work.

## Verification

`swift test --package-path ios/WishwellCloud` from the repo root runs the storage tests on macOS. These use isolated in-memory databases with CloudKit disabled. They cover option validation, URL schemes, backup round trips, duplicate restore, invalid-import atomicity, moving wishes, and fulfilled sorting.

The UI test `testOfflineWishPersistsWithThreeOptionsAndFulfillment` launches with the debug-only `--local-preview` argument, requires no website or iCloud account, and verifies disk persistence after app relaunch. `testCreateCloudSyncFixture` and `testReadCloudSyncFixture` are opt-in physical-device tests for two devices using the same iCloud account. They create a clearly named synthetic wishlist in the development environment; they do not inspect unrelated personal content. They skip on simulators. Run these with `-only-testing:` rather than the whole test suite on a physical device.

## Remaining conversion work

Verified on October 29, 2026: four storage tests pass; offline create/three-options/fulfill/relaunch UI tests pass on iPhone and iPad simulators; a signed physical iPad created a private CloudKit wish and a signed physical iPhone received the same wish with its three options and fulfilled status. Debug/device and Release/simulator builds pass. Account-switch privacy, offline cross-device conflict resolution, deletion propagation, photo sync, social permissions, and real purchases are still unverified.

1. Verify private sync on the same account across iPhone/iPad, offline reconciliation, deletion, photo sync, quota errors, and switching between unrelated accounts on devices. Compiling and a visible empty library are not sufficient evidence of cross-device sync.
2. Implement the social layer separately from private SwiftData mirroring. Public profiles, discovery, following, public-list projections, likes, comments, and activity need direct CloudKit APIs and a reviewed public-database schema. SwiftData's private automatic sync does not implement these features.
3. Configure and test server-enforced Creator-only write/delete permissions for public record types. Derive authorship from CloudKit's creator identity, not client-provided user IDs. Never put private titles or options in public activity records. Validate public-to-private removal of dependent social records before enabling publishing. Public default-zone cascading deletion is asynchronous; design and communicate that transition explicitly.
4. Add block/report controls, content moderation arrangements, profile/content deletion, notification subscriptions, privacy policy/support URLs, and App Store privacy information before exposing social content or submitting.
5. Verify backup/import with a real existing account and explicit user input. Keep services running until required personal data has been copied and checked. Social-history migration needs a separate decision; do not forge past likes/comments under new Apple identities.
6. Select the production bundle ID/build, deploy the validated CloudKit development schema to production, test StoreKit sandbox products, and complete App Store signing/review. No production CloudKit schema or App Store build has been submitted by creating this preview.

Apple references: [CloudKit databases](https://help.apple.com/xcode/mac/current/en.lproj/dev52452c426.html), [sharing private records](https://developer.apple.com/documentation/cloudkit/ckshare), [cascading deletion](https://developer.apple.com/documentation/cloudkit/ckrecord/referenceaction/deleteself), [iCloud identity changes](https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/nsubiquityidentitydidchange).
