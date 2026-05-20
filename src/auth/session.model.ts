// src/auth/session.model.ts — Canonical Session model (REQ-AUTH-002, REQ-AUTH-003)
//
// Full Session type for authenticated requests. Created during login
// (REQ-AUTH-002) and consumed by validateSession and logout (REQ-AUTH-003).
//
// Fields match the Prisma Session model in prisma/schema.prisma with camelCase
// naming convention for TypeScript/JavaScript compatibility.

/**
 * Session model for authenticated requests.
 *
 * @field id — UUID v4 string (primary key)
 * @field userId — UUID v4 string, foreign key to User
 * @field token — cryptographically random bearer token (unique)
 * @field expiresAt — session expiry timestamp
 * @field createdAt — ISO-8601 timestamp
 */
export interface Session {
  id: string;
  userId: string;
  token: string;
  expiresAt: Date;
  createdAt: string;
}
