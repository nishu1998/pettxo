export type ProviderStatsV3 = {
  requestsReceived: number;
  requestsAccepted: number;
  requestsDeclined: number;
  requestsExpired: number;
  consecutiveDeclines: number;
  consecutiveExpiries: number;
  responseSamples: number[];
  parentPaymentAbandoned: number;
  appliedMutationKeys: string[];
  updatedAt: Date | null;
};

export type ParentStatsV3 = {
  requestsSent: number;
  paymentsCompleted: number;
  paymentsAbandoned: number;
  cancellationsAfterPayment: number;
  requiresUpfrontPayment: boolean;
  appliedMutationKeys: string[];
  updatedAt: Date | null;
};

export function emptyProviderStatsV3(): ProviderStatsV3 {
  return {
    requestsReceived: 0,
    requestsAccepted: 0,
    requestsDeclined: 0,
    requestsExpired: 0,
    consecutiveDeclines: 0,
    consecutiveExpiries: 0,
    responseSamples: [],
    parentPaymentAbandoned: 0,
    appliedMutationKeys: [],
    updatedAt: null,
  };
}

export function emptyParentStatsV3(): ParentStatsV3 {
  return {
    requestsSent: 0,
    paymentsCompleted: 0,
    paymentsAbandoned: 0,
    cancellationsAfterPayment: 0,
    requiresUpfrontPayment: false,
    appliedMutationKeys: [],
    updatedAt: null,
  };
}

export type ProviderStatsMutation =
  | {type: "request_started"; mutationKey: string; occurredAt: Date}
  | {type: "accepted"; mutationKey: string; occurredAt: Date; responseSeconds: number | null}
  | {type: "declined"; mutationKey: string; occurredAt: Date; responseSeconds: number | null}
  | {type: "expired"; mutationKey: string; occurredAt: Date; responseSeconds: number | null}
  | {type: "parent_payment_abandoned"; mutationKey: string; occurredAt: Date};

export type ParentStatsMutation =
  | {type: "request_created"; mutationKey: string; occurredAt: Date}
  | {type: "payment_completed"; mutationKey: string; occurredAt: Date}
  | {type: "payment_abandoned"; mutationKey: string; occurredAt: Date};

function hasApplied(stats: {appliedMutationKeys: string[]}, mutationKey: string): boolean {
  return stats.appliedMutationKeys.includes(mutationKey);
}

function appendMutationKey(keys: string[], mutationKey: string): string[] {
  if (keys.includes(mutationKey)) return keys;
  const next = [...keys, mutationKey];
  return next.slice(Math.max(next.length - 100, 0));
}

function appendResponseSample(samples: number[], responseSeconds: number | null): number[] {
  if (responseSeconds == null || responseSeconds < 0) return samples;
  const next = [...samples, responseSeconds];
  return next.slice(Math.max(next.length - 50, 0));
}

export function applyProviderStatsMutation(
  current: ProviderStatsV3,
  mutation: ProviderStatsMutation,
): ProviderStatsV3 {
  if (hasApplied(current, mutation.mutationKey)) return current;

  switch (mutation.type) {
    case "request_started":
      return {
        ...current,
        requestsReceived: current.requestsReceived + 1,
        appliedMutationKeys: appendMutationKey(current.appliedMutationKeys, mutation.mutationKey),
        updatedAt: mutation.occurredAt,
      };
    case "accepted":
      return {
        ...current,
        requestsAccepted: current.requestsAccepted + 1,
        consecutiveDeclines: 0,
        consecutiveExpiries: 0,
        responseSamples: appendResponseSample(current.responseSamples, mutation.responseSeconds),
        appliedMutationKeys: appendMutationKey(current.appliedMutationKeys, mutation.mutationKey),
        updatedAt: mutation.occurredAt,
      };
    case "declined":
      return {
        ...current,
        requestsDeclined: current.requestsDeclined + 1,
        consecutiveDeclines: current.consecutiveDeclines + 1,
        consecutiveExpiries: 0,
        responseSamples: appendResponseSample(current.responseSamples, mutation.responseSeconds),
        appliedMutationKeys: appendMutationKey(current.appliedMutationKeys, mutation.mutationKey),
        updatedAt: mutation.occurredAt,
      };
    case "expired":
      return {
        ...current,
        requestsExpired: current.requestsExpired + 1,
        consecutiveDeclines: 0,
        consecutiveExpiries: current.consecutiveExpiries + 1,
        responseSamples: appendResponseSample(current.responseSamples, mutation.responseSeconds),
        appliedMutationKeys: appendMutationKey(current.appliedMutationKeys, mutation.mutationKey),
        updatedAt: mutation.occurredAt,
      };
    case "parent_payment_abandoned":
      return {
        ...current,
        parentPaymentAbandoned: current.parentPaymentAbandoned + 1,
        appliedMutationKeys: appendMutationKey(current.appliedMutationKeys, mutation.mutationKey),
        updatedAt: mutation.occurredAt,
      };
  }
}

export function applyParentStatsMutation(
  current: ParentStatsV3,
  mutation: ParentStatsMutation,
): ParentStatsV3 {
  if (hasApplied(current, mutation.mutationKey)) return current;

  switch (mutation.type) {
    case "request_created":
      return {
        ...current,
        requestsSent: current.requestsSent + 1,
        appliedMutationKeys: appendMutationKey(current.appliedMutationKeys, mutation.mutationKey),
        updatedAt: mutation.occurredAt,
      };
    case "payment_completed":
      return {
        ...current,
        paymentsCompleted: current.paymentsCompleted + 1,
        appliedMutationKeys: appendMutationKey(current.appliedMutationKeys, mutation.mutationKey),
        updatedAt: mutation.occurredAt,
      };
    case "payment_abandoned":
      return {
        ...current,
        paymentsAbandoned: current.paymentsAbandoned + 1,
        appliedMutationKeys: appendMutationKey(current.appliedMutationKeys, mutation.mutationKey),
        updatedAt: mutation.occurredAt,
      };
  }
}
