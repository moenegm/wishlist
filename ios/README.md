# Wishwell for iPhone and iPad

Native SwiftUI app, iOS/iPadOS 17+. Open `Wishwell/Wishwell.xcodeproj` and select the shared **Wishwell** scheme. The app and Rails backend intentionally share this repository.

## Local development

1. Use Ruby 3.4.11 and install the Rails bundle from the repository root.
2. Point `DATABASE_URL` at a **local development database**, run `bin/rails db:prepare`, and run `bin/rails server` on port 3000.
3. Open the Xcode project and run on an iPhone or iPad simulator. Debug defaults to `http://localhost:3000`; set the scheme environment variable `WISHWELL_API_URL` to override it. A physical device needs a reachable local server address, not the device's own localhost.
4. Register a local account or use an existing local development account. Production accounts are not copied into local development.

Keep simulator signing enabled (the normal Xcode default). An unsigned simulator build cannot reliably use Keychain. Release defaults to `https://wishwell-22rh.onrender.com` over HTTPS and ignores debug URL overrides.

For local command-line builds:

```sh
xcodebuild -project ios/Wishwell/Wishwell.xcodeproj -scheme Wishwell \
  -sdk iphonesimulator -configuration Debug \
  -derivedDataPath /tmp/wishwell-derived CODE_SIGN_IDENTITY=- build
```

## Included

- Adaptive iPhone tabs and iPad sidebar; native SwiftUI forms and navigation.
- Existing Devise account sign-in, registration, password recovery request, Keychain session persistence, and sign-out.
- Private/public wishlists, wish editing/moving, up to three store/link and price alternatives, fulfillment and deletion.
- Name search, profiles, following/followers, followed members' shared lists.
- Likes/unlikes, comments, deletion of your own comments.
- Notifications, unread counts, explicit marking of displayed notifications as read.
- Profile name editing, photo upload, email/password editing with current-password confirmation, account deletion with password confirmation.
- Pagination for lists, people, comments, and notifications; foreground and pull-to-refresh updates.

Prices follow the website's existing USD display; this does not introduce currencies. Public sharing uses the existing website links. Universal Links, push notifications, offline mutation queues, Android, and a share extension are deferred.

## Before release

The API is gated off in production unless `MOBILE_API_ENABLED=true`. Do not point a release at production expecting it to work before the API branch is reviewed, migrated, and enabled. Verify production recovery email delivery. Choose the final bundle identifier and Apple signing team in Xcode before device/TestFlight builds. This project has no account credentials or signing team checked in.

Public social content needs reporting/blocking and moderation arrangements before App Store submission. Add a privacy policy, support URL, App Store privacy answers, accessibility/device QA, and production monitoring. Account deletion is implemented, but deleting storage/backups is subject to the hosting retention policy and should be documented.

## Repeatable simulator QA

Create disposable preview data in a **local development database**:

```sh
DATABASE_URL=postgresql://localhost/wishwell_development bin/rails runner ios/seed_preview.rb
```

Run local Rails on port 3000. The `WishwellUITests` target signs in as `ios-qa@example.test` with the disposable password defined in the preview seed. It creates a new three-option wish, fulfills it, and verifies Keychain restoration after relaunch. Each run adds a local QA wish; it never logs into production. Use `xcodebuild test` with an available simulator destination or Product → Test in Xcode. Debug `--ui-testing` ignores an existing token for a local host so the sign-in flow is exercised; it does not bypass authentication.

## Installing a development build on a physical iPad/iPhone

Connect and trust the device, enable Developer Mode, and use your Apple Development team in Xcode. For a build that runs directly from the Home Screen, set the Debug build setting `WISHWELL_DEVELOPMENT_API_URL` to a reachable address such as `http://YOUR-MAC.local:3000`. This is embedded in the preview build; it does not require launch environment variables from Xcode. Release builds ignore this development override.

Run local Rails with `RAILS_DEVELOPMENT_HOSTS=YOUR-MAC.local` and bind to a LAN interface, e.g. `bin/rails server -b 0.0.0.0 -p 3000`, using only your local development/preview database. Keep the Mac awake and the device on the same network. Allow local-network access when iOS requests it. The app includes a local-network usage description and allows local networking through ATS; it does not disable HTTPS requirements for general internet requests.

Development builds use the local accounts/database. They are not connected to production merely because they are installed on a physical device. A TestFlight/production build requires the production API rollout described above.
