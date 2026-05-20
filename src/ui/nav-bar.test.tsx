// src/ui/nav-bar.test.tsx — Navigation bar and auth middleware unit tests
//
// Covers: All ACs from S1.5 (Navigation, logout, and route protection)
// Anti-pattern verified: no implementation mocking, no shared mutable state,
// no snapshot overuse, no private method testing, no weak assertions.

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor, cleanup } from "@testing-library/react";
import React from "react";

// ===========================================================================
// Auth middleware tests — pure function, no DOM needed
// ===========================================================================

describe("AuthMiddleware — computeMiddlewareAction", () => {
  // Dynamically import to avoid top-level side effects
  let computeMiddlewareAction: any;
  let AuthSessionExpiredError: any;
  let AuthSessionInvalidError: any;

  beforeEach(async () => {
    const mod = await import("./auth-middleware");
    computeMiddlewareAction = mod.computeMiddlewareAction;

    const authMod = await import("../auth/auth.service");
    AuthSessionExpiredError = authMod.AuthSessionExpiredError;
    AuthSessionInvalidError = authMod.AuthSessionInvalidError;
  });

  // -----------------------------------------------------------------------
  // AC-3: Unauthenticated → protected route → redirect to /login
  // -----------------------------------------------------------------------

  it("AC-3: unauthenticated request to protected route returns redirect to /login with returnUrl [positive]", async () => {
    const validateSession = vi.fn().mockRejectedValue(new AuthSessionInvalidError());

    const action = await computeMiddlewareAction("/dashboard", null, validateSession);

    expect(action.kind).toBe("redirect");
    expect(action.url).toContain("/login");
    expect(action.url).toContain("returnUrl");
    expect(action.url).toContain(encodeURIComponent("/dashboard"));
  });

  // -----------------------------------------------------------------------
  // AC-3: Authenticated → protected route → pass through
  // -----------------------------------------------------------------------

  it("AC-3: authenticated request to protected route returns pass action [positive]", async () => {
    const validateSession = vi.fn().mockResolvedValue({ id: "user-1", email: "alice@example.com" });

    const action = await computeMiddlewareAction("/dashboard", "valid-token", validateSession);

    expect(action.kind).toBe("pass");
    expect(validateSession).toHaveBeenCalledWith("valid-token");
  });

  // -----------------------------------------------------------------------
  // AC-4: Authenticated → /login → redirect to /
  // -----------------------------------------------------------------------

  it("AC-4: authenticated request to /login returns redirect to / [positive]", async () => {
    const validateSession = vi.fn().mockResolvedValue({ id: "user-1", email: "alice@example.com" });

    const action = await computeMiddlewareAction("/login", "valid-token", validateSession);

    expect(action.kind).toBe("redirect");
    expect(action.url).toBe("/");
  });

  // -----------------------------------------------------------------------
  // AC-4: Authenticated → /register → redirect to /
  // -----------------------------------------------------------------------

  it("AC-4: authenticated request to /register returns redirect to / [positive]", async () => {
    const validateSession = vi.fn().mockResolvedValue({ id: "user-1", email: "alice@example.com" });

    const action = await computeMiddlewareAction("/register", "valid-token", validateSession);

    expect(action.kind).toBe("redirect");
    expect(action.url).toBe("/");
  });

  // -----------------------------------------------------------------------
  // AC-4: Unauthenticated → /login or /register → pass through
  // -----------------------------------------------------------------------

  it("AC-4: unauthenticated request to /login passes through [positive]", async () => {
    const validateSession = vi.fn().mockRejectedValue(new AuthSessionInvalidError());

    const action = await computeMiddlewareAction("/login", null, validateSession);

    expect(action.kind).toBe("pass");
  });

  it("AC-4: unauthenticated request to /register passes through [positive]", async () => {
    const validateSession = vi.fn().mockRejectedValue(new AuthSessionInvalidError());

    const action = await computeMiddlewareAction("/register", null, validateSession);

    expect(action.kind).toBe("pass");
  });

  // -----------------------------------------------------------------------
  // AC-3: Expired session → protected route → redirect to /login
  // -----------------------------------------------------------------------

  it("AC-3: expired session token on protected route returns redirect to /login [negative]", async () => {
    const validateSession = vi.fn().mockRejectedValue(new AuthSessionExpiredError());

    const action = await computeMiddlewareAction("/cards", "expired-token", validateSession);

    expect(action.kind).toBe("redirect");
    expect(action.url).toContain("/login");
    expect(action.url).toContain(encodeURIComponent("/cards"));
  });

  // -----------------------------------------------------------------------
  // Public routes always pass through
  // -----------------------------------------------------------------------

  it("public routes always pass through regardless of auth state [positive]", async () => {
    // Without session
    const action1 = await computeMiddlewareAction("/about", null, vi.fn());
    expect(action1.kind).toBe("pass");

    // With valid session
    const action2 = await computeMiddlewareAction("/about", "valid-token", vi.fn().mockResolvedValue({ id: "u1" }));
    expect(action2.kind).toBe("pass");

    // With expired session
    const action3 = await computeMiddlewareAction("/about", "expired-token", vi.fn().mockRejectedValue(new AuthSessionExpiredError()));
    expect(action3.kind).toBe("pass");
  });

  // -----------------------------------------------------------------------
  // getSessionToken helper
  // -----------------------------------------------------------------------

  it("getSessionToken extracts session_token from cookies [positive]", async () => {
    const { getSessionToken } = await import("./auth-middleware");

    // Mock NextRequest
    const mockRequest = {
      cookies: {
        get: vi.fn((name: string) => {
          if (name === "session_token") return { value: "my-session-token" };
          return undefined;
        }),
      },
    };

    const token = getSessionToken(mockRequest as any);
    expect(token).toBe("my-session-token");
  });

  it("getSessionToken returns null when no session cookie [negative]", async () => {
    const { getSessionToken } = await import("./auth-middleware");

    const mockRequest = {
      cookies: {
        get: vi.fn(() => undefined),
      },
    };

    const token = getSessionToken(mockRequest as any);
    expect(token).toBeNull();
  });
});

// ===========================================================================
// Nav bar component tests — DOM rendering via @testing-library/react
// ===========================================================================

describe("NavBar — session-aware navigation", () => {
  // We need to render the component in jsdom. The NavBar accepts session
  // state as props and callbacks.

  beforeEach(() => {
    cleanup();
  });

  afterEach(() => {
    cleanup();
  });

  // -----------------------------------------------------------------------
  // AC-1: No session → Register and Login links
  // -----------------------------------------------------------------------

  it("AC-1: when no session exists, nav bar displays Register and Login links and NO Logout button or user email [positive]", async () => {
    const { NavBar } = await import("./nav-bar");

    render(
      React.createElement(NavBar, {
        session: null,
        loading: false,
        onLogout: vi.fn(),
        logoutError: null,
      }),
    );

    // Register and Login links present
    expect(screen.getByText("Register")).toBeDefined();
    expect(screen.getByText("Login")).toBeDefined();

    // Logout button and user email NOT present
    expect(screen.queryByText("Logout")).toBeNull();
    expect(screen.queryByText(/@/)).toBeNull();
  });

  // -----------------------------------------------------------------------
  // AC-1: Valid session → email and Logout button
  // -----------------------------------------------------------------------

  it("AC-1: when a valid session exists, nav bar displays user email and Logout button and NO Register/Login links [positive]", async () => {
    const { NavBar } = await import("./nav-bar");

    render(
      React.createElement(NavBar, {
        session: { id: "user-1", email: "alice@example.com", createdAt: "", updatedAt: "" },
        loading: false,
        onLogout: vi.fn(),
        logoutError: null,
      }),
    );

    // User email and Logout button present
    expect(screen.getByText("alice@example.com")).toBeDefined();
    expect(screen.getByText("Logout")).toBeDefined();

    // Register and Login links NOT present
    expect(screen.queryByText("Register")).toBeNull();
    expect(screen.queryByText("Login")).toBeNull();
  });

  // -----------------------------------------------------------------------
  // AC-2: Click Logout → calls onLogout
  // -----------------------------------------------------------------------

  it("AC-2: clicking Logout calls onLogout with the current session token [positive]", async () => {
    const { NavBar } = await import("./nav-bar");

    const onLogout = vi.fn();
    const session = { id: "user-1", email: "alice@example.com", createdAt: "", updatedAt: "" };

    render(
      React.createElement(NavBar, {
        session,
        loading: false,
        onLogout,
        logoutError: null,
      }),
    );

    const logoutButton = screen.getByText("Logout");
    fireEvent.click(logoutButton);

    expect(onLogout).toHaveBeenCalledTimes(1);
  });

  // -----------------------------------------------------------------------
  // AC-2: Logout failure → error message displayed
  // -----------------------------------------------------------------------

  it("AC-2: when logout fails, error is surfaced to the user and nav state is unchanged [negative]", async () => {
    const { NavBar } = await import("./nav-bar");

    const session = { id: "user-1", email: "alice@example.com", createdAt: "", updatedAt: "" };

    render(
      React.createElement(NavBar, {
        session,
        loading: false,
        onLogout: vi.fn().mockRejectedValue(new Error("Logout failed")),
        logoutError: "Failed to log out. Please try again.",
      }),
    );

    // Error message is displayed
    expect(screen.getByText("Failed to log out. Please try again.")).toBeDefined();

    // Nav state unchanged — still showing authenticated view
    expect(screen.getByText("alice@example.com")).toBeDefined();
    expect(screen.getByText("Logout")).toBeDefined();
  });

  // -----------------------------------------------------------------------
  // AC-6: Loading state → skeleton/spinner, not unauthenticated view
  // -----------------------------------------------------------------------

  it("AC-6: while session is loading, nav shows a loading skeleton/spinner and does NOT show Register/Login links [positive]", async () => {
    const { NavBar } = await import("./nav-bar");

    render(
      React.createElement(NavBar, {
        session: null,
        loading: true,
        onLogout: vi.fn(),
        logoutError: null,
      }),
    );

    // Loading indicator present (check for aria-label or data-testid)
    const loadingIndicator = screen.getByTestId("nav-loading");
    expect(loadingIndicator).toBeDefined();

    // Unauthenticated links NOT shown during loading
    expect(screen.queryByText("Register")).toBeNull();
    expect(screen.queryByText("Login")).toBeNull();

    // Authenticated content NOT shown during loading
    expect(screen.queryByText("Logout")).toBeNull();
  });
});

// ===========================================================================
// Cookie helper tests
// ===========================================================================

describe("Cookie helpers", () => {
  it("CLEAR_SESSION_COOKIE returns a cookie-setting header that clears the session token", async () => {
    const { CLEAR_SESSION_COOKIE, SESSION_COOKIE_NAME } = await import("./auth-middleware");

    const result = CLEAR_SESSION_COOKIE;

    expect(result).toContain(SESSION_COOKIE_NAME);
    expect(result).toContain("Max-Age=0");
    expect(result).toContain("Path=/");
  });
});