// src/ui/nav-bar.tsx — Session-aware navigation bar
//
// A client component that displays different navigation links based on
// authentication state.
//
// AC-1: No session → Register + Login links; Valid session → email + Logout
// AC-2: Logout button triggers logout flow
// AC-5: Responsive touch targets ≥ 44×44 CSS pixels on narrow viewports
// AC-6: Loading state shows skeleton, not unauthenticated view
//
// Depends on: PublicUser from auth/user.model.ts (S1.3)

import React from "react";
import type { PublicUser } from "../auth/user.model";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface NavBarProps {
  /** The current session user, or null if not authenticated. */
  session: PublicUser | null;
  /** Whether the session is still being loaded. */
  loading: boolean;
  /** Callback invoked when the user clicks Logout. */
  onLogout: () => void | Promise<void>;
  /** Error message from a failed logout attempt, or null. */
  logoutError: string | null;
}

// ---------------------------------------------------------------------------
// NavBar component
// ---------------------------------------------------------------------------

/**
 * Session-aware navigation bar.
 *
 * Renders different content based on authentication state:
 * - **Loading:** A placeholder skeleton/spinner while the session resolves.
 * - **Authenticated:** User email and a Logout button.
 * - **Unauthenticated:** Register and Login links.
 */
export function NavBar({ session, loading, onLogout, logoutError }: NavBarProps) {
  // --- Loading state (AC-6) ---
  if (loading) {
    return (
      <nav
        className="nav-bar nav-bar--loading"
        role="navigation"
        aria-label="Main navigation"
        data-testid="nav-loading"
      >
        <div className="nav-bar__loading-skeleton" aria-label="Loading navigation" />
      </nav>
    );
  }

  // --- Authenticated state (AC-1) ---
  if (session !== null) {
    return (
      <nav className="nav-bar nav-bar--authenticated" role="navigation" aria-label="Main navigation">
        <div className="nav-bar__user-info">
          <span className="nav-bar__email" data-testid="nav-user-email">
            {session.email}
          </span>
        </div>

        <div className="nav-bar__actions">
          <button
            className="nav-bar__logout-btn"
            onClick={onLogout}
            type="button"
            aria-label="Log out"
          >
            Logout
          </button>
        </div>

        {logoutError && (
          <div className="nav-bar__error" role="alert" data-testid="nav-logout-error">
            {logoutError}
          </div>
        )}
      </nav>
    );
  }

  // --- Unauthenticated state (AC-1) ---
  return (
    <nav className="nav-bar nav-bar--unauthenticated" role="navigation" aria-label="Main navigation">
      <div className="nav-bar__links">
        <a href="/register" className="nav-bar__link" aria-label="Register">
          Register
        </a>
        <a href="/login" className="nav-bar__link" aria-label="Login">
          Login
        </a>
      </div>
    </nav>
  );
}