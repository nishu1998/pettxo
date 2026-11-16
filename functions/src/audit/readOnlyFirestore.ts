/**
 * Read-only enforcement for operator audit tooling.
 *
 * This module is NOT exported from src/index.ts and defines no Cloud Function.
 * It is used only by scripts/read_only_relationship_audit.js.
 *
 * Two layers:
 *  1. enforceReadOnlyFirestore(db): per-instance. Every RPC the client sends
 *     is funnelled through Firestore#request / Firestore#requestStream; both are
 *     replaced with an allowlist of read RPCs (batchGetDocuments, runQuery,
 *     runAggregationQuery) that also rejects any transactional write context.
 *     High-level write entry points (batch, bulkWriter, recursiveDelete,
 *     read-write runTransaction, and transaction write methods) throw first so
 *     the failure is explicit.
 *  2. lockFirestoreWritePrototypes(classes): process-wide. Replaces every write
 *     method on DocumentReference, CollectionReference, WriteBatch, Transaction
 *     and BulkWriter prototypes. The audit CLI applies this before it creates
 *     any client, so no code in the process can write, whichever reference it
 *     obtains.
 */

import type {Firestore, Transaction} from "firebase-admin/firestore";

export const READ_ONLY_RPC_METHODS: ReadonlySet<string> = new Set([
  "batchGetDocuments",
  "runQuery",
  "runAggregationQuery",
]);

export class ReadOnlyViolationError extends Error {
  readonly code = "AUDIT_READ_ONLY_VIOLATION";

  constructor(operation: string) {
    super(`read-only audit refused write-capable operation: ${operation}`);
    this.name = "ReadOnlyViolationError";
  }
}

const READ_ONLY_MARKER = Symbol.for("pettxo.audit.readOnlyFirestore");

type MutableRecord = Record<string | symbol, unknown>;

function refuse(operation: string): never {
  throw new ReadOnlyViolationError(operation);
}

function assertReadRpc(methodName: unknown, request: unknown): void {
  const name = String(methodName);
  if (!READ_ONLY_RPC_METHODS.has(name)) refuse(`rpc:${name}`);
  const body = (request ?? {}) as MutableRecord;
  if (body.newTransaction != null) refuse(`rpc:${name}:newTransaction`);
  if (body.transaction != null) refuse(`rpc:${name}:transaction`);
}

const TRANSACTION_WRITE_METHODS = ["set", "update", "create", "delete"] as const;

function lockTransactionInstance(transaction: Transaction): Transaction {
  const mutable = transaction as unknown as MutableRecord;
  for (const method of TRANSACTION_WRITE_METHODS) {
    // defineProperty (not assignment): the prototype methods may already be
    // locked non-writable by lockFirestoreWritePrototypes.
    Object.defineProperty(mutable, method, {value: () => refuse(`transaction.${method}`), configurable: false});
  }
  return transaction;
}

export function isReadOnlyFirestore(db: Firestore): boolean {
  return (db as unknown as MutableRecord)[READ_ONLY_MARKER] === true;
}

export function enforceReadOnlyFirestore(db: Firestore): Firestore {
  const mutable = db as unknown as MutableRecord;
  if (mutable[READ_ONLY_MARKER] === true) return db;
  const request = mutable.request as ((...args: unknown[]) => unknown) | undefined;
  const requestStream = mutable.requestStream as ((...args: unknown[]) => unknown) | undefined;
  if (typeof request !== "function" || typeof requestStream !== "function") {
    // The RPC funnel is an internal of @google-cloud/firestore. If it moves,
    // refuse to run rather than silently losing the allowlist.
    throw new Error("audit_read_only_enforcement_unavailable");
  }
  mutable.request = (methodName: unknown, body: unknown, ...rest: unknown[]) => {
    assertReadRpc(methodName, body);
    return request.call(db, methodName, body, ...rest);
  };
  mutable.requestStream = (methodName: unknown, bidirectional: unknown, body: unknown, ...rest: unknown[]) => {
    assertReadRpc(methodName, body);
    return requestStream.call(db, methodName, bidirectional, body, ...rest);
  };
  for (const method of ["batch", "bulkWriter", "recursiveDelete", "bundle"]) {
    mutable[method] = () => refuse(`firestore.${method}`);
  }
  const runTransaction = db.runTransaction.bind(db);
  mutable.runTransaction = (
    updateFunction: (transaction: Transaction) => Promise<unknown>,
    options?: {readOnly?: boolean; readTime?: unknown},
  ) => {
    if (options?.readOnly !== true) refuse("firestore.runTransaction(read-write)");
    return runTransaction(
      (transaction) => updateFunction(lockTransactionInstance(transaction)),
      options as Parameters<Firestore["runTransaction"]>[1],
    );
  };
  Object.defineProperty(db, READ_ONLY_MARKER, {value: true, enumerable: false});
  return db;
}

type Constructor = {prototype: MutableRecord; name?: string};

export type FirestoreWriteClasses = {
  DocumentReference: Constructor;
  CollectionReference: Constructor;
  WriteBatch: Constructor;
  Transaction: Constructor;
  BulkWriter: Constructor;
};

export const PROTOTYPE_WRITE_METHODS: Readonly<Record<keyof FirestoreWriteClasses, readonly string[]>> = {
  DocumentReference: ["set", "update", "create", "delete"],
  CollectionReference: ["add"],
  WriteBatch: ["set", "update", "create", "delete", "commit"],
  Transaction: ["set", "update", "create", "delete"],
  BulkWriter: ["set", "update", "create", "delete", "flush", "close"],
};

/** Process-wide write lockdown. Irreversible by design; use only in a dedicated audit process. */
export function lockFirestoreWritePrototypes(classes: FirestoreWriteClasses): string[] {
  const locked: string[] = [];
  for (const [className, methods] of Object.entries(PROTOTYPE_WRITE_METHODS) as Array<
    [keyof FirestoreWriteClasses, readonly string[]]
  >) {
    const prototype = classes[className]?.prototype;
    if (!prototype) throw new Error(`audit_read_only_enforcement_unavailable:${className}`);
    for (const method of methods) {
      if (typeof prototype[method] !== "function") {
        throw new Error(`audit_read_only_enforcement_unavailable:${className}.${method}`);
      }
      Object.defineProperty(prototype, method, {
        value: () => refuse(`${className}.${method}`),
        writable: false,
        configurable: false,
      });
      locked.push(`${className}.${method}`);
    }
  }
  return locked;
}
