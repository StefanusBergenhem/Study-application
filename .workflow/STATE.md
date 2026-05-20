# Project State

## Infrastructure Facts

- AuthDb interface extended in S1.3: added `findSessionByToken(token)`, `deleteSession(token)`, and `findUserById(id)` methods. Production implementation wraps Prisma Session and User queries.
- Session model extracted from `user.model.ts` to dedicated `session.model.ts` with fields: id, userId, token, expiresAt, createdAt.
- Login anti-enumeration: unknown-email path uses dummy bcrypt.compareSync to maintain constant-ish timing vs wrong-password path.
- Register and Login forms (S1.4) created as 'use client' components in src/ui/. Forms use callback-based dependency injection (onRegister/onLogin props) rather than importing AuthService directly — ui component depends on auth only through its declared interface.
- Password visibility toggle implemented as text toggle ("Show"/"Hide") rather than icon; passes all AC-6 tests.

## Known Issues

<!-- Track known issues or limitations that affect development. -->

## Deferred Items

<!-- Items identified during development that are out of scope but should not be forgotten. -->
- E2E tests for auth forms (5 scenarios: register success, duplicate email, login success, login failure, viewport responsiveness) deferred — e2e tooling not configured (commands.test_e2e empty in config.yaml). Set up Playwright/Cypress in a future sprint.
- Server Action wiring: current forms accept callbacks; production Server Action integration (calling AuthService via 'use server') deferred to page-routing task.
- Styling beyond basic functional layout deferred per out_of_scope — visual design is a separate concern.
