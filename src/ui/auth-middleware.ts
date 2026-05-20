// src/ui/auth-middleware.ts — Route protection middleware
//
// Next.js Edge middleware that runs on every request to protect routes
// based on authentication state. Uses AuthService.validateSession to
// validate the session cookie.
//
// AC-3: Protected routes redirect unauthenticated visitors to /login with returnUrl
// AC-4: Authenticated visitors on /login or /register redirect to /
//
// Depends on: AuthService from auth component (S1.3)

import { NextRequest, NextResponse } from "next/server";

// ---------------------------------------------------------------------------
// Route configuration
// ---------------------------------------------------------------------------

/** Routes that require authentication. */
export const PROTECTED_ROUTES = [
  "/dashboard",
  "/cards",
  "/libraries",
  "/study",
  "/export",
  "/settings",
  "/api-tokens",
  "/mind-maps",
];

/** Routes meant for unauthenticated users only (auth pages). */
export const AUTH_ROUTES = [
  "/login",
  "/register",
  "/forgot-password",
  "/reset-password",
];

/** Public routes accessible to everyone regardless of auth state. */
export const PUBLIC_ROUTES = ["/", "/about", "/privacy", "/terms"];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Check if a pathname matches any route in the given list.
 * Supports exact matches and prefix matches for sub-routes.
 */
export function matchesRoute(pathname: string, routes: string[]): boolean {
  const normalized = pathname.replace(/\/$/, "") || "/";
  for (const route of routes) {
    if (normalized === route || normalized.startsWith(route + "/")) {
      return true;
    }
  }
  return false;
}

/** Cookie name for the session token. */
export const SESSION_COOKIE_NAME = "session_token";

/**
 * Read the session token from the request cookies.
 * Returns null if no session cookie is present.
 */
export function getSessionToken(request: NextRequest): string | null {
  return request.cookies.get(SESSION_COOKIE_NAME)?.value ?? null;
}

/**
 * Set-Cookie header value that clears the session cookie.
 * Used by the logout flow to remove the cookie on the client.
 */
export const CLEAR_SESSION_COOKIE = `${SESSION_COOKIE_NAME}=; Max-Age=0; Path=/; HttpOnly; Secure; SameSite=Lax`;

// ---------------------------------------------------------------------------
// Action types
// ---------------------------------------------------------------------------

export type MiddlewareAction =
  | { kind: "redirect"; url: string }
  | { kind: "pass" };

// ---------------------------------------------------------------------------
// Core logic — pure function, testable without Next.js objects
// ---------------------------------------------------------------------------

/**
 * Compute the middleware action for a given request path and auth state.
 *
 * @param pathname — The URL pathname being requested
 * @param sessionToken — The session token from cookies (null if absent)
 * @param validateSession — A function that validates a session token
 * @returns A MiddlewareAction describing what to do
 */
export async function computeMiddlewareAction(
  pathname: string,
  sessionToken: string | null,
  validateSession: (token: string) => Promise<unknown>,
): Promise<MiddlewareAction> {
  const isProtected = matchesRoute(pathname, PROTECTED_ROUTES);
  const isAuthRoute = matchesRoute(pathname, AUTH_ROUTES);
  const isPublic = matchesRoute(pathname, PUBLIC_ROUTES);

  // Public routes always pass through
  if (isPublic) {
    return { kind: "pass" };
  }

  // No session token present
  if (sessionToken === null) {
    if (isProtected) {
      // AC-3: redirect to /login with returnUrl
      const returnUrl = encodeURIComponent(pathname);
      return { kind: "redirect", url: `/login?returnUrl=${returnUrl}` };
    }
    // Auth routes without session → pass through (they handle their own UI)
    return { kind: "pass" };
  }

  // Session token present — validate it
  try {
    await validateSession(sessionToken);
    // Session is valid
    if (isAuthRoute) {
      // AC-4: authenticated on auth page → redirect to /
      return { kind: "redirect", url: "/" };
    }
    return { kind: "pass" };
  } catch (error: unknown) {
    // Check if the error is an auth error (invalid or expired session)
    if (
      error instanceof Error &&
      (error.name === "AuthSessionExpiredError" || error.name === "AuthSessionInvalidError")
    ) {
      if (isProtected) {
        // AC-3: expired/invalid session → redirect to /login
        const returnUrl = encodeURIComponent(pathname);
        return { kind: "redirect", url: `/login?returnUrl=${returnUrl}` };
      }
      return { kind: "pass" };
    }
    // Unexpected error — re-throw
    throw error;
  }
}