export class DomainError extends Error {
  constructor(public readonly code: string, message: string, public readonly status = 422) {
    super(message);
  }
}

export class NotFound extends DomainError {
  constructor(what: string) { super("not_found", `${what} not found`, 404); }
}

export class Invalid extends DomainError {
  constructor(detail: string) { super("invalid", detail, 400); }
}
