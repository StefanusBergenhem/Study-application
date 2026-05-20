// src/auth/auth.service.ts — AuthService.register / login / logout / validateSession
//
// Implements the AuthService contracts from COMPONENTS.yaml.
// register   → REQ-AUTH-001, REQ-AUTH-005, REQ-AUTH-006
// login      → REQ-AUTH-002
// logout     → REQ-AUTH-003
// validateSession → REQ-AUTH-002, REQ-AUTH-003
//
// All methods use bcrypt for password hashing (cost ≥ 12) per OWASP
// Password Storage Cheat Sheet (REQ-AUTH-005).
//
// Style: tolerant — returns typed errors instead of panicking on bad input.

import bcrypt from "bcryptjs";
import { User, toPublicUser, PublicUser } from "./user.model";
import { Session } from "./session.model";

// ---------------------------------------------------------------------------
// Typed errors — all extend Error so callers can discriminate via instanceof
// ---------------------------------------------------------------------------

export class AuthDuplicateUserError extends Error {
  constructor() {
    super("A user with this email is already registered.");
    this.name = "AuthDuplicateUserError";
  }
}

export class AuthInvalidEmailError extends Error {
  constructor() {
    super("The email address does not contain '@'.");
    this.name = "AuthInvalidEmailError";
  }
}

export class AuthWeakPasswordError extends Error {
  constructor() {
    super("Password must be at least 8 characters long.");
    this.name = "AuthWeakPasswordError";
  }
}

export class AuthInvalidCredentialsError extends Error {
  constructor() {
    super("Invalid email or password.");
    this.name = "AuthInvalidCredentialsError";
  }
}

export class AuthSessionExpiredError extends Error {
  constructor() {
    super("Session has expired.");
    this.name = "AuthSessionExpiredError";
  }
}

export class AuthSessionInvalidError extends Error {
  constructor() {
    super("Invalid session token.");
    this.name = "AuthSessionInvalidError";
  }
}

// ---------------------------------------------------------------------------
// Database interface (injected dependency — mockable for tests)
// ---------------------------------------------------------------------------

/**
 * Data-access methods the AuthService needs from the persistence layer.
 * In production this wraps Prisma; in tests it is mocked.
 */
export interface AuthDb {
  /** Look up a user by email. Returns null when not found. */
  findUserByEmail(email: string): Promise<User | null>;
  /** Persist a new user row. Returns the created User. */
  createUser(data: { email: string; passwordHash: string }): Promise<User>;
  /** Create a session token for the given user. Returns the full Session. */
  createSession(params: { userId: string; token: string; expiresAt: Date }): Promise<Session>;
  /** Look up a session by token. Returns null when not found. */
  findSessionByToken(token: string): Promise<(Session & { userId: string }) | null>;
  /** Delete a session row by token. Idempotent — no error if not found. */
  deleteSession(token: string): Promise<void>;
  /** Look up a user by id. Returns null when not found. */
  findUserById(id: string): Promise<User | null>;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/** Bcrypt cost factor — ≥ 12 per REQ-AUTH-005 / OWASP guidance. */
const BCRYPT_COST = 12;

/** Session token expiry (7 days from creation). */
const SESSION_TTL_MS = 7 * 24 * 60 * 60 * 1000;

/** Minimum password length. */
const MIN_PASSWORD_LENGTH = 8;

// ---------------------------------------------------------------------------
// AuthService
// ---------------------------------------------------------------------------

export interface RegisterResult {
  user: User;
  session: Session;
}

export interface LoginResult {
  user: User;
  session: Session;
}

export class AuthService {
  constructor(private readonly db: AuthDb) {}

  /**
   * Register a new user with email and password.
   *
   * Validates input before making any database calls.
   * Returns a User (with bcrypt-hashed password) and a Session.
   *
   * @param email   — must contain '@'
   * @param password — must be ≥ 8 characters
   * @throws AuthInvalidEmailError when email has no '@'
   * @throws AuthWeakPasswordError when password is too short
   * @throws AuthDuplicateUserError when email is already registered
   */
  async register(email: string, password: string): Promise<RegisterResult> {
    // --- Pre-validation (no database calls) ---

    if (typeof email !== "string" || !email.includes("@")) {
      throw new AuthInvalidEmailError();
    }

    if (typeof password !== "string" || password.length < MIN_PASSWORD_LENGTH) {
      throw new AuthWeakPasswordError();
    }

    // --- Check uniqueness ---

    const existing = await this.db.findUserByEmail(email);
    if (existing !== null) {
      throw new AuthDuplicateUserError();
    }

    // --- Hash password ---

    const passwordHash = bcrypt.hashSync(password, BCRYPT_COST);

    // --- Persist user ---

    const user = await this.db.createUser({ email, passwordHash });

    // --- Create session ---

    const token = crypto.randomUUID();
    const expiresAt = new Date(Date.now() + SESSION_TTL_MS);

    const session = await this.db.createSession({ userId: user.id, token, expiresAt });

    return { user, session };
  }

  /**
   * Authenticate a user by email and password.
   *
   * Uses constant-time comparison to prevent timing-based user enumeration.
   * Both unknown-email and wrong-password paths produce the same error message
   * and timing profile.
   *
   * @param email   — non-empty string
   * @param password — non-empty string
   * @throws AuthInvalidCredentialsError when email is unknown or password mismatch
   */
  async login(email: string, password: string): Promise<LoginResult> {
    // --- Pre-validation ---

    if (typeof email !== "string" || email.length === 0) {
      throw new AuthInvalidCredentialsError();
    }

    if (typeof password !== "string" || password.length === 0) {
      throw new AuthInvalidCredentialsError();
    }

    // --- Look up user ---

    const user = await this.db.findUserByEmail(email);

    // Anti-enumeration: compute bcrypt verify even if user not found,
    // so that both paths take similar time.
    let passwordValid = false;
    if (user !== null) {
      passwordValid = bcrypt.compareSync(password, user.passwordHash);
    } else {
      // Hash a dummy value to maintain constant-ish timing
      bcrypt.compareSync(password, "$2a$12$00000000000000000000000000000000000000000000");
    }

    if (user === null || !passwordValid) {
      throw new AuthInvalidCredentialsError();
    }

    // --- Create session ---

    const token = crypto.randomUUID();
    const expiresAt = new Date(Date.now() + SESSION_TTL_MS);

    const session = await this.db.createSession({ userId: user.id, token, expiresAt });

    return { user, session };
  }

  /**
   * Invalidate a session token so it can no longer authenticate requests.
   *
   * Idempotent — calling with an already-expired, already-logged-out, or
   * garbage token produces no error.
   *
   * @param sessionToken — session token string
   */
  async logout(sessionToken: string): Promise<void> {
    // Idempotent delete — no error if session doesn't exist
    await this.db.deleteSession(sessionToken);
  }

  /**
   * Validate a session token and return the associated user.
   *
   * If the session token is expired, it is cleaned up (deleted) and an
   * AuthSessionExpiredError is returned. If the token is nonexistent or
   * garbage, an AuthSessionInvalidError is returned.
   *
   * @param token — session token string, non-empty
   * @throws AuthSessionExpiredError when token is valid but past expiry
   * @throws AuthSessionInvalidError when token doesn't match any active session
   */
  async validateSession(token: string): Promise<PublicUser> {
    // --- Pre-validation ---

    if (typeof token !== "string" || token.length === 0) {
      throw new AuthSessionInvalidError();
    }

    // --- Look up session ---

    const session = await this.db.findSessionByToken(token);
    if (session === null) {
      throw new AuthSessionInvalidError();
    }

    // --- Check expiry ---

    if (session.expiresAt < new Date()) {
      // Clean up expired session row
      await this.db.deleteSession(token);
      throw new AuthSessionExpiredError();
    }

    // --- Look up user ---

    const user = await this.db.findUserById(session.userId);
    if (user === null) {
      // Session references a deleted user — clean up and treat as invalid
      await this.db.deleteSession(token);
      throw new AuthSessionInvalidError();
    }

    return toPublicUser(user);
  }
}