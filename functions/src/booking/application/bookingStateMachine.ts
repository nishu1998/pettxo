import type {BookingActor, CanonicalBookingState} from "../domain/bookingContracts";

export type BookingTransitionCode =
  | "ALLOWED"
  | "INVALID_CURRENT_STATE"
  | "TERMINAL_STATE"
  | "DEADLINE_PASSED"
  | "ACTOR_NOT_AUTHORIZED"
  | "IDEMPOTENT_REPLAY"
  | "MALFORMED_BOOKING";

export type BookingTransitionEvaluation = {
  ok: boolean;
  code: BookingTransitionCode;
  fromState: CanonicalBookingState;
  toState: CanonicalBookingState;
  actor: BookingActor;
  message: string;
};

const TERMINAL_STATES = new Set<CanonicalBookingState>([
  "DECLINED",
  "EXPIRED",
  "PAYMENT_EXPIRED",
  "CANCELLED_BY_PARENT",
  "CANCELLED",
]);

const ALLOWED_TRANSITIONS: Record<CanonicalBookingState, CanonicalBookingState[]> = {
  REQUESTED: ["PENDING_PROVIDER", "CANCELLED_BY_PARENT"],
  PENDING_PROVIDER: [
    "ACCEPTED_AWAITING_PAYMENT",
    "DECLINED",
    "EXPIRED",
    "CANCELLED_BY_PARENT",
  ],
  ACCEPTED_AWAITING_PAYMENT: ["PAYMENT_EXPIRED"],
  CONFIRMED: ["IN_PROGRESS", "CANCELLED", "NO_SHOW"],
  IN_PROGRESS: ["COMPLETED_PENDING_REVIEW"],
  COMPLETED_PENDING_REVIEW: ["COMPLETED_FINAL"],
  COMPLETED_FINAL: [],
  DECLINED: [],
  EXPIRED: [],
  PAYMENT_EXPIRED: [],
  CANCELLED_BY_PARENT: [],
  CANCELLED: [],
  DISPUTED: [],
  SERVICE_NOT_STARTED: [],
  NO_SHOW: [],
};

function allowedActorsForTransition(
  fromState: CanonicalBookingState,
  toState: CanonicalBookingState,
): BookingActor[] {
  if (fromState === "REQUESTED" && toState === "PENDING_PROVIDER") return ["system", "admin"];
  if (fromState === "REQUESTED" && toState === "CANCELLED_BY_PARENT") return ["parent", "admin"];
  if (fromState === "PENDING_PROVIDER" && toState === "ACCEPTED_AWAITING_PAYMENT") {
    return ["provider", "admin"];
  }
  if (fromState === "PENDING_PROVIDER" && toState === "DECLINED") return ["provider", "admin"];
  if (fromState === "PENDING_PROVIDER" && toState === "EXPIRED") return ["system", "admin"];
  if (fromState === "PENDING_PROVIDER" && toState === "CANCELLED_BY_PARENT") {
    return ["parent", "admin"];
  }
  if (fromState === "ACCEPTED_AWAITING_PAYMENT" && toState === "PAYMENT_EXPIRED") {
    return ["system", "admin"];
  }
  if (fromState === "CONFIRMED" && toState === "CANCELLED") {
    return ["parent", "provider", "admin"];
  }
  if (fromState === "CONFIRMED" && toState === "IN_PROGRESS") {
    return ["provider", "admin"];
  }
  if (fromState === "CONFIRMED" && toState === "NO_SHOW") {
    return ["system", "admin"];
  }
  if (fromState === "IN_PROGRESS" && toState === "COMPLETED_PENDING_REVIEW") {
    return ["provider", "admin"];
  }
  if (fromState === "COMPLETED_PENDING_REVIEW" && toState === "COMPLETED_FINAL") {
    return ["system", "admin"];
  }
  return [];
}

export function evaluateBookingTransition(params: {
  fromState: CanonicalBookingState;
  toState: CanonicalBookingState;
  actor: BookingActor;
  now: Date;
  acceptDeadlineAt?: Date | null;
  payDeadlineAt?: Date | null;
}): BookingTransitionEvaluation {
  const {fromState, toState, actor, now, acceptDeadlineAt, payDeadlineAt} = params;
  if (!(now instanceof Date) || Number.isNaN(now.getTime())) {
    return {
      ok: false,
      code: "MALFORMED_BOOKING",
      fromState,
      toState,
      actor,
      message: "Authoritative now timestamp is invalid.",
    };
  }
  if (fromState === toState) {
    return {
      ok: false,
      code: "IDEMPOTENT_REPLAY",
      fromState,
      toState,
      actor,
      message: "Transition already applied.",
    };
  }
  if (TERMINAL_STATES.has(fromState)) {
    return {
      ok: false,
      code: "TERMINAL_STATE",
      fromState,
      toState,
      actor,
      message: `State ${fromState} is terminal for Block 3 transitions.`,
    };
  }
  if (!ALLOWED_TRANSITIONS[fromState].includes(toState)) {
    return {
      ok: false,
      code: "INVALID_CURRENT_STATE",
      fromState,
      toState,
      actor,
      message: `Transition ${fromState} -> ${toState} is not allowed.`,
    };
  }
  if (!allowedActorsForTransition(fromState, toState).includes(actor)) {
    return {
      ok: false,
      code: "ACTOR_NOT_AUTHORIZED",
      fromState,
      toState,
      actor,
      message: `Actor ${actor} cannot perform ${fromState} -> ${toState}.`,
    };
  }
  if (
    fromState === "PENDING_PROVIDER" &&
    (toState === "ACCEPTED_AWAITING_PAYMENT" || toState === "DECLINED") &&
    acceptDeadlineAt instanceof Date &&
    now.getTime() > acceptDeadlineAt.getTime()
  ) {
    return {
      ok: false,
      code: "DEADLINE_PASSED",
      fromState,
      toState,
      actor,
      message: "Acceptance deadline has already passed.",
    };
  }
  if (
    fromState === "PENDING_PROVIDER" &&
    toState === "EXPIRED" &&
    acceptDeadlineAt instanceof Date &&
    now.getTime() < acceptDeadlineAt.getTime()
  ) {
    return {
      ok: false,
      code: "DEADLINE_PASSED",
      fromState,
      toState,
      actor,
      message: "Cannot expire a request before the acceptance deadline.",
    };
  }
  if (
    fromState === "ACCEPTED_AWAITING_PAYMENT" &&
    toState === "PAYMENT_EXPIRED" &&
    payDeadlineAt instanceof Date &&
    now.getTime() < payDeadlineAt.getTime()
  ) {
    return {
      ok: false,
      code: "DEADLINE_PASSED",
      fromState,
      toState,
      actor,
      message: "Cannot expire payment before the payment deadline.",
    };
  }

  return {
    ok: true,
    code: "ALLOWED",
    fromState,
    toState,
    actor,
    message: `Transition ${fromState} -> ${toState} is allowed.`,
  };
}

export function transitionTable(): Readonly<Record<CanonicalBookingState, readonly CanonicalBookingState[]>> {
  return ALLOWED_TRANSITIONS;
}
