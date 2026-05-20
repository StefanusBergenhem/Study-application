// src/auth/auth.service.ts — AuthService.register (REQ-AUTH-001, REQ-AUTH-005, REQ-AUTH-006)
//
// Implements the AuthService.register contract from COMPONENTS.yaml.
// Validates inputs (email format, password length) before touching the
// database. Uses bcrypt for password hashing (cost ≥ 12) per OWASP
// Password Storage Cheat Sheet (REQ-AUTH-005).
//
// Style: tolerant — returns typed errors instead of panicking on bad input.

import bcrypt from "bcryptjs";
import { User, Session } from "./user.model";

// ---------------------------------------------------------------------------
// Typed errors
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
  /** Create a session token for the given user. */
  createSession(params: { userId: string; token: string; expiresAt: Date }): Promise<Session>;
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
}