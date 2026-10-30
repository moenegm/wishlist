# Wishwell iCloud conversion preview

This is a separate iPhone/iPad app while the Rails-backed app in `../Wishwell` remains operational. Open `Wishwell.xcodeproj`, scheme `Wishwell`. The preview uses bundle ID `com.nujoomdigital.wishwell.icloudpreview` and displays as **Wishwell Preview**, so testing does not replace the existing app or its Keychain sessions.

## Storage

- SwiftData maintains the local library; Apple's CloudKit mirroring handles private-database uploads, downloads, and offline changes.
- Container: `iCloud.com.nujoomdigital.wishwell`. Enable iCloud/CloudKit and Push Notifications for the preview identifier in the developer account. Background remote notifications are declared.
- Every CloudKit model property has a default or is optional, relationships are optional and have inverses, and UUIDs do not use unsupported uniqueness constraints.
- The local store URL is partitioned by a SHA-256 digest of the CloudKit user record ID. Account-change notifications close the displayed library; reopening verifies the matching identity. A device's unchanged iCloud Drive identity permits an offline reopen of an already verified account when the user record lookup fails specifically for network reasons. A new identity never inherits the previous account's cached store.
- The optional on-device library has its own store with CloudKit explicitly disabled. It is not silently uploaded into an account later. Transfer via backup/import is an explicit action.
- A failed store initialization is shown rather than silently replacing the library with an empty store. Save failures roll back and are shown. Core Data mirroring events provide sync status; enabling iCloud is not represented as proof that all changes have uploaded.
- Lists are private by default. The Rails visibility flag is deliberately not converted into a public CloudKit record. A public copy exists only after the owner explicitly publishes a list from its sharing menu; backups and imports never restore a publication ID. Sharing a text copy uses an explicit system share sheet and creates a copy, not a live collaborative list.

## Included

Lists/categories, wishes, moving wishes between lists, three store/link-price options, reversible fulfillment, a fulfilled-items filter, local profile/photo, JSON backup/export, duplicate-safe restore, and an opt-in read-only copy from the website. No account password is needed for normal use.

The social layer (public profiles and name search, following, explicit list publishing/unpublishing, likes, comments, notifications with synced read markers, blocking, reporting, and public-profile removal) is implemented against CloudKit's public database but is **switched off** by `WishwellSocialEnabled = false` in `Info.plist`. It stays off until the schema in `CloudKit/` is imported to development and its permissions are verified on Apple's service with two real accounts. See `CloudKit/README.md`.

Website import creates a temporary bearer session with the old service, copies only the signed-in user's lists/options/fulfilled flags, and attempts to revoke that session before returning. Passwords/tokens are not persisted. Previously imported list IDs are skipped to preserve local edits. Imported lists are private. Profiles, follows, likes, comments, and notification history are not migrated in this first pass. The website is not modified or shut down.

## Support Wishwell

Optional one-time tips use StoreKit 2, signed transaction verification, handling of cancellation/pending approval, unfinished transactions, and transaction completion. No entitlement or feature depends on paying. Create these as **consumable** products in App Store Connect:

- `com.nujoomdigital.wishwell.tip.small`
- `com.nujoomdigital.wishwell.tip.medium`
- `com.nujoomdigital.wishwell.tip.large`

The UI uses Apple's localized product names and prices. When products are not configured or available, it says so and does not simulate a purchase. Prices, agreements, banking/tax setup, sandbox transactions, and product submission remain release work.

## Verification

`swift test --package-path ios/WishwellCloud` from the repo root runs the storage tests on macOS. These use isolated in-memory databases with CloudKit disabled. They cover option validation, URL schemes, backup round trips, duplicate restore, invalid-import atomicity, moving wishes, and fulfilled sorting.

`SocialTests` run the social rules against an in-memory two-account database: creator-derived authorship and impersonation attempts, rejection of edits to another person's records, stale-device republish refusal, account switches mid-operation, report privacy, blocking, and profile removal. The storage tests also check that backup imports never restore a publication ID. These are domain tests. They do not exercise Apple's server-side permission enforcement.

`testSocialPreviewLikeAndComment` and `testPrivateListPublishAndUnpublishInSocialPreview` use the debug-only `--social-preview` argument: an on-device library plus a synthetic in-memory social database. They never contact CloudKit and are unavailable in Release builds.

`--social-live-check` opens a debug-only diagnostic screen on a signed physical device. It bypasses opening the private library and uses synthetic records in the actual development public database to check identity, own-record create/read/update, reporting, and stale-save rejection after deleting a test root. It leaves a synthetic profile, list, interactions, and report for the second-account checks. Fixture IDs and results are stored locally in Documents as `social-live-check-fixture.json` and `social-live-check-results.txt`; neither is part of a library backup. Normal launches still honor the disabled social feature flag. A first-account pass does not verify cross-account enforcement.

The UI test `testOfflineWishPersistsWithThreeOptionsAndFulfillment` launches with the debug-only `--local-preview` argument, requires no website or iCloud account, and verifies disk persistence after app relaunch. `testCreateCloudSyncFixture` and `testReadCloudSyncFixture` are opt-in physical-device tests for two devices using the same iCloud account. They create a clearly named synthetic wishlist in the development environment; they do not inspect unrelated personal content. They skip on simulators. Run these with `-only-testing:` rather than the whole test suite on a physical device.

## Remaining conversion work

Verified on October 29, 2026: four storage tests pass; offline create/three-options/fulfill/relaunch UI tests pass on iPhone and iPad simulators; a signed physical iPad created a private CloudKit wish and a signed physical iPhone received the same wish with its three options and fulfilled status. Debug/device and Release/simulator builds pass. Account-switch privacy, offline cross-device conflict resolution, deletion propagation, photo sync, Moderator access, complete live social UI workflows, and real purchases remain unverified.

Social layer, also October 29, 2026: 20 storage/social unit tests pass on macOS; the simulated social UI tests (like/comment, publish then make private) and the offline library test pass on both iPhone and iPad simulators; the Release simulator build passes. The combined schema was imported into development on October 29, 2026. A fresh server export confirms that all existing definitions and the six social types, indexes, and grants were preserved; Apple added standard system fields. Reports have no World or general iCloud read grant. Live social features remain disabled, and the initial two-account permission checks have since passed; Moderator access and complete social UI workflows remain unverified.

October 30, 2026: profile search now matches every typed word, so a full name finds a person; previously only a single word worked. Normal social reads ignore synthetic diagnostic records. 22 storage/social unit tests pass. The four live social UI tests passed across two iPhones with distinct Apple accounts on development CloudKit; see `CloudKit/README.md` for coverage and the fixes they led to.

1. Verify private sync on the same account across iPhone/iPad, offline reconciliation, deletion, photo sync, quota errors, and switching between unrelated accounts on devices. Compiling and a visible empty library are not sufficient evidence of cross-device sync.
2. Completed: imported the reviewed combined schema into **development**, then compared the server export against the reviewed definitions. Production has not been deployed.
3. Completed on October 29, 2026 through direct adapter diagnostics with two Apple accounts: Creator-only write/delete, report privacy, dependent removal after unpublishing, and stale-save rejection. The four `testLiveSocial…` UI tests then passed across both phones on October 30, 2026. The Moderator role was then assigned to the owner's account in development and verified with `--moderator-check`, and all synthetic fixtures were removed from both accounts. The planned live checks are complete. Enabling `WishwellSocialEnabled` for the development preview is now a product decision; read markers syncing from iPhone to iPad on the same account, and the iPad social screens, were checked on October 30, 2026. Before production, make sure every SwiftData model has a record type in the deployed schema (see `CloudKit/README.md`). See `CloudKit/README.md`.
4. Push alerts for follows, likes and comments are in (CloudKit query subscriptions, generic alert text, permission asked when a profile is published). They still need a check on a device with the app closed. Drafts of the privacy policy and App Store privacy answers are in `AppStore/`; fill in the date and support email, host the policy, and set up a support page. Reports are reviewed in CloudKit Console by the Moderator account.
5. Verify backup/import with a real existing account and explicit user input. Keep services running until required personal data has been copied and checked. Social-history migration needs a separate decision; do not forge past likes/comments under new Apple identities.
6. Select the production bundle ID/build, run `--social-live-check --initialize-cloudkit-schema` once on a signed device so every SwiftData type and field exists in development (the first attempt failed with a generic Core Data error; the next run logs the full error), deploy the validated development schema to production and assign the Moderator role there, test StoreKit sandbox products, and complete App Store signing/review. `Wishwell.storekit` holds local tip products for trying the tip jar from Xcode (it's attached to the scheme's Run action; not yet tried). No production CloudKit schema or App Store build has been submitted by creating this preview.

Apple references: [CloudKit databases](https://help.apple.com/xcode/mac/current/en.lproj/dev52452c426.html), [sharing private records](https://developer.apple.com/documentation/cloudkit/ckshare), [cascading deletion](https://developer.apple.com/documentation/cloudkit/ckrecord/referenceaction/deleteself), [iCloud identity changes](https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/nsubiquityidentitydidchange).

Live first-account verification on October 29, 2026: a signed iPhone passed CloudKit identity, profile creation with creator metadata, own-profile read/update, synthetic list publication, like/comment creation, own-report create/read, and server rejection of a stale save after deleting a synthetic public root. The initial run found that WWReport needed explicit Creator read permission; this was corrected in development and in social.ckdb, with a schema regression assertion. All 20 unit tests pass, and Debug/device and Release/simulator builds succeed. That first-account run did not yet verify cross-account report denial, foreign-record write/delete denial, dependent deletion, or Moderator access; see the subsequent two-account results below. Synthetic fixtures remain for second-account checks and must be removed before ordinary social use. Normal social features stay disabled.

## Two-account live checks

On October 29, 2026, two signed iPhones using distinct Apple accounts passed public profile/list reads and creator queries, server rejection of foreign profile/list edits and deletion, report privacy through direct fetch and query, and following/liking/commenting with own-interaction deletion in both directions. The list owner then unpublished a synthetic root with the other account’s like/comment; that account verified all three records were absent, and the server rejected a stale recreation. Debug/device and Release/simulator builds pass.

These are actual development CloudKit adapter checks. Moderator access and complete social screens still need live joint testing. Normal social features remain disabled and production is unchanged. Synthetic fixtures must be removed before ordinary social use. Diagnostic arguments and remaining checks are documented in [CloudKit setup](CloudKit/README.md#two-account-live-checks).
