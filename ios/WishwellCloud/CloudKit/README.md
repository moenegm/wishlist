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

The activity bell refreshes on foreground and pull-to-refresh. There are no alert pushes or delivery guarantees while the app is closed. Public-copy updates run while the app is open; private changes saved offline remain local/queued for private sync until connectivity returns. Republishing public copies waits for the app to run again. Activity is derived from current public records and shows the latest 100 entries, so deleted/unpublished activity disappears. Queries honor CloudKit cursors and fail explicitly at 2,000 results rather than silently returning incorrect totals; scale work will need UI pagination and server-side query batching. Blocked people are hidden on the user's devices; a public record remains publicly readable.

The two-account in-memory tests cover the domain's rules, not Apple's live permission enforcement. The debug-only `--social-preview` launch argument provides synthetic people and a wishlist for simulator UI testing. This preview uses an on-device library and an in-memory social database, shows a preview banner, never contacts the public CloudKit database, and is unavailable in Release builds.
