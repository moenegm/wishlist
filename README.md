# Wishwell

Live app: [https://wishwell-22rh.onrender.com](https://wishwell-22rh.onrender.com)

Wishwell is a small, private-by-default place to keep wishlists and the things you are hoping for. Create an account, make a list, and save a wish with its price and where to find it. You can share individual lists on your public profile and follow people to keep their shared lists close for birthdays, holidays, and other occasions.

## Sharing

Wishlists are private by default. A list owner can make an individual wishlist public; public lists appear on that person’s profile and can be opened without signing in. Signed-in members can search for other members by first or last name and follow them, even if they have not shared a wishlist yet. The profile’s Circle section contains followers, followed members, and search. Public lists from followed members appear in the Circle; private lists remain visible only to their owner. Individual wishes live inside a wishlist; the separate all-wishes directory has been removed. Members can like and comment on wishlists and wishes, and new follows, public wish additions, likes, and comments appear in the in-app notifications list.

## Stack

- Ruby 3.4.11
- Rails 8.1
- PostgreSQL
- Devise for accounts
- Active Storage for profile photos

## Run locally

Install Ruby 3.4.11 and PostgreSQL, then run:

```sh
bundle install
bin/rails db:prepare
bin/rails server
```

Open `http://localhost:3000`. The local Active Storage service saves uploads under `storage/`.

## Deploy for $0

The repository includes a Render Blueprint in `render.yaml`. For a small public demo:

1. Create a Supabase project in Frankfurt and copy its PostgreSQL connection string.
2. Create a private bucket for profile photos. Enable S3 access in Supabase Storage and generate S3 credentials.
3. Connect the GitHub repository to Render and create a Blueprint from `render.yaml`.
4. When Render prompts for values, provide `DATABASE_URL`, `SUPABASE_S3_ACCESS_KEY_ID`, `SUPABASE_S3_SECRET_ACCESS_KEY`, `SUPABASE_S3_REGION`, `SUPABASE_STORAGE_BUCKET`, and `SUPABASE_S3_ENDPOINT` from Supabase. Render generates `SECRET_KEY_BASE`.

The Blueprint builds assets, runs database migrations, starts Puma, and keeps uploaded photos in Supabase Storage. Keep S3 credentials in Render’s environment settings; they grant server-side access to storage.

The free setup is suited to a portfolio demo, not dependable production hosting. [Render free web services sleep after 15 minutes of inactivity](https://render.com/docs/free), and its free Postgres databases expire after 30 days. [Supabase’s free database has a 500 MB quota](https://supabase.com/docs/guides/platform/database-size), and projects may pause after a week without activity. Free plans do not include backups, so keep an export of any data you want to preserve.

## Configuration notes

Local development uses disk storage. Production defaults to disk storage too; set `ACTIVE_STORAGE_SERVICE=supabase` only after adding the Supabase S3 settings above. Database connection details are supplied through `DATABASE_URL` in production. Never commit service credentials or production secrets.

## Native iPhone and iPad app

The SwiftUI app lives in [`ios/Wishwell`](ios/Wishwell) in this same repository. Open `ios/Wishwell/Wishwell.xcodeproj` in Xcode. See [local setup and release notes](ios/README.md) and the [mobile API contract](docs/mobile-api.md). Mobile uses existing Rails accounts, PostgreSQL data, and Active Storage; it contains no Supabase service credentials.

The new API is disabled in production unless explicitly enabled with `MOBILE_API_ENABLED=true` after review and migration. Debug app builds use local Rails; release builds use the existing production host.
