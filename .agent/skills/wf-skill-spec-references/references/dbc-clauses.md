# Design-by-Contract Clauses

Some exposed symbols in `COMPONENTS.yaml` carry a contract worth specifying —
preconditions, postconditions, invariants, typed errors, style. Others are plain
data types or trivial helpers; for those a name is enough.

## When DbC pulls weight (apply it here)

- The symbol is **called from multiple components** or across a component boundary.
- The contract is **non-obvious** from the name and signature alone.
- Wrong assumptions about the contract have caused, or would cause, real bugs.
- Tests need a clear oracle (success postcondition + per-error-type assertions).

## When DbC is overhead (skip it)

- Pure data types (structs, records) with no behaviour.
- Trivial helpers (`cn(...)` Tailwind merge, `isNil(...)`) whose contract is the name.
- Internal helpers within a single component, called from one site.

For "skip" cases, list the symbol name plainly in `exposes:` and move on.

## The five DbC fields

For a contract-worthy symbol, write an `exposes:` entry with a structured block:

### `preconditions`

What the **caller** must guarantee before invoking. List of conditions. Each
condition must be testable; reference parameters by name.

```yaml
preconditions:
  - "userId is a non-empty string of length ≤ 64."
  - "userId conforms to RFC 4122 UUID v4 format."
  - "The caller holds a read-or-write lock on the user store."
```

### `postconditions`

What the **implementer** guarantees on return, **assuming preconditions held**.
Split by outcome if multiple. Pattern: success postcondition + one per typed error.

```yaml
postconditions:
  on_success:
    - "Returns a User object with id == userId."
    - "User.lastAccessedAt is set to now."
  on_UserNotFoundError:
    - "Returns UserNotFoundError; user store unchanged."
  on_StorageError:
    - "Returns StorageError; user store unchanged."
```

### `invariants`

Conditions that hold **before AND after** every public call on the instance
(or, for stateless symbols, on the component as a whole). If the symbol is
stateless and has no invariants, declare `invariants: []` explicitly — don't omit.

```yaml
invariants:
  - "user_count >= 0"
  - "indexed_users.keys() ⊆ user_store.ids()"
```

### `typed_errors`

Named error types the symbol may signal, with the condition that produces each.
Implementers may not invent error types not listed here; callers may rely on this
list being exhaustive.

```yaml
typed_errors:
  - name: UserNotFoundError
    when: "The supplied userId does not correspond to any user record."
  - name: StorageError
    when: "The underlying user-store is unavailable or returns I/O error."
```

### `style`

One of:

- **`demanding`** — strong preconditions. Caller checks inputs. Implementer
  assumes preconditions hold and does NOT add defensive checks. Precondition
  violation is a caller bug.
- **`tolerant`** — weak preconditions. Implementer accepts loose inputs and
  produces defined behaviour (typically a typed error) for invalid inputs.
  Burden is on the implementer.

Pick whichever **maximises architectural simplicity** — if the same caller-side
check is needed in many places, hoist it into the implementer (tolerant). If
the precondition is naturally checked once at a boundary above, push it to the
caller (demanding).

## Hidden clauses forbidden

Meyer's rule: the contract's obligation list **implicitly limits the contractor's
duties** to only those obligations.

- Do not write code that assumes obligations not in the contract.
- Do not check preconditions in a `demanding` implementation — duplicate
  checking inflates complexity.

Clean blame assignment:
- **Precondition violation** → caller bug.
- **Postcondition violation** → implementer bug.
- **Invariant violation** → implementer bug.

## DbC ↔ test mapping

| Contract element                          | Test phase   | Note                                              |
|-------------------------------------------|--------------|---------------------------------------------------|
| Precondition                              | Arrange      | The arrange step encodes the precondition.        |
| Postcondition (success)                   | Assert       | Becomes the success-case assertion.               |
| Postcondition (failure, per typed_error)  | Assert       | Each typed_error produces a dedicated test case.  |
| Invariant                                 | Assert (after) | Verify invariants hold post-call for state-mutating calls. |

Downstream impl contracts (SwA) and test authors (build agent) consume DbC
clauses to derive test cases. Quality of DbC = quality of generated tests.

## Anti-patterns

- **Vague preconditions.** "valid input", "reasonable size", "well-formed". Specify
  what "valid" means — type, length, format, range.
- **Postcondition that paraphrases the function name.** "Returns the user" is the
  name, not the postcondition. State **observable consequences**: what's returned,
  what state changed, what's emitted.
- **Untyped errors.** "May throw an exception" tells the caller nothing. List the types.
- **Defensive-programming creep.** Once you've declared `demanding`, do not write
  `if (userId == null) throw ...` inside the implementation — that says "actually
  I'm tolerant after all". Pick a style and honour it.

## In COMPONENTS.yaml

```yaml
exposes:
  - name: AuthMiddleware.Validate                # contract-worthy — full block
    signature:
      parameters:
        - { name: token, type: string }
      return_type: "(User, error)"
    preconditions:
      - "token is a non-empty string."
    postconditions:
      on_success:
        - "Returned User.id matches the token's `sub` claim."
      on_AuthExpiredError:
        - "Token's `exp` claim is in the past."
    invariants: []
    typed_errors:
      - { name: AuthExpiredError, when: "Token's exp claim is in the past." }
      - { name: AuthInvalidError, when: "Signature/claim verification failed." }
    style: tolerant
  - SessionStore                                 # trivial — plain name is enough
  - User                                         # pure data type
```

The two forms (structured block vs. plain string) coexist in the same `exposes:`
array. Mix freely — use the structured form only where the contract pulls weight.
