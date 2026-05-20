// src/auth/user.model.ts — Canonical User and Session models (REQ-AUTH-006)
//
// The User type is the single source of truth for user identity across
// all components. Import User from here, never redefine.
//
// The PublicUser type excludes passwordHash for safe serialization.
// Use toPublicUser() to create serializable views.

/**
 * Canonical User model.
 *
 * @field id — UUID v4 string
 * @field email — unique email address
 * @field passwordHash — bcrypt/argon2id hash; never serialised
 * @field createdAt — ISO-8601 timestamp
 * @field updatedAt — ISO-8601 timestamp
 */
export interface User {
  id: string;
  email: string;
  passwordHash: string;
  createdAt: string;
  updatedAt: string;
}

/**
 * Public-safe User payload — excludes passwordHash.
 * All field names are camelCase and JSON-serialisable.
 */
export type PublicUser = Omit<User, "passwordHash">;

/**
 * Create a PublicUser view from a User.
 * Safe to send over the wire or include in response bodies.
 */
export function toPublicUser(user: User): PublicUser {
  const { passwordHash: _, ...publicUser } = user;
  return publicUser;
}

/**
 * Session model for authenticated requests.
 *
 * @field token — cryptographically random bearer token
 * @field expiresAt — session expiry timestamp
 */
export interface Session {
  token: string;
  expiresAt: Date;
}