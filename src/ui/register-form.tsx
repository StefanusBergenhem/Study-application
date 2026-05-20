// src/ui/register-form.tsx — Register form component (S1.4)
//
// 'use client' component that captures email + password, validates on submit,
// and delegates to the provided onRegister handler.
//
// AC-1: Client-side validation (email format, password ≥ 8 chars)
// AC-2: Calls onRegister, redirects on success, shows "Email already registered" on duplicate
// AC-6: Password show/hide toggle
// AC-7: Disable submit during submission (double-submit prevention)
// REQ-UI-001: All touch targets ≥ 44×44 CSS pixels on viewports ≤ 768px

"use client";

import React, { useState, useCallback } from "react";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface RegisterFormProps {
  /** Async function that performs registration. Returns error if registration fails. */
  onRegister: (email: string, password: string) => Promise<{ error?: Error }>;
  /** Called after successful registration (e.g., to redirect to login page). */
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
  if (!email.includes("@")) return "Invalid email format";
  return undefined;
}

function validatePassword(password: string): string | undefined {
  if (password.length === 0) return "Password is required";
  if (password.length < 8) return "Password must be at least 8 characters";
  return undefined;
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function RegisterForm({ onRegister, onSuccess }: RegisterFormProps) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
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
        const result = await onRegister(email, password);
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
    [email, password, onRegister, onSuccess],
  );

  return (
    <form onSubmit={handleSubmit} noValidate className="register-form" data-testid="register-form">
      <h1>Create Account</h1>

      {/* ---- Email field ---- */}
      <div className="field">
        <label htmlFor="register-email">Email</label>
        <input
          id="register-email"
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="you@example.com"
          aria-describedby={errors.email ? "register-email-error" : undefined}
          aria-invalid={errors.email ? true : undefined}
          disabled={loading}
          autoComplete="email"
        />
        {errors.email && (
          <p id="register-email-error" className="field-error" role="alert">
            {errors.email}
          </p>
        )}
      </div>

      {/* ---- Password field ---- */}
      <div className="field">
        <label htmlFor="register-password">Password</label>
        <div className="password-wrapper">
          <input
            id="register-password"
            type={showPassword ? "text" : "password"}
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="At least 8 characters"
            aria-describedby={errors.password ? "register-password-error" : undefined}
            aria-invalid={errors.password ? true : undefined}
            disabled={loading}
            autoComplete="new-password"
          />
          <button
            type="button"
            className="password-toggle"
            onClick={() => setShowPassword((prev) => !prev)}
            aria-label={showPassword ? "Hide password" : "Show password"}
            disabled={loading}
          >
            {showPassword ? "Hide" : "Show"}
          </button>
        </div>
        {errors.password && (
          <p id="register-password-error" className="field-error" role="alert">
            {errors.password}
          </p>
        )}
      </div>

      {/* ---- Server error (form-level) ---- */}
      {serverError && (
        <p className="form-error" role="alert" data-testid="register-server-error">
          {serverError}
        </p>
      )}

      {/* ---- Submit button ---- */}
      <button type="submit" disabled={loading} className="submit-btn">
        {loading ? "Creating account…" : "Create Account"}
      </button>
    </form>
  );
}