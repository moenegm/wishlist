# App Store privacy answers

Answers for App Store Connect > App Privacy, based on how Wishwell works today. Recheck them if push notifications, analytics or any third-party service are added.

## Does the app collect data?

Yes, but only when someone sets up a public profile. Private wishlists in the user's own iCloud account aren't collected: we have no access to them.

## Data types

| Category | Type | Linked to user | Used for tracking | Purpose |
| --- | --- | --- | --- | --- |
| Contact Info | Name (public display name) | Yes | No | App Functionality |
| User Content | Photos (optional profile photo) | Yes | No | App Functionality |
| User Content | Other User Content (published wishlists, comments, likes, follows) | Yes | No | App Functionality |
| User Content | Customer Support (reports) | Yes | No | App Functionality |
| Identifiers | User ID (anonymous iCloud account identifier) | Yes | No | App Functionality |

Not collected: email, phone, address, location, contacts, browsing history, search history, purchases, financial info, health, diagnostics, usage data.

## Tracking

No. There are no ads, analytics or data brokers.

## Links needed before submission

- Privacy policy URL: host `privacy-policy.md` once [DATE] and [SUPPORT EMAIL] are filled in.
- Support URL: a page with the support email and how to remove a public profile.
