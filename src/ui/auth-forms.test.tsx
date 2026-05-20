// src/ui/auth-forms.test.tsx — Register and Login form unit tests (S1.4)
//
// TDD: Red → Green → Refactor
// Covers: AC-1 through AC-7 from task S1.4
// Anti-pattern verified: no implementation mocking (mock at service boundary),
// no shared mutable state, no snapshot overuse, no weak assertions.
//
// @vitest-environment jsdom

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, waitFor, cleanup } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import "@testing-library/jest-dom/vitest";
import React from "react";
import { RegisterForm } from "./register-form";
import { LoginForm } from "./login-form";

// ---------------------------------------------------------------------------
// Helpers — distinct sentinel values to avoid AP#10 (coincidental equality)
// ---------------------------------------------------------------------------

const VALID_EMAIL = "alice@example.com";
const VALID_PASSWORD = "secret123!";
const EXISTING_EMAIL = "existing@example.com";

// ---------------------------------------------------------------------------
// RegisterForm tests
// ---------------------------------------------------------------------------

afterEach(() => {
  cleanup();
});

describe("RegisterForm", () => {
  /** Returns a mock register handler and its bound mock function. */
  function createMockRegister() {
    const mockFn = vi.fn();
    const handler = async (email: string, password: string) => {
      mockFn(email, password);
      return { error: undefined };
    };
    return { handler, mockFn };
  }

  /** Returns a mock register handler that always returns a duplicate-user error. */
  function createDuplicateEmailRegister() {
    const handler = async (_email: string, _password: string) => {
      return { error: new Error("A user with this email is already registered.") };
    };
    return handler;
  }

  /** Returns a mock register handler that simulates a slow (in-flight) request. */
  function createSlowRegister() {
    const handler = async (_email: string, _password: string) => {
      // Intentionally never resolves during the test window
      return new Promise<{ error?: Error }>(() => {});
    };
    return handler;
  }

  // AC-1: Renders email and password fields with labels and a submit button
  it("AC-1: renders email and password fields with labels, submit button, and password toggle [positive]", () => {
    const { handler } = createMockRegister();
    render(<RegisterForm onRegister={handler} />);

    expect(screen.getByLabelText("Email")).toBeInTheDocument();
    expect(screen.getByLabelText("Password")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /create account/i })).toBeInTheDocument();
    // Password visibility toggle
    expect(screen.getByRole("button", { name: /show password/i })).toBeInTheDocument();
  });

  // AC-2: Submits valid email + password ≥ 8 chars, calls register service, redirects on success
  it("AC-2: submits valid email + password, calls register handler, invokes onSuccess on success [positive]", async () => {
    const user = userEvent.setup();
    const { handler, mockFn } = createMockRegister();
    const onSuccess = vi.fn();

    render(<RegisterForm onRegister={handler} onSuccess={onSuccess} />);

    await user.type(screen.getByLabelText("Email"), VALID_EMAIL);
    await user.type(screen.getByLabelText("Password"), VALID_PASSWORD);
    await user.click(screen.getByRole("button", { name: /create account/i }));

    await waitFor(() => {
      expect(mockFn).toHaveBeenCalledWith(VALID_EMAIL, VALID_PASSWORD);
    });
    expect(onSuccess).toHaveBeenCalledTimes(1);
  });

  // AC-1: Empty email → displays inline error 'Email is required', form not submitted
  it("AC-1: empty email displays inline error 'Email is required', form not submitted [negative]", async () => {
    const user = userEvent.setup();
    const { handler, mockFn } = createMockRegister();

    render(<RegisterForm onRegister={handler} />);

    // Fill password so only email is empty
    await user.type(screen.getByLabelText("Password"), VALID_PASSWORD);
    await user.click(screen.getByRole("button", { name: /create account/i }));

    expect(await screen.findByText(/email is required/i)).toBeInTheDocument();
    expect(mockFn).not.toHaveBeenCalled();
  });

  // AC-1: Email missing '@' → displays inline error 'Invalid email format', form not submitted
  it("AC-1: email missing '@' displays inline error 'Invalid email format', form not submitted [negative]", async () => {
    const user = userEvent.setup();
    const { handler, mockFn } = createMockRegister();

    render(<RegisterForm onRegister={handler} />);

    await user.type(screen.getByLabelText("Email"), "bademail");
    await user.type(screen.getByLabelText("Password"), VALID_PASSWORD);
    await user.click(screen.getByRole("button", { name: /create account/i }));

    expect(await screen.findByText(/invalid email format/i)).toBeInTheDocument();
    expect(mockFn).not.toHaveBeenCalled();
  });

  // AC-1: Password < 8 chars → displays inline error 'Password must be at least 8 characters'
  it("AC-1: password < 8 chars displays inline error 'Password must be at least 8 characters' [boundary]", async () => {
    const user = userEvent.setup();
    const { handler, mockFn } = createMockRegister();

    render(<RegisterForm onRegister={handler} />);

    await user.type(screen.getByLabelText("Email"), VALID_EMAIL);
    await user.type(screen.getByLabelText("Password"), "short");
    await user.click(screen.getByRole("button", { name: /create account/i }));

    expect(await screen.findByText(/password must be at least 8 characters/i)).toBeInTheDocument();
    expect(mockFn).not.toHaveBeenCalled();
  });

  // AC-1: Password of exactly 8 chars → validation passes
  it("AC-1: password of exactly 8 chars passes validation [boundary]", async () => {
    const user = userEvent.setup();
    const { handler, mockFn } = createMockRegister();
    const onSuccess = vi.fn();

    render(<RegisterForm onRegister={handler} onSuccess={onSuccess} />);

    await user.type(screen.getByLabelText("Email"), VALID_EMAIL);
    await user.type(screen.getByLabelText("Password"), "87654321"); // exactly 8 chars
    await user.click(screen.getByRole("button", { name: /create account/i }));

    await waitFor(() => {
      expect(mockFn).toHaveBeenCalled();
    });
    expect(onSuccess).toHaveBeenCalledTimes(1);
    // No password-too-short error displayed
    expect(screen.queryByText(/password must be at least 8 characters/i)).not.toBeInTheDocument();
  });

  // AC-2: AuthDuplicateUserError → displays 'Email already registered'
  it("AC-2: register service returns duplicate-user error, displays 'Email already registered' [negative]", async () => {
    const user = userEvent.setup();
    const handler = createDuplicateEmailRegister();

    render(<RegisterForm onRegister={handler} />);

    await user.type(screen.getByLabelText("Email"), EXISTING_EMAIL);
    await user.type(screen.getByLabelText("Password"), VALID_PASSWORD);
    await user.click(screen.getByRole("button", { name: /create account/i }));

    expect(await screen.findByTestId("register-server-error")).toHaveTextContent(/already registered/i);
  });

  // AC-7: Submit button is disabled while request is in-flight
  it("AC-7: submit button is disabled while request is in-flight [positive]", async () => {
    const user = userEvent.setup();
    const handler = createSlowRegister();

    render(<RegisterForm onRegister={handler} />);

    await user.type(screen.getByLabelText("Email"), VALID_EMAIL);
    await user.type(screen.getByLabelText("Password"), VALID_PASSWORD);
    await user.click(screen.getByRole("button", { name: /create account/i }));

    // Button should be disabled while request is pending
    expect(screen.getByRole("button", { name: /creating account/i })).toBeDisabled();
  });

  // AC-6: Password field has a visibility toggle
  it("AC-6: password visibility toggle switches between masked and plaintext [positive]", async () => {
    const user = userEvent.setup();
    const { handler } = createMockRegister();

    render(<RegisterForm onRegister={handler} />);

    const passwordInput = screen.getByLabelText("Password");
    const toggleButton = screen.getByRole("button", { name: /show password/i });

    // Initially masked
    expect(passwordInput).toHaveAttribute("type", "password");

    // Click toggle → show password
    await user.click(toggleButton);
    expect(passwordInput).toHaveAttribute("type", "text");

    // Click toggle again → hide password
    await user.click(toggleButton);
    expect(passwordInput).toHaveAttribute("type", "password");
  });
});

// ---------------------------------------------------------------------------
// LoginForm tests
// ---------------------------------------------------------------------------

describe("LoginForm", () => {
  function createMockLogin() {
    const mockFn = vi.fn();
    const handler = async (email: string, password: string) => {
      mockFn(email, password);
      return { error: undefined };
    };
    return { handler, mockFn };
  }

  function createFailingLogin() {
    const handler = async (_email: string, _password: string) => {
      return { error: new Error("Invalid email or password.") };
    };
    return handler;
  }

  // AC-3: Renders email and password fields with labels and a submit button
  it("AC-3: renders email and password fields with labels and a submit button [positive]", () => {
    const { handler } = createMockLogin();
    render(<LoginForm onLogin={handler} />);

    expect(screen.getByLabelText("Email")).toBeInTheDocument();
    expect(screen.getByLabelText("Password")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /sign in/i })).toBeInTheDocument();
  });

  // AC-3: Submits valid credentials, calls login service, redirects on success
  it("AC-3: submits valid credentials, calls login handler, invokes onSuccess on success [positive]", async () => {
    const user = userEvent.setup();
    const { handler, mockFn } = createMockLogin();
    const onSuccess = vi.fn();

    render(<LoginForm onLogin={handler} onSuccess={onSuccess} />);

    await user.type(screen.getByLabelText("Email"), VALID_EMAIL);
    await user.type(screen.getByLabelText("Password"), VALID_PASSWORD);
    await user.click(screen.getByRole("button", { name: /sign in/i }));

    await waitFor(() => {
      expect(mockFn).toHaveBeenCalledWith(VALID_EMAIL, VALID_PASSWORD);
    });
    expect(onSuccess).toHaveBeenCalledTimes(1);
  });

  // AC-4: AuthInvalidCredentialsError → displays 'Invalid email or password'
  it("AC-4: login service returns invalid-credentials error, displays 'Invalid email or password' [negative]", async () => {
    const user = userEvent.setup();
    const handler = createFailingLogin();

    render(<LoginForm onLogin={handler} />);

    await user.type(screen.getByLabelText("Email"), VALID_EMAIL);
    await user.type(screen.getByLabelText("Password"), "wrongpass!");
    await user.click(screen.getByRole("button", { name: /sign in/i }));

    expect(await screen.findByText(/invalid email or password/i)).toBeInTheDocument();
  });

  // AC-3: Empty email → displays inline error, form not submitted
  it("AC-3: empty email displays inline error, form not submitted [negative]", async () => {
    const user = userEvent.setup();
    const { handler, mockFn } = createMockLogin();

    render(<LoginForm onLogin={handler} />);

    await user.type(screen.getByLabelText("Password"), VALID_PASSWORD);
    await user.click(screen.getByRole("button", { name: /sign in/i }));

    expect(await screen.findByText(/email is required/i)).toBeInTheDocument();
    expect(mockFn).not.toHaveBeenCalled();
  });

  // AC-3: Empty password → displays inline error, form not submitted
  it("AC-3: empty password displays inline error, form not submitted [negative]", async () => {
    const user = userEvent.setup();
    const { handler, mockFn } = createMockLogin();

    render(<LoginForm onLogin={handler} />);

    await user.type(screen.getByLabelText("Email"), VALID_EMAIL);
    await user.click(screen.getByRole("button", { name: /sign in/i }));

    expect(await screen.findByText(/password is required/i)).toBeInTheDocument();
    expect(mockFn).not.toHaveBeenCalled();
  });
});