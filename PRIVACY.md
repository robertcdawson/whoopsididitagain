---
title: Privacy Policy
permalink: /privacy/
---

# Privacy Policy

**Application:** whoopsididitagain
**Operator:** Robert Dawson (an individual, not a company)
**Contact:** manatees@gmail.com
**Effective date:** August 8, 2026
**Last updated:** August 8, 2026

## 1. Summary

whoopsididitagain ("the App") is a personal, single-user hobby project. It is
built and operated by one individual, for that same individual's own use with
their own WHOOP account. It is not a commercial product, it is not offered to
the public, and it does not have customers.

The App accesses data from the [WHOOP API](https://developer.whoop.com/) using
WHOOP's OAuth 2.0 authorization flow, and only with the explicit consent of the
WHOOP member who authorizes it.

The short version: your data is used only to make the App work for you, it is
not sold, it is not shared with anyone, and you can revoke access and have it
deleted at any time.

## 2. Who this policy covers

This policy applies to any WHOOP member who authorizes the App. In normal
operation that is exactly one person: the operator named above. If you are
reading this because you are considering authorizing the App, this policy
describes what happens to your data if you do.

## 3. What data the App accesses

When you authorize the App, WHOOP asks you to approve a specific set of
permissions ("scopes"). The App may request some or all of the following:

| Scope | Data it grants access to |
| --- | --- |
| `read:profile` | Basic profile information: first name, last name, WHOOP user ID, and the email address on your WHOOP account |
| `read:body_measurement` | Height, weight, and maximum heart rate |
| `read:cycles` | Physiological cycles, including day strain and average heart rate |
| `read:recovery` | Recovery scores, resting heart rate, heart rate variability, and related recovery metrics |
| `read:sleep` | Sleep sessions, including duration, stages, sleep performance, and respiratory rate |
| `read:workout` | Workout activities, including sport, duration, strain, heart rate zones, and calories |
| `offline` | A refresh token, so the App can continue syncing your data without prompting you to log in each time |

The App requests **read-only** access to WHOOP data. It does not create,
modify, or delete anything in your WHOOP account.

The consent screen shown by WHOOP at authorization time is authoritative. You
can decline it, and you can grant access and later revoke it.

## 4. What the App does *not* collect

The App does not collect, and has no mechanism to collect:

- Your WHOOP password or WHOOP login credentials — authentication happens
  entirely on WHOOP's own systems via OAuth, and the App never sees them.
- Payment or financial information. The App is free and has no billing.
- Location data, contacts, photos, microphone, or camera data.
- Advertising identifiers or cross-site tracking data.
- Data about anyone who has not personally authorized the App.

There are no third-party analytics, advertising, tracking pixels, session
recorders, or telemetry SDKs in the App.

## 5. How the data is used

WHOOP data is used for one purpose only: to provide the App's own features to
the person whose data it is — for example, displaying, charting, summarizing,
or locally analyzing that person's own WHOOP metrics.

The data is **not** used for:

- Advertising or marketing of any kind.
- Building profiles about you for anyone else's benefit.
- Training machine learning models offered to third parties.
- Any purpose you have not authorized.

## 6. Where data is stored, and for how long

- **Access and refresh tokens** are stored so the App can talk to the WHOOP API
  on your behalf. They are kept out of version control and are never committed
  to this repository.
- **WHOOP data** may be cached or stored locally so the App can display history
  without re-fetching it on every use.

Storage is limited to infrastructure controlled by the operator — a personal
machine and, where applicable, a private personal deployment. Data is retained
only as long as it is useful to the operator, and is deleted on request or when
the App is retired.

## 7. Sharing and disclosure

Data obtained from WHOOP is **not sold, rented, traded, or shared with any
third party**. There are no advertisers, no data brokers, no partners, and no
affiliates, because there is no business here.

The only exception is the narrow one every operator is subject to: disclosure
required by valid legal process, or disclosure necessary to protect someone's
safety or legal rights. The operator has never received such a request.

The App does rely on WHOOP itself as its data source. Your relationship with
WHOOP is governed by [WHOOP's own privacy policy](https://www.whoop.com/privacy/),
which is not affected by this document.

## 8. Your choices and rights

You are in control at all times:

- **Revoke access.** You can disconnect the App at any time from your WHOOP
  account settings, or via the WHOOP app. Revocation immediately invalidates the
  App's tokens and stops all further data access.
- **Request deletion.** Email the contact address above and any stored copy of
  your WHOOP data and tokens will be deleted.
- **Request a copy.** Email the contact address above to ask what data is
  currently stored.
- **Ask questions.** Same address. It is one person; they will read it.

Depending on where you live, you may have additional statutory rights (for
example under GDPR or the CCPA). The operator will honor valid requests under
those laws to the extent they apply.

## 9. Security

Reasonable measures are taken to protect the data, appropriate to a personal
project of this size:

- Credentials and tokens are held in environment variables or local
  configuration excluded from version control, never hard-coded in source.
- All communication with the WHOOP API uses HTTPS.
- Access is limited to the operator's own devices and accounts.

No system is perfectly secure. Because the App has exactly one user and stores
data on personal infrastructure rather than a public server, the exposure
surface is deliberately small — but no absolute guarantee can be made.

## 10. Children

The App is not directed at children and is not intended for use by anyone under
16. No data is knowingly collected from children.

## 11. International users

The operator is based in the United States, and any stored data resides there.

## 12. Changes to this policy

If this policy changes, the updated version will be published in this
repository and the "Last updated" date above will be revised. Because the App
has a single user, material changes will simply be known to that user.

## 13. Relationship to WHOOP

whoopsididitagain is an independent personal project. It is **not** created,
endorsed, sponsored, or supported by WHOOP, Inc. "WHOOP" is a trademark of its
respective owner. Use of the WHOOP API is subject to the
[WHOOP API Terms of Use](https://developer.whoop.com/api-terms-of-use/).

## 14. Contact

Questions, deletion requests, or concerns:

**manatees@gmail.com**
