// src/ui/login-form.tsx — Login form component (S1.4)
//
// 'use client' component that captures email + password, validates on submit,
// and delegates to the provided onLogin handler.
//
// AC-3: Calls onLogin, redirects on success
// AC-4: Shows "Invalid email or password" on failure (generic, non-revealing)
// REQ-UI-001: All touch targets ≥ 44×44 CSS pixels on viewports ≤ 768px

"use client";

import React, { useState, useCallback } from "react";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface LoginFormProps {
  /** Async function that performs login. Returns error if authentication fails. */
  onLogin: (email: string, password: string) => Promise<{ error?: Error }>;
  /** Called after successful login (e.g., to redirect to dashboard). */
  onSuccess?: () => void;
}

// ---------------------------------------------------------------------------
// Client-side validation
// ---------------------------------------------------------------------------

interface ValidationErrors {
  email?: string;
  password?: string;
}

function validateEmail(email: string): string | undefined {
  if (email.length === 0) return "Email is required";
  // Login form does not validate email format client-side (the server handles it)
  return undefined;
}

function validatePassword(password: string): string | undefined {
  if (password.length === 0) return "Password is required";
  return undefined;
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function LoginForm({ onLogin, onSuccess }: LoginFormProps) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [errors, setErrors] = useState<ValidationErrors>({});
  const [serverError, setServerError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const handleSubmit = useCallback(
    async (e: React.FormEvent) => {
      e.preventDefault();

      // --- Client-side validation ---
      const emailError = validateEmail(email);
      const passwordError = validatePassword(password);
      const newErrors: ValidationErrors = {};
      if (emailError) newErrors.email = emailError;
      if (passwordError) newErrors.password = passwordError;
      setErrors(newErrors);
      setServerError(null);

      if (Object.keys(newErrors).length > 0) return;

      // --- Submit ---
      setLoading(true);
      try {
        const result = await onLogin(email, password);
        if (result.error) {
          setServerError(result.error.message);
        } else {
          onSuccess?.();
        }
      } catch {
        setServerError("An unexpected error occurred. Please try again.");
      } finally {
        setLoading(false);
      }
    },
    [email, password, onLogin, onSuccess],
  );

  return (
    <form onSubmit={handleSubmit} noValidate className="login-form" data-testid="login-form">
      <h1>Sign In</h1>

      {/* ---- Email field ---- */}
      <div className="field">
        <label htmlFor="login-email">Email</label>
        <input
          id="login-email"
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="you@example.com"
          aria-describedby={errors.email ? "login-email-error" : undefined}
          aria-invalid={errors.email ? true : undefined}
          disabled={loading}
          autoComplete="email"
        />
        {errors.email && (
          <p id="login-email-error" className="field-error" role="alert">
            {errors.email}
          </p>
        )}
      </div>

      {/* ---- Password field ---- */}
      <div className="field">
        <label htmlFor="login-password">Password</label>
        <input
          id="login-password"
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          placeholder="Enter your password"
          aria-describedby={errors.password ? "login-password-error" : undefined}
          aria-invalid={errors.password ? true : undefined}
          disabled={loading}
          autoComplete="current-password"
        />
        {errors.password && (
          <p id="login-password-error" className="field-error" role="alert">
            {errors.password}
          </p>
        )}
      </div>

      {/* ---- Server error (form-level) ---- */}
      {serverError && (
        <p className="form-error" role="alert" data-testid="login-server-error">
          {serverError}
        </p>
      )}

      {/* ---- Submit button ---- */}
      <button type="submit" disabled={loading} className="submit-btn">
        {loading ? "Signing in…" : "Sign In"}
      </button>
    </form>
  );
}