# Project State

## Infrastructure Facts

- AuthDb interface extended in S1.3: added `findSessionByToken(token)`, `deleteSession(token)`, and `findUserById(id)` methods. Production implementation wraps Prisma Session and User queries.
- Session model extracted from `user.model.ts` to dedicated `session.model.ts` with fields: id, userId, token, expiresAt, createdAt.
- Login anti-enumeration: unknown-email path uses dummy bcrypt.compareSync to maintain constant-ish timing vs wrong-password path.

## Known Issues

<!-- Track known issues or limitations that affect development. -->

## Deferred Items

<!-- Items identified during development that are out of scope but should not be forgotten. -->
