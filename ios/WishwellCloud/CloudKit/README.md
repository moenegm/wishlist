# Social schema setup

The app keeps social features disabled through `WishwellSocialEnabled` until development permissions have been configured and tested. Personal iCloud sync does not require this social schema. Neither a successful build nor the isolated social tests prove the permissions on Apple's actual service.

`social.ckdb` defines six public record types. The common `payload` contains JSON. Parent references use `deleteSelf`; Creator identity and creation time come from CloudKit system metadata, not the JSON payload.

| Type | Read | Create | Write/delete |
| --- | --- | --- | --- |
| WWProfile, WWList, WWFollow, WWLike, WWComment | World | Authenticated | Creator |
| WWReport | Creator, Moderator | Authenticated | Creator, Moderator |

Only explicitly published profiles and wishlist snapshots enter these types. Private SwiftData records remain in the private database. Reports must never be granted World or general Authenticated read access. Assign the Moderator role only to the account responsible for reviewing reports. Use CloudKit Console's report records as the moderation queue; confirm its access before enabling the reporting UI for real users.

## Prepare without disturbing personal sync

CloudKit management access is required. Authenticate `cktool` interactively with `xcrun cktool save-token --type management`; keep the token in Keychain and out of source code, shell history, and chat. No management credential belongs in the app.

Export the current development schema first:

```sh
xcrun cktool export-schema --team-id BCT33A5W39 \
  --container-id iCloud.com.nujoomdigital.wishwell \
  --environment development --output-file /tmp/wishwell-existing.ckdb
python3 ios/WishwellCloud/CloudKit/prepare_schema.py \
  /tmp/wishwell-existing.ckdb /tmp/wishwell-social-reviewed.ckdb
xcrun cktool validate-schema --team-id BCT33A5W39 \
  --container-id iCloud.com.nujoomdigital.wishwell \
  --environment development --file /tmp/wishwell-social-reviewed.ckdb
```

Review the combined schema, especially all pre-existing private types and indexes. Do **not** import `social.ckdb` alone over the existing schema; it is a fragment. The preparation script appends to the unmodified export and refuses an initial automatic merge if social types or the Moderator role already exist. Later schema revisions need a reviewed diff against a fresh export.

After validation/review, import the combined file into **development** with `cktool import-schema` using the same team/container/environment/file arguments. Do not run `reset-schema` or delete existing records. Export again and compare the server schema against the reviewed file. No production schema deployment is included here.

## Live verification before enabling

1. Use two unrelated Apple accounts. Publish synthetic profiles and one list each.
2. Confirm each can read public records and create own interactions, but cannot update/delete the other's records using direct CloudKit operations.
3. Confirm names/owners supplied in payloads cannot impersonate CloudKit creator identity in app reads.
4. Confirm one user cannot read the other's report records, while the assigned Moderator can review them.
5. Unpublish a list with the other user's comments/likes. Verify dependent deletion and reject parentless/stale writes. Default-zone cascading is asynchronous; never treat a surviving child as permission to display private content.
6. Verify a stale/offline device does not recreate an unpublished list. Only an explicit new publish action may create a new public root.
7. Check follows, likes/unlikes, comments/deletion, new-wish activity, private synced read markers, blocking/unblocking, and public-profile removal.
8. Once these checks pass, enable `WishwellSocialEnabled` for the development preview and build both devices for joint testing. Production deployment and App Store readiness are separate steps.

## Current limitations

The activity bell refreshes on foreground and pull-to-refresh. Push alerts come from CloudKit query subscriptions on the person's profile (follows) and each published list (likes and comments). They are created and removed as the profile and lists change, and carry generic text only. Each subscription is pinned to the public default zone. A list that was just published or unpublished is passed in directly, because the query index can lag a save by several seconds. Delivery with the app closed is not yet confirmed. Public-copy updates run while the app is open; private changes saved offline remain local/queued for private sync until connectivity returns. Republishing public copies waits for the app to run again. Activity is derived from current public records and shows the latest 100 entries, so deleted/unpublished activity disappears. Queries honor CloudKit cursors and fail explicitly at 2,000 results rather than silently returning incorrect totals; scale work will need UI pagination and server-side query batching. Blocked people are hidden on the user's devices; a public record remains publicly readable.

The two-account in-memory tests cover the domain's rules, not Apple's live permission enforcement. The debug-only `--social-preview` launch argument provides synthetic people and a wishlist for simulator UI testing. This preview uses an on-device library and an in-memory social database, shows a preview banner, never contacts the public CloudKit database, and is unavailable in Release builds.

## Development import status

On October 29, 2026, the reviewed combined schema passed Apple’s validation and was imported into development. The subsequent server export was compared with the reviewed schema: all nine record types, existing definitions, social indexes and grants, and the Moderator role are present. Differences were limited to standard system fields added by Apple. WWReport has no World or general iCloud read grant. This checks configuration only; the initial import did not verify actual two-account enforcement or Moderator access; see the subsequent live checks below. Production is unchanged.

For first-account testing, explicitly launch the signed debug app with `--social-live-check`. This diagnostic uses synthetic development public records without opening the private library. Keep normal social features disabled until the live checks above pass.

Live first-account verification on October 29, 2026: a signed iPhone passed CloudKit identity, profile creation with creator metadata, own-profile read/update, synthetic list publication, like/comment creation, own-report create/read, and server rejection of a stale save after deleting a synthetic public root. The initial run found that WWReport needed explicit Creator read permission; this was corrected in development and in social.ckdb, with a schema regression assertion. All 20 unit tests pass, and Debug/device and Release/simulator builds succeed. That first-account run did not yet verify cross-account report denial, foreign-record write/delete denial, dependent deletion, or Moderator access; see the subsequent two-account results below. Synthetic fixtures remain for second-account checks and must be removed before ordinary social use. Normal social features stay disabled.

## Two-account live checks

On October 29, 2026, signed iPhones using two distinct Apple accounts passed direct checks against the actual development CloudKit service in both directions:

- Read the other account’s public synthetic profile/list and query the profile by CloudKit creator.
- Server rejection of updates and deletion of the other account’s profile/list.
- The other account’s report remained hidden through direct record fetch and creator-filtered query.
- Create follows, likes, and comments on the other account’s content, then delete own interactions.
- Both accounts also passed their own-record checks and stale-save rejection after deleting a synthetic root.

For dependent deletion, one account created a like and comment on the other account’s synthetic list. Its owner unpublished that list and the server rejected a stale recreation. The interacting account then verified that the root, like, and comment were all absent. This is a live server observation, not a simulator or mock result. CloudKit cascading remains asynchronous. Debug/device and Release/simulator builds pass.

These checks exercise the direct CloudKit adapter, not the full social screens. Moderator assignment/access, live search UI, block/report flows, notifications/read markers, and public-profile removal still need joint testing. The normal social feature flag remains false. Synthetic fixtures remain for follow-up and must be removed before ordinary social use. Production is unchanged.

Diagnostic launch arguments (Debug, signed physical devices only):

- `--social-live-check --peer-profile PROFILE_ID LIST_ID REPORT_ID` runs own-record and cross-account checks and leaves synthetic cascade interactions.
- `--social-live-check --unpublish-fixture LIST_ID` deletes only an owned synthetic list and checks stale-save rejection.
- `--social-live-check --verify-cascade LIST_ID LIKE_ID COMMENT_ID` polls for the three synthetic records to become absent.

All supplied fixture IDs must begin with `wishwell-check-`. Results and fixture IDs are local diagnostic files, excluded from library backup. No private library is opened.

## Synthetic fixtures

Normal social reads ignore every record whose ID begins with `wishwell-check-`, so a leftover diagnostic profile can never be chosen as someone's public profile or appear in search, lists, threads, or activity. The records still exist on the server until removed.

- `--social-live-check --cleanup-fixtures` lists the current account's synthetic records (likes, comments, follows, reports, lists, profiles) and deletes nothing.
- `--social-live-check --cleanup-fixtures --confirm-delete` deletes exactly those records, children first, then confirms that each one is absent.

Cleanup only touches records whose CloudKit creator is the current account and whose ID has the synthetic prefix. Run it on each test account's device. Keep one synthetic report from each account until Moderator access has been checked.

## Moderator access

The schema grants WWReport read/write to the `Moderator` role. Assigning the role is a privileged change: confirm the exact Apple account first, assign it in CloudKit Console, and never widen WWReport's World or authenticated grants instead. In Console: Records, Public Database, Fetch Records by the account's user record name (the diagnostics print it), open the `Users` record, and tick the role under Security Roles. Console applies the change immediately.

On October 30, 2026, with the owner's confirmation, the Moderator role was assigned in **development** to the owner's account (user record `_69221177a54ae82aeb03666e638595cc`). Production has no role assignments; they must be repeated there after the schema is deployed.

`--social-live-check --moderator-check REPORT_ID` fetches and creator-queries another account's synthetic report. It prints `PASS` only when the current account can read it, and `NOT READABLE` otherwise. Run it once before assigning the role (expect `NOT READABLE`) and once after (expect `PASS`). A third account without the role should still get `NOT READABLE`.

Verified on October 30, 2026 against development: before assignment, the owner's account got `NOT READABLE` for the second account's synthetic report. After assignment it could fetch and creator-query that report (`PASS`). The second account, without the role, still got `NOT READABLE` for one of the owner's reports.

## Live social UI tests

The direct adapter checks above do not exercise the screens. `--social-live-ui` (Debug, signed devices only) enables social screens against development CloudKit for that launch only. It opens a separate on-device library named `social-live-test`, so no personal wishes are read or published, and shows a banner in Circle. Ordinary launches still honor `WishwellSocialEnabled = false`.

Four UI tests drive it across two devices with distinct Apple accounts. They skip on simulators and unless the runner receives `WISHWELL_LIVE_SOCIAL=1`. Run them one at a time, in order, with `TEST_RUNNER_WISHWELL_LIVE_SOCIAL=1` and `-only-testing:`:

1. Owner device: `testLiveSocial1OwnerPublishes`. Publishes the profile "Wishwell Owner Check" and a one-wish list "Live check list".
2. Peer device: `testLiveSocial2PeerInteractsReportsAndBlocks`. Publishes "Wishwell Peer Check", searches by full name, follows, likes, comments, reports the list, blocks (search must hide the owner) and unblocks.
3. Owner device: `testLiveSocial3OwnerSeesActivityThenRemovesEverything`. Checks follow/like/comment activity, marks it read, makes the list private and removes the public profile.
4. Peer device: `testLiveSocial4PeerSeesRemovalThenRemovesProfile`. Confirms the owner no longer appears, then removes its own profile.

Afterwards only the peer's report remains, which is intentional for moderation review. Read-marker sync across a second device on the same account, alert pushes and iPad layout are not covered by these tests.

### Results, October 30, 2026

All four tests passed on two signed iPhones with distinct Apple accounts against the actual development CloudKit service: the owner on the user's iPhone and the peer on the second iPhone. Covered through the real screens: profile publishing, list publishing, full-name search, follow, like, comment, reporting a list, blocking (search hides the person) and unblocking, follow/like/comment notifications on the owner's device, marking them read, making the list private, and removing both public profiles.

Running them found and fixed three problems:

- The report form's Submit button could sit under the keyboard; Submit is now in the navigation bar.
- Like could be tapped before the thread loaded and act on placeholder state, removing an existing like. Like is now disabled until loaded and exposes Liked / Not liked to accessibility.
- Test-side: tab switching while search was active, and reruns that toggled existing follows/likes.

Leftovers: the peer account authored three "Live UI check" reports (test 2 ran four times; one run didn't submit because of the keyboard issue). Reports have no parent, so profile removal doesn't delete them. The peer device's isolated test library still holds nothing of note, and the owner's isolated library holds the now-private "Live check list"; neither is the personal library.

Still unverified: Moderator access, read markers syncing to a second device on the same account, iPad social layout on a device, and behavior with real (non-synthetic) content volume.

### Fixture dry run, October 30, 2026

`--cleanup-fixtures` without `--confirm-delete` listed 16 synthetic records on the user's account and 3 on the peer account (follow, report, profile), all with the `wishwell-check-` prefix. After the Moderator check, `--confirm-delete` removed all of them: 3 on the peer account in one pass, and 16 on the owner's account in two passes. The first pass stopped on a CloudKit "Internal server error" after 7 deletions, and a rerun removed and confirmed the remaining 9. No `wishwell-check-` records remain for either account. The three "Live UI check" reports from the UI tests remain intentionally as sample moderation entries.

## Read markers across devices

`--social-live-cloud` (Debug, signed devices) turns on live social for one launch while using the personal iCloud library, so private read markers can sync. It publishes nothing from the library. The five `testLiveReadSync…` UI tests use it: the owner publishes a profile on the iPhone, the peer follows it, the iPhone marks the notification read, and an iPad on the same Apple account then shows that notification as read. The iPad removes the owner profile and the peer removes its own.

All five passed on October 30, 2026 (owner iPhone, owner iPad, peer iPhone). The iPad showed the read marker within about 40 seconds, and the Circle and Notifications screens worked in the iPad split layout.

Before production: the development schema only gained `CD_SocialReadState` when the first read marker synced. `CD_HiddenPerson` and `CD_LocalProfile` may still be missing. Development creates missing types on first save, but production does not, so check a fresh development export for every SwiftData model before deploying.

## Private schema completeness

On October 30, 2026 the development schema had `CD_Wish`, `CD_WishList` and `CD_SocialReadState`, but no `CD_HiddenPerson` or `CD_LocalProfile`. `CD_WishList` lacked `CD_publicRecordName` and `CD_legacyID`, and `CD_Wish` lacked `CD_legacyID`. Development adds types and fields only when a device first saves a value, and production never does, so a production deploy now would break syncing for those models.

`--social-live-check --initialize-cloudkit-schema` (Debug, signed device) runs `initializeCloudKitSchema()` against a throwaway store, which creates every type and field without opening the personal library. It runs off the main thread; on the main thread it waited on CloudKit replies that never arrived and timed out after 30 seconds.

Schema setup works by saving one `CD_FAKE_…` placeholder record per type into the private sync zone and deleting them afterwards. A run that fails part way can leave them behind, where the app would sync them in as a stray list and wish. The setup now always removes any record whose name starts with `CD_FAKE_` when it finishes, and `--social-live-check --remove-schema-placeholders` does only that cleanup.

Result on October 30, 2026: the development schema now has `CD_HiddenPerson` and `CD_LocalProfile`, `CD_WishList` has `CD_publicRecordName` and `CD_legacyID`, and `CD_Wish` has `CD_legacyID` (checked in CloudKit Console). A timed-out earlier attempt had left five placeholders on the owner's account; they were removed, and a final clean run completed and left none. Run the setup again whenever a SwiftData model gains a type or field, before deploying to production.
