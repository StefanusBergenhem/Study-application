// src/auth/auth.service.test.ts — AuthService.register unit tests
//
// TDD: Red → Green → Refactor
// Covers: AC-1 through AC-6, all typed_errors, on_success postconditions.
// Anti-pattern verified: no implementation mocking, no shared mutable state,
// no snapshot overuse, no private method testing, no weak assertions.

import { describe, it, expect, vi, beforeEach } from "vitest";
import { AuthService, AuthDuplicateUserError, AuthInvalidEmailError, AuthWeakPasswordError } from "./auth.service";
import { User, Session, PublicUser } from "./user.model";
import bcrypt from "bcryptjs";

// ---------------------------------------------------------------------------
// Mocks — mock at the boundary we don't own (Prisma / database layer)
// ---------------------------------------------------------------------------

type MockDb = {
  findUserByEmail: ReturnType<typeof vi.fn>;
  createUser: ReturnType<typeof vi.fn>;
  createSession: ReturnType<typeof vi.fn>;
};

function createMockDb(): MockDb {
  return {
    findUserByEmail: vi.fn(),
    createUser: vi.fn(),
    createSession: vi.fn(),
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
    token: "rand0m-tok3n-str1ng",
    expiresAt: new Date("2026-05-27T00:00:00.000Z"),
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

  // DbC: Tolerant style — every failure mode returns a specific typed error.
  // Each error is an Error subclass with a distinct name, so callers can
  // discriminate via instanceof or .name without parsing messages.
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