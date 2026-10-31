# App-only conversion

## Product decisions

Wishwell is becoming an iPhone/iPad product with no Rails/Supabase dependency for normal operation. Apple manages cloud storage. Downloading and using all functional features remains free. Support Wishwell is an optional one-time tip; subscriptions, paid feature limits, and affiliate links are not part of this conversion.

The conversion lives in `ios/WishwellCloud` on `feature/icloud-conversion`. `ios/Wishwell` and the Rails site remain available during migration. The preview has a separate bundle identifier and installs alongside the old app. Do not remove the old services or assume old accounts/data have migrated.

## First implementation

SwiftUI views use SwiftData models directly instead of routing local operations through HTTP-shaped methods. Local writes save immediately and failures are surfaced. CloudKit mirroring synchronizes the private library. An optional, separate on-device library works without an iCloud account. Changing library type does not upload or merge existing data implicitly.

The original visual palette, iPad sidebar, iPhone tabs, three shopping options, moving wishes, and fulfillment are retained. Lists in this preview are private. A text share is a static copy, clearly labeled. JSON backups let a user transfer personal lists explicitly. A temporary read-only website import is the only code path that contacts Render; credentials are entered by the user and never stored.

The preview includes StoreKit purchase handling and an honest unavailable state before tip products are configured. Product names/prices come from Apple; prices and App Store Connect banking/tax agreements have not been selected or accepted.

## Social architecture to validate before implementation is enabled

Private SwiftData mirroring is not a public social backend and does not support arbitrary access rules between records. Public profiles and interactions require direct CloudKit APIs plus a public-database schema and indexes. A separate persistence boundary is needed; do not add a `public` Boolean to private models and assume other people can read them.

Proposed boundaries:

| Data | Storage / authority |
| --- | --- |
| Personal lists, wishes, prices, fulfillment, private profile settings | User's private CloudKit database with local SwiftData replica |
| Discoverable profile | Explicitly published public profile; CloudKit creator is the authoritative identity |
| Public list/wish content | Explicit public projection of owner-authored content; never an implicit upload of all private rows |
| Follows / likes / comments | Public records authored by the acting iCloud user, linked to a real published parent |
| Read state and user preferences | Recipient's private database |
| Activity | Derived from verified social records/subscriptions; no client-supplied recipient messages containing private content |

Public record permissions must allow creating appropriate records as an authenticated user and updating/deleting only as the Creator. User IDs, actor names, and counts supplied by a client are not trusted as authorization. Check parent references and creator identity on reads as well as writes. Specify query indexes before enabling discovery.

Unpublishing must remove the public projection and dependents without deleting the private original. CloudKit's `deleteSelf` references can cascade deletion, but default-zone cascading is asynchronous. Verify behavior for records authored by other people, privacy transitions, stale devices, and offline pending writes before making the publishing UI available. A public cache cannot make already shared copies disappear; communicate copying/sharing honestly.

The existing Rails authorization rules are a test matrix for the replacement: non-owners cannot modify wishes or lists, private content cannot be fetched by another account, comments are deletable by their authors, and historical activity must not reveal subsequently private titles. Add blocking, reporting, and moderation before shipping public user-generated content.

## Data migration

Personal lists can be copied from the old API after the owner signs in. All imported lists start private, including ones previously public. UUIDs become the native identity; old list/wish IDs are retained only for import deduplication. Repeating an import skips already imported lists to avoid replacing local edits.

Old email/password identities do not become Apple identities. Existing follows, likes, comments, and notification history must not be fabricated under a new iCloud author. Plan any social-history migration separately. If Supabase is unavailable, the optional import remains blocked until database access is recovered; new personal-library usage does not depend on it.

## Release gates

Initial verification (October 29, 2026): storage tests and iPhone/iPad offline UI tests pass. A physical iPad created a three-option fulfilled wish in private CloudKit and a physical iPhone received and displayed it successfully. Both preview builds have the intended CloudKit container and development push entitlement. No real website account was imported and no tips were charged.

- Same-account iPhone/iPad sync, including fulfillment, deletion, movement, photo, offline updates, and conflicts.
- Account-switch privacy test: edit offline as A, change iCloud account to B, relaunch, and confirm A's library is neither displayed nor uploaded into B.
- No-account, iCloud disabled, full quota, interrupted sync, and error recovery.
- Two unrelated iCloud accounts for social permissions, private/public transitions, and notifications.
- Read-only migration checked against source before retiring the database.
- Consumable tips configured and sandbox tested, including cancellation, pending approval, interrupted delivery, and repeated tips.
- Production CloudKit schema deployment, production identity/signing, privacy policy, support page, App Store privacy answers, accessibility and device QA.

The preview is a development build, not an App Store submission or a completed social migration.
