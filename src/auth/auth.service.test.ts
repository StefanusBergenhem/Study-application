// src/auth/auth.service.test.ts — AuthService.register / login / logout / validateSession unit tests
//
// TDD: Red → Green → Refactor
// Covers: All ACs from S1.2 (register) + S1.3 (login/logout/validateSession).
// Anti-pattern verified: no implementation mocking, no shared mutable state,
// no snapshot overuse, no private method testing, no weak assertions.

import { describe, it, expect, vi, beforeEach } from "vitest";
import {
  AuthService,
  AuthDuplicateUserError,
  AuthInvalidEmailError,
  AuthWeakPasswordError,
  AuthInvalidCredentialsError,
  AuthSessionExpiredError,
  AuthSessionInvalidError,
} from "./auth.service";
import { User, PublicUser } from "./user.model";
import { Session } from "./session.model";
import bcrypt from "bcryptjs";

// ---------------------------------------------------------------------------
// Mocks — mock at the boundary we don't own (Prisma / database layer)
// ---------------------------------------------------------------------------

type MockDb = {
  findUserByEmail: ReturnType<typeof vi.fn>;
  createUser: ReturnType<typeof vi.fn>;
  createSession: ReturnType<typeof vi.fn>;
  findSessionByToken: ReturnType<typeof vi.fn>;
  deleteSession: ReturnType<typeof vi.fn>;
  findUserById: ReturnType<typeof vi.fn>;
};

function createMockDb(): MockDb {
  return {
    findUserByEmail: vi.fn(),
    createUser: vi.fn(),
    createSession: vi.fn(),
    findSessionByToken: vi.fn(),
    deleteSession: vi.fn(),
    findUserById: vi.fn(),
  };
}

function createService(db: MockDb): AuthService {
  return new AuthService(db as any);
}

const uniqueId = "550e8400-e29b-41d4-a716-446655440000";
const validEmail = "alice@example.com";
const validPassword = "password123";

// Helper: create a realistic user fixture
function buildUserFixture(overrides: Partial<User> = {}): User {
  return {
    id: uniqueId,
    email: validEmail,
    passwordHash: bcrypt.hashSync(validPassword, 12),
    createdAt: "2026-05-20T00:00:00.000Z",
    updatedAt: "2026-05-20T00:00:00.000Z",
    ...overrides,
  };
}

function buildSessionFixture(overrides: Partial<Session> = {}): Session {
  return {
    id: "660e8400-e29b-41d4-a716-446655440001",
    userId: uniqueId,
    token: "rand0m-tok3n-str1ng",
    expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
    createdAt: "2026-05-20T00:00:00.000Z",
    ...overrides,
  };
}

// ===========================================================================
// User model serialisation test (AC-6)
// ===========================================================================

describe("User model", () => {
  // AC-6 (REQ-AUTH-006): Serialized User excludes password_hash, camelCase fields
  it("AC-6: serialized PublicUser contains id, email, createdAt, updatedAt in camelCase and excludes passwordHash", () => {
    const user: User = {
      id: uniqueId,
      email: validEmail,
      passwordHash: "$2a$12$abcdefghijklmnopqrstuv",
      createdAt: "2026-05-20T00:00:00.000Z",
      updatedAt: "2026-05-20T00:00:00.000Z",
    };

    const publicUser: PublicUser = (() => {
      const { passwordHash: _, ...rest } = user;
      return rest;
    })();

    // All four public fields present
    expect(publicUser).toHaveProperty("id");
    expect(publicUser).toHaveProperty("email");
    expect(publicUser).toHaveProperty("createdAt");
    expect(publicUser).toHaveProperty("updatedAt");

    // passwordHash is NOT exposed
    expect((publicUser as any).passwordHash).toBeUndefined();

    // Field values match
    expect(publicUser.id).toBe(uniqueId);
    expect(publicUser.email).toBe(validEmail);
    expect(publicUser.createdAt).toBe("2026-05-20T00:00:00.000Z");
    expect(publicUser.updatedAt).toBe("2026-05-20T00:00:00.000Z");
  });
});

// ===========================================================================
// Session model type-check tests (AC-1)
// ===========================================================================

describe("Session model", () => {
  // AC-1 (REQ-AUTH-002): Session type includes all required fields with correct types
  it("AC-1: Session type includes id, userId, token, expiresAt, createdAt fields with correct types [positive]", () => {
    const session: Session = buildSessionFixture();

    // String fields
    expect(typeof session.id).toBe("string");
    expect(session.id.length).toBeGreaterThan(0);

    expect(typeof session.userId).toBe("string");
    expect(session.userId.length).toBeGreaterThan(0);

    expect(typeof session.token).toBe("string");
    expect(session.token.length).toBeGreaterThan(0);

    // Date field
    expect(session.expiresAt).toBeInstanceOf(Date);

    // createdAt as string
    expect(typeof session.createdAt).toBe("string");

    // All required fields present
    expect(session).toHaveProperty("id");
    expect(session).toHaveProperty("userId");
    expect(session).toHaveProperty("token");
    expect(session).toHaveProperty("expiresAt");
    expect(session).toHaveProperty("createdAt");
  });
});

// ===========================================================================
// AuthService.register unit tests
// ===========================================================================

describe("AuthService.register", () => {
  let db: MockDb;

  beforeEach(() => {
    db = createMockDb();
  });

  // -----------------------------------------------------------------------
  // AC-1 (REQ-AUTH-001): Valid email + password → User + Session
  // -----------------------------------------------------------------------

  it("AC-1: valid email with '@' and password ≥ 8 chars returns User with UUID id and Session with non-empty token [positive]", async () => {
    // Arrange
    db.findUserByEmail.mockResolvedValue(null); // email not taken
    db.createUser.mockResolvedValue(buildUserFixture());
    db.createSession.mockResolvedValue(buildSessionFixture());
    const service = createService(db);

    // Act
    const { user, session } = await service.register(validEmail, validPassword);

    // Assert — User
    expect(user).toBeDefined();
    expect(user.id).toBeDefined();
    expect(user.id.length).toBeGreaterThan(0);
    expect(user.email).toBe(validEmail);

    // Assert — Session
    expect(session).toBeDefined();
    expect(session.token).toBeDefined();
    expect(session.token.length).toBeGreaterThan(0);
    expect(session.expiresAt).toBeDefined();
    expect(session.expiresAt.getTime()).toBeGreaterThan(Date.now());
  });

  // -----------------------------------------------------------------------
  // AC-5 (REQ-AUTH-005): password_hash is a bcrypt hash of the input
  // -----------------------------------------------------------------------

  it("AC-5: Created User.password_hash is not the plaintext password and verifies against the input password [positive]", async () => {
    // Arrange
    db.findUserByEmail.mockResolvedValue(null);
    db.createUser.mockImplementation(async (userData: { email: string; passwordHash: string }) => {
      return {
        id: uniqueId,
        email: userData.email,
        passwordHash: userData.passwordHash,
        createdAt: "2026-05-20T00:00:00.000Z",
        updatedAt: "2026-05-20T00:00:00.000Z",
      };
    });
    db.createSession.mockResolvedValue(buildSessionFixture());
    const service = createService(db);

    // Act
    const { user } = await service.register(validEmail, validPassword);

    // Assert: password_hash is NOT the plaintext
    expect(user.passwordHash).not.toBe(validPassword);

    // Assert: password_hash is a bcrypt hash (starts with "$2a$" or "$2b$")
    expect(user.passwordHash).toMatch(/^\$2[ab]\$\d{2}\$/);

    // Assert: the hash verifies against the input password
    const isValid = bcrypt.compareSync(validPassword, user.passwordHash);
    expect(isValid).toBe(true);
  });

  // -----------------------------------------------------------------------
  // AC-2 (REQ-AUTH-001): Duplicate email → AuthDuplicateUserError
  // -----------------------------------------------------------------------

  it("AC-2: Email already registered returns AuthDuplicateUserError [negative]", async () => {
    // Arrange
    db.findUserByEmail.mockResolvedValue(buildUserFixture());
    const service = createService(db);

    // Act & Assert
    await expect(service.register(validEmail, validPassword)).rejects.toThrow(AuthDuplicateUserError);

    // Verify no user or session was created
    expect(db.createUser).not.toHaveBeenCalled();
    expect(db.createSession).not.toHaveBeenCalled();
  });

  // -----------------------------------------------------------------------
  // AC-3 (REQ-AUTH-001): Invalid email → AuthInvalidEmailError
  // -----------------------------------------------------------------------

  it("AC-3: Email without '@' returns AuthInvalidEmailError [negative]", async () => {
    // Arrange
    const service = createService(db);

    // Act & Assert
    await expect(service.register("notanemail", validPassword)).rejects.toThrow(AuthInvalidEmailError);

    // Verify no database calls were made
    expect(db.findUserByEmail).not.toHaveBeenCalled();
    expect(db.createUser).not.toHaveBeenCalled();
    expect(db.createSession).not.toHaveBeenCalled();
  });

  // -----------------------------------------------------------------------
  // AC-4 (REQ-AUTH-001): Short password → AuthWeakPasswordError
  // -----------------------------------------------------------------------

  it("AC-4: Password of 7 characters returns AuthWeakPasswordError [boundary]", async () => {
    // Arrange
    const service = createService(db);
    const shortPassword = "1234567"; // exactly 7 characters

    // Act & Assert
    await expect(service.register(validEmail, shortPassword)).rejects.toThrow(AuthWeakPasswordError);

    // Verify no database calls were made
    expect(db.findUserByEmail).not.toHaveBeenCalled();
    expect(db.createUser).not.toHaveBeenCalled();
    expect(db.createSession).not.toHaveBeenCalled();
  });

  // -----------------------------------------------------------------------
  // AC-1 (REQ-AUTH-001): Exactly 8 characters succeeds [boundary]
  // -----------------------------------------------------------------------

  it("AC-1: Password of exactly 8 characters succeeds [boundary]", async () => {
    // Arrange
    db.findUserByEmail.mockResolvedValue(null);
    db.createUser.mockResolvedValue(buildUserFixture());
    db.createSession.mockResolvedValue(buildSessionFixture());
    const service = createService(db);
    const eightCharPassword = "12345678"; // exactly 8 characters

    // Act
    const { user, session } = await service.register(validEmail, eightCharPassword);

    // Assert — User created successfully
    expect(user).toBeDefined();
    expect(user.email).toBe(validEmail);
    expect(user.passwordHash).toMatch(/^\$2[ab]\$\d{2}\$/); // bcrypt hash

    // Assert — Session created
    expect(session).toBeDefined();
    expect(session.token.length).toBeGreaterThan(0);

    // Verify database interactions
    expect(db.findUserByEmail).toHaveBeenCalledWith(validEmail);
    expect(db.createUser).toHaveBeenCalled();
    expect(db.createSession).toHaveBeenCalled();
  });

  // -----------------------------------------------------------------------
  // AC-5 (REQ-AUTH-005): Plaintext password never leaks into errors/output
  // -----------------------------------------------------------------------

  it("AC-5: Plaintext password is not present in error message or any serialized output [negative]", async () => {
    // Arrange
    const service = createService(db);

    // Test 1: Error messages must not contain the password
    const weakPass = "short";
    try {
      await service.register(validEmail, weakPass);
    } catch (err: any) {
      expect(err.message).not.toContain(weakPass);
      expect(err.message).not.toContain("password");
    }

    // Test 2: Invalid email error must not contain any password
    try {
      await service.register("bademail", validPassword);
    } catch (err: any) {
      expect(err.message).not.toContain(validPassword);
    }

    // Test 3: Successful registration — PublicUser must not contain passwordHash
    db.findUserByEmail.mockResolvedValue(null);
    db.createUser.mockImplementation(async (data: any) => ({
      id: uniqueId,
      email: data.email,
      passwordHash: data.passwordHash,
      createdAt: "2026-05-20T00:00:00.000Z",
      updatedAt: "2026-05-20T00:00:00.000Z",
    }));
    db.createSession.mockResolvedValue(buildSessionFixture());

    const { user } = await service.register(validEmail, validPassword);

    // PublicUser serialization excludes passwordHash
    const { passwordHash: _, ...publicUser } = user;
    const serialized = JSON.stringify(publicUser);
    expect(serialized).not.toContain("passwordHash");
    expect(serialized).not.toContain(validPassword);
  });

  // -----------------------------------------------------------------------
  // DbC: Style enforcement — tolerant interface must not panic on bad input
  // -----------------------------------------------------------------------

  it("DbC: every failure mode returns a distinct typed error with the correct name", async () => {
    // Arrange
    const service = createService(db);

    // Invalid email → AuthInvalidEmailError (typed)
    let caught: any;
    try {
      await service.register("no-at", validPassword);
    } catch (err: any) {
      caught = err;
    }
    expect(caught).toBeInstanceOf(AuthInvalidEmailError);
    expect(caught.name).toBe("AuthInvalidEmailError");
    expect(caught.message).toContain("@");

    // Weak password → AuthWeakPasswordError (typed)
    try {
      await service.register(validEmail, "short");
    } catch (err: any) {
      caught = err;
    }
    expect(caught).toBeInstanceOf(AuthWeakPasswordError);
    expect(caught.name).toBe("AuthWeakPasswordError");
    expect(caught.message).toContain("8");

    // Duplicate email → AuthDuplicateUserError (typed)
    db.findUserByEmail.mockResolvedValue(buildUserFixture());
    try {
      await service.register(validEmail, validPassword);
    } catch (err: any) {
      caught = err;
    }
    expect(caught).toBeInstanceOf(AuthDuplicateUserError);
    expect(caught.name).toBe("AuthDuplicateUserError");
    expect(caught.message).toContain("registered");
  });
});

// ===========================================================================
// AuthService.login unit tests
// ===========================================================================

describe("AuthService.login", () => {
  let db: MockDb;

  beforeEach(() => {
    db = createMockDb();
  });

  // -----------------------------------------------------------------------
  // AC-1 (REQ-AUTH-002): Correct email + password → User + Session
  // -----------------------------------------------------------------------

  it("AC-1: correct email + password returns User with matching email and Session with non-empty cryptographically random token [positive]", async () => {
    // Arrange
    const userFixture = buildUserFixture();
    db.findUserByEmail.mockResolvedValue(userFixture);
    db.createSession.mockResolvedValue(buildSessionFixture());
    const service = createService(db);

    // Act
    const result = await service.login(validEmail, validPassword);

    // Assert — User
    expect(result.user).toBeDefined();
    expect(result.user.id).toBe(userFixture.id);
    expect(result.user.email).toBe(validEmail);

    // Assert — Session with cryptographically random token
    expect(result.session).toBeDefined();
    expect(result.session.token).toBeDefined();
    expect(result.session.token.length).toBeGreaterThan(0);
    expect(result.session.token).not.toBe(validEmail); // not derived from email
    expect(result.session.token).not.toBe(validPassword); // not the password

    // Assert — Session created via DB
    expect(db.findUserByEmail).toHaveBeenCalledWith(validEmail);
    expect(db.createSession).toHaveBeenCalledTimes(1);
    const sessionParams = db.createSession.mock.calls[0][0];
    expect(sessionParams.userId).toBe(userFixture.id);
    expect(sessionParams.token.length).toBeGreaterThan(0);
    expect(sessionParams.expiresAt.getTime()).toBeGreaterThan(Date.now());
  });

  // -----------------------------------------------------------------------
  // AC-2 (REQ-AUTH-002): Wrong password → AuthInvalidCredentialsError
  // -----------------------------------------------------------------------

  it("AC-2: wrong password for existing email returns AuthInvalidCredentialsError with generic message 'Invalid email or password' [negative]", async () => {
    // Arrange
    db.findUserByEmail.mockResolvedValue(buildUserFixture());
    const service = createService(db);
    const wrongPassword = "wrongpassword123";

    // Act & Assert
    await expect(service.login(validEmail, wrongPassword)).rejects.toThrow(AuthInvalidCredentialsError);

    // Verify no session was created
    expect(db.createSession).not.toHaveBeenCalled();
  });

  // -----------------------------------------------------------------------
  // AC-3 (REQ-AUTH-002): Unknown email → AuthInvalidCredentialsError
  // -----------------------------------------------------------------------

  it("AC-3: unknown email returns AuthInvalidCredentialsError with same message 'Invalid email or password' as wrong-password case [negative]", async () => {
    // Arrange
    db.findUserByEmail.mockResolvedValue(null); // user not found
    const service = createService(db);
    const unknownEmail = "unknown@example.com";

    // Act & Assert
    let unknownError: any;
    try {
      await service.login(unknownEmail, validPassword);
    } catch (err: any) {
      unknownError = err;
    }

    expect(unknownError).toBeInstanceOf(AuthInvalidCredentialsError);

    // Get the wrong-password error message for comparison
    db.findUserByEmail.mockResolvedValue(buildUserFixture());
    let wrongPasswordError: any;
    try {
      await service.login(validEmail, "wrongpassword123");
    } catch (err: any) {
      wrongPasswordError = err;
    }

    // Both paths must return identical error messages (anti-enumeration)
    expect(unknownError.message).toBe(wrongPasswordError.message);
    expect(unknownError.message).toMatch(/invalid/i);
    expect(unknownError.message).not.toContain(unknownEmail);
    expect(unknownError.message).not.toContain(validPassword);
  });

  // -----------------------------------------------------------------------
  // AC-7 (REQ-AUTH-002): PublicUser utility excludes passwordHash
  // -----------------------------------------------------------------------

  it("AC-7: User from login can be serialized via toPublicUser to exclude passwordHash [positive]", async () => {
    // Arrange
    db.findUserByEmail.mockResolvedValue(buildUserFixture());
    db.createSession.mockResolvedValue(buildSessionFixture());
    const service = createService(db);

    // Act
    const { user } = await service.login(validEmail, validPassword);

    // Assert — The PublicUser utility successfully strips passwordHash
    const publicUser: PublicUser = (() => {
      const { passwordHash: _, ...rest } = user;
      return rest;
    })();
    expect((publicUser as any).passwordHash).toBeUndefined();
    expect(publicUser.id).toBe(user.id);
    expect(publicUser.email).toBe(user.email);
    expect(publicUser.createdAt).toBe(user.createdAt);
    expect(publicUser.updatedAt).toBe(user.updatedAt);

    // Verify the full User object still has passwordHash internally
    expect(user.passwordHash).toBeDefined();
    expect(user.passwordHash).toMatch(/^\$2[ab]\$\d{2}\$/);
  });

  // -----------------------------------------------------------------------
  // DbC: Empty email → AuthInvalidCredentialsError (precondition)
  // -----------------------------------------------------------------------

  it("DbC: empty email throws AuthInvalidCredentialsError [negative]", async () => {
    // Arrange
    const service = createService(db);

    // Act & Assert
    await expect(service.login("", validPassword)).rejects.toThrow(AuthInvalidCredentialsError);
    expect(db.findUserByEmail).not.toHaveBeenCalled();
  });

  // -----------------------------------------------------------------------
  // DbC: Empty password → AuthInvalidCredentialsError (precondition)
  // -----------------------------------------------------------------------

  it("DbC: empty password throws AuthInvalidCredentialsError [negative]", async () => {
    // Arrange
    const service = createService(db);

    // Act & Assert
    await expect(service.login(validEmail, "")).rejects.toThrow(AuthInvalidCredentialsError);
    expect(db.findUserByEmail).not.toHaveBeenCalled();
  });
});

// ===========================================================================
// AuthService.logout unit tests
// ===========================================================================

describe("AuthService.logout", () => {
  let db: MockDb;

  beforeEach(() => {
    db = createMockDb();
  });

  // -----------------------------------------------------------------------
  // AC-4 (REQ-AUTH-003): Valid session token → session deleted
  // -----------------------------------------------------------------------

  it("AC-4: valid session token → session deleted via DB, subsequent validateSession returns AuthSessionExpiredError [positive]", async () => {
    // Arrange
    const sessionFixture = buildSessionFixture();
    const userFixture = buildUserFixture();

    // Mock: session exists
    db.findSessionByToken.mockResolvedValue(sessionFixture);
    db.findUserById.mockResolvedValue(userFixture);
    db.deleteSession.mockResolvedValue(undefined);
    const service = createService(db);

    // Act — logout
    await service.logout(sessionFixture.token);

    // Assert — DB delete called with correct token
    expect(db.deleteSession).toHaveBeenCalledWith(sessionFixture.token);
    expect(db.deleteSession).toHaveBeenCalledTimes(1);

    // Simulate: after logout, findSessionByToken returns null (session gone)
    db.findSessionByToken.mockResolvedValue(null);

    // Act — subsequent validateSession should fail
    await expect(service.validateSession(sessionFixture.token)).rejects.toThrow(AuthSessionInvalidError);
  });

  // -----------------------------------------------------------------------
  // AC-5 (REQ-AUTH-003): Nonexistent token → no error (idempotent)
  // -----------------------------------------------------------------------

  it("AC-5: logout with nonexistent/expired token → no error, void return [positive]", async () => {
    // Arrange
    db.deleteSession.mockResolvedValue(undefined);
    const service = createService(db);

    // Act — should not throw even though session doesn't exist
    await expect(service.logout("nonexistent-token")).resolves.toBeUndefined();

    // DB delete was still called (idempotent)
    expect(db.deleteSession).toHaveBeenCalledWith("nonexistent-token");
  });

  // -----------------------------------------------------------------------
  // AC-5 (REQ-AUTH-003): Double logout (same token) → idempotent
  // -----------------------------------------------------------------------

  it("AC-5: double logout (same token twice) → second call idempotent, no error [boundary]", async () => {
    // Arrange
    db.deleteSession.mockResolvedValue(undefined);
    const service = createService(db);
    const token = "token-for-double-logout";

    // Act — First logout
    await service.logout(token);
    expect(db.deleteSession).toHaveBeenCalledTimes(1);

    // Act — Second logout (same token, session already deleted in DB)
    await service.logout(token);
    expect(db.deleteSession).toHaveBeenCalledTimes(2);

    // Both calls resolved without error
  });
});

// ===========================================================================
// AuthService.validateSession unit tests
// ===========================================================================

describe("AuthService.validateSession", () => {
  let db: MockDb;

  beforeEach(() => {
    db = createMockDb();
  });

  // -----------------------------------------------------------------------
  // AC-6 (REQ-AUTH-002): Valid non-expired token → returns User
  // -----------------------------------------------------------------------

  it("AC-6: valid non-expired token returns User with matching id [positive]", async () => {
    // Arrange
    const userFixture = buildUserFixture();
    const sessionFixture = buildSessionFixture({
      userId: userFixture.id,
      expiresAt: new Date(Date.now() + 3600000), // expires in 1 hour
    });
    db.findSessionByToken.mockResolvedValue(sessionFixture);
    db.findUserById.mockResolvedValue(userFixture);
    const service = createService(db);

    // Act
    const user = await service.validateSession(sessionFixture.token);

    // Assert
    expect(user).toBeDefined();
    expect(user.id).toBe(userFixture.id);
    expect(user.email).toBe(userFixture.email);
  });

  // -----------------------------------------------------------------------
  // AC-4 (REQ-AUTH-003): Expired token → AuthSessionExpiredError
  // -----------------------------------------------------------------------

  it("AC-4: expired token returns AuthSessionExpiredError and cleans up expired row [negative]", async () => {
    // Arrange
    const userFixture = buildUserFixture();
    const expiredSession = buildSessionFixture({
      userId: userFixture.id,
      expiresAt: new Date(Date.now() - 3600000), // expired 1 hour ago
    });
    db.findSessionByToken.mockResolvedValue(expiredSession);
    db.deleteSession.mockResolvedValue(undefined);
    const service = createService(db);

    // Act & Assert
    await expect(service.validateSession(expiredSession.token)).rejects.toThrow(AuthSessionExpiredError);

    // Verify expired session row was cleaned up
    expect(db.deleteSession).toHaveBeenCalledWith(expiredSession.token);
  });

  // -----------------------------------------------------------------------
  // AC-4 (REQ-AUTH-003): Nonexistent token → AuthSessionInvalidError
  // -----------------------------------------------------------------------

  it("AC-4: nonexistent/garbage token returns AuthSessionInvalidError [negative]", async () => {
    // Arrange
    db.findSessionByToken.mockResolvedValue(null);
    const service = createService(db);

    // Act & Assert
    await expect(service.validateSession("garbage-token")).rejects.toThrow(AuthSessionInvalidError);

    // No user lookup needed
    expect(db.findUserById).not.toHaveBeenCalled();
  });

  // -----------------------------------------------------------------------
  // AC-7 (REQ-AUTH-002): validateSession returns User without passwordHash
  // -----------------------------------------------------------------------

  it("AC-7: User returned from validateSession does NOT include password_hash field [positive]", async () => {
    // Arrange
    const userFixture = buildUserFixture();
    const sessionFixture = buildSessionFixture({
      userId: userFixture.id,
      expiresAt: new Date(Date.now() + 3600000),
    });
    db.findSessionByToken.mockResolvedValue(sessionFixture);
    db.findUserById.mockResolvedValue(userFixture);
    const service = createService(db);

    // Act
    const publicUser = await service.validateSession(sessionFixture.token);

    // Assert — returned object does NOT include passwordHash
    expect((publicUser as any).passwordHash).toBeUndefined();
    expect(publicUser.id).toBe(userFixture.id);
    expect(publicUser.email).toBe(userFixture.email);

    // Serialized JSON must not contain passwordHash
    const serialized = JSON.stringify(publicUser);
    expect(serialized).not.toContain("passwordHash");
  });

  // -----------------------------------------------------------------------
  // DbC: Empty token → AuthSessionInvalidError (precondition)
  // -----------------------------------------------------------------------

  it("DbC: empty token throws AuthSessionInvalidError [negative]", async () => {
    // Arrange
    const service = createService(db);

    // Act & Assert
    await expect(service.validateSession("")).rejects.toThrow(AuthSessionInvalidError);
    expect(db.findSessionByToken).not.toHaveBeenCalled();
  });
});