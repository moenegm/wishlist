# Mobile API v1

This branch adds `/api/v1` alongside the HTML website. Both use existing Active Record models and the same PostgreSQL/Active Storage services. No Supabase credentials are distributed to clients.

## Enabling

Development/test: enabled. Production: returns 404 unless `MOBILE_API_ENABLED=true`.

Apply `20261016000003_create_mobile_sessions` before enabling. The API branch is separate from the approved website enhancements. Enabling in production is a deployment decision after review, not an effect of building the app locally.

## Sessions

`POST session` accepts `email`, `password`; `POST register` also accepts `first_name`, `last_name`, `password_confirmation`. Both return `{token, expires_at, user}`. Registration uses the existing Devise model and password policy. This is not Supabase Auth.

Authenticated calls require `Authorization: Bearer <token>`; browser cookies are not API credentials. Tokens contain 48 random bytes, only SHA-256 digests are stored server-side, and sessions expire after 30 days. `DELETE session` revokes the current session. Changing the user's password invalidates old sessions via a password-hash fingerprint. Native clients store the bearer token in device-only, unlocked Keychain; passwords are not persisted. Refresh-token rotation is not implemented: expiry requires sign-in again.

Sign-in/register/recovery are throttled to 10 requests/minute/IP using a per-process memory store. Before scaling to multiple processes/instances, use a shared rate-limit store or gateway. Add production abuse monitoring. HTTPS is forced by the Rails production config.

`POST password_recovery` accepts email and returns a generic response regardless of account existence. Production email delivery still requires hosting configuration and verification.

## Endpoints

- `GET/PATCH me`: own account/name profile; `POST me/avatar`: multipart photo, 5 MB limit, MIME sniffing. Photos pass through Rails to Active Storage.
- `PATCH me/credentials`: current password required to change email/password; returns a replacement session and revokes other mobile sessions.
- `DELETE me`: current password required; deletes the existing user and dependent app records.
- `GET/POST wlists`, `GET/PATCH/DELETE wlists/:id`: wishlist CRUD. Writes use `{wlist: {title, wl_category, is_public}}`.
- `GET wlists?feed=following`: followed members' public lists.
- `GET/POST/PATCH/DELETE wishes[/ :id]`: wish CRUD. Writes use `{wish: {title, wlists_id, location, price, location_2, price_2, location_3, price_3, fulfilled}}`. Ownership is always derived from the session; list assignments are scoped to the owner.
- `GET people?q=...`, `GET people?group=followers|following`, `GET people/:id`.
- `POST/DELETE people/:id/follow`: retry-safe follow/unfollow.
- `POST/DELETE like`: `{target_type: "Wish"|"Wlist", target_id}`. Retry-safe state setting.
- `GET comments?target_type=...&target_id=...`, `POST comments` with target and `body`, `DELETE comments/:id` for the author.
- `GET notifications`: `{unread_count, notifications}`; no read side effects.
- `PATCH notifications/read`: `{ids: [...]}`; at most 100 IDs per call, scoped to recipient.

Collection endpoints use 40-item pages and `page=1` (default), `page=2`, etc. Wishlist detail currently includes all wishes in that list; paginate that nested collection before supporting very large lists. API names retain existing `wlist`/`wlists_id` backend conventions. The app maps JSON snake_case to Swift camelCase. Decimal prices may serialize as strings; clients must preserve decimal precision.

400 missing parameters; 401 missing/expired/revoked token; 404 inaccessible/missing content; 422 validation error; 429 throttled. Errors are `{error: "..."}` except framework-generated throttling responses. Never serialize complete User records.

## Privacy and social parity

All API content requires authentication. HTML public sharing remains anonymously accessible. Private lists/wishes are owner-only; following never grants private access. Names/photos and public lists are discoverable by signed-in members. Only owners edit/delete content; only authors delete their comments. Nonempty wishlist deletion is blocked.

Web and API follows/likes/comments use shared transactional `SocialActions`. New public wish notifications use the same shared fanout method. No self-notifications; no notifications for fulfillment or editing an existing wish. Notifications recheck current target visibility and redact inaccessible/deleted content, including notifications created before a list became private. The web notification page marks only its displayed 100 rows read; mobile marks explicit IDs. Existing browser CSRF protection remains intact; API controllers use bearer authentication and do not inherit cookie sessions.

## Validation

Use a dedicated local test database; never set the test URL to production:

```sh
RAILS_ENV=test DATABASE_URL=postgresql://localhost/wishwell_test bin/rails db:prepare
RAILS_ENV=test DATABASE_URL=postgresql://localhost/wishwell_test PARALLEL_WORKERS=1 \
  bin/rails test test/controllers/mobile_api_test.rb \
  test/controllers/wish_options_test.rb test/controllers/wish_fulfillment_test.rb
```

The original scaffold tests/fixtures predate current account/visibility rules and are not a passing full-suite baseline. They are not silently disabled or represented as passing.
