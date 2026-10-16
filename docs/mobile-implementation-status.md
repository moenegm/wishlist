# Native app review handoff — 16 October 2026

## Repository and deployment

All code is in `moenegm/wishlist`. Website fulfillment and three purchase options were committed and pushed to `master` as `18fecc8`. The native app and API are on `feature/mobile-api`; they have not been merged into `master`. No manual Render deployment or production database command was run for the new API. Render may automatically deploy the approved website push; its deployment status was not independently confirmed.

## Review locally

Open `ios/Wishwell/Wishwell.xcodeproj` and run the Wishwell scheme on an iPhone or iPad simulator. Debug uses local Rails on port 3000. The current local checkout uses the isolated preview database `wishwell_preview` on PostgreSQL port 55439. It contains no imported production data.

Local preview credentials: `ios-qa@example.test` / `LocalPreview123!`. The seed is development-only and includes a local friend, Tomas Preview, for Circle browsing. The existing `preview@example.com` account also remains in the local database. Never reuse these disposable credentials for production.

## Verification

- Rails: **26 tests, 122 assertions, zero failures/errors** across mobile_api_test, wish_options_test, and wish_fulfillment_test.
- iPhone 17 Pro: native UI test passed for existing-account sign-in, three-option wish creation, fulfillment, and Keychain session restoration.
- iPad mini (A17 Pro): the same flow passed, including the adaptive sidebar and keyboard completion before adding options.
- Both Debug and Release simulator configurations compile successfully. The latest iPhone regression includes the final compact editor and adaptive color palette.
- Native-created fulfilled wishes with three options were confirmed in the same local database the website uses.
- The original scaffold suite is not a passing baseline; it has obsolete fixtures/routes. Only the named checks above are represented as passing.

The initial iPad Pro simulator had orientation and focus/tap automation issues. Testing on a fresh iPad mini isolated the input behavior; the editor was simplified into compact rows and given explicit keyboard completion. The final test uses single add-option taps after finishing price entry. Screenshots were exported from successful device tests.

## Before production/TestFlight

Review the app and API branch; verify production password-recovery email delivery and hosting reliability. Review/merge/migrate the backend and explicitly set `MOBILE_API_ENABLED=true` before attempting production mobile login. Choose the final bundle identifier and signing team, then test on physical devices and prepare TestFlight. Reporting/blocking/moderation, privacy policy/support links, App Store disclosures, accessibility and wider device/network testing remain release work. Push notifications and offline editing were deliberately deferred.

See `docs/mobile-api.md` for token lifetime, revocation, access rules, pagination, and rate-limit boundaries. There is no new database, no Supabase client SDK in the app, and no service credential in the client.
