/**
 * Point-in-time, read-budgeted scanner for the relationship readiness audit.
 *
 * NOT exported from src/index.ts; defines no Cloud Function. Every read runs
 * inside one read-only transaction pinned to a single `readTime`, so all
 * collections describe the same moment of a live database. No transaction is
 * begun on the server for read-only + readTime transactions, so the 270-second
 * transaction lifetime does not apply; the readTime must stay inside Firestore
 * version retention (1 hour without PITR), enforced by MAX_SNAPSHOT_AGE_MS.
 */

import {
  FieldPath,
  Timestamp,
  type DocumentData,
  type Firestore,
  type Query,
  type QueryDocumentSnapshot,
  type Transaction,
} from "firebase-admin/firestore";

import {
  AUDIT_COLLECTIONS,
  type AuditCollectionKey,
  type AuditDoc,
  type AuditSourceData,
} from "./relationshipAuditEvaluation";
import {isReadOnlyFirestore} from "./readOnlyFirestore";

export const DEFAULT_PAGE_SIZE = 300;
export const MAX_PAGE_SIZE = 500;
/** Abort before Firestore's 1-hour version retention could invalidate the snapshot. */
export const MAX_SNAPSHOT_AGE_MS = 55 * 60 * 1000;
/** Field mask used for users/{uid} existence checks so no profile fields are returned. */
export const EXISTENCE_ONLY_FIELD = "__pettxoAuditExistenceOnly";
const BOOKING_STATES_FOR_COUNT = [
  "REQUESTED", "PENDING_PROVIDER", "ACCEPTED_AWAITING_PAYMENT", "CONFIRMED", "IN_PROGRESS",
  "COMPLETED_PENDING_REVIEW", "COMPLETED_FINAL", "DECLINED", "EXPIRED", "PAYMENT_EXPIRED",
  "CANCELLED_BY_PARENT", "CANCELLED", "DISPUTED", "SERVICE_NOT_STARTED", "NO_SHOW",
];

export class AuditIncompleteError extends Error {
  constructor(readonly reasonCode: string, message: string) {
    super(message);
    this.name = "AuditIncompleteError";
  }
}

export type ScanProgress = {
  readCount: number;
  maxReads: number | null;
  collectionsCompleted: Partial<Record<string, number>>;
  inProgress: string | null;
};

export type ScanOptions = {
  db: Firestore;
  readTime: Timestamp;
  maxReads: number | null;
  pageSize?: number;
  progress: ScanProgress;
  clock?: () => number;
};

class SnapshotReader {
  private readonly pageSize: number;
  private readonly clock: () => number;

  constructor(
    private readonly db: Firestore,
    private readonly transaction: Transaction,
    private readonly readTime: Timestamp,
    private readonly progress: ScanProgress,
    pageSize: number | undefined,
    clock: (() => number) | undefined,
  ) {
    this.pageSize = Math.min(Math.max(Math.trunc(pageSize ?? DEFAULT_PAGE_SIZE), 1), MAX_PAGE_SIZE);
    this.clock = clock ?? Date.now;
  }

  private remaining(): number {
    return this.progress.maxReads == null ? Number.POSITIVE_INFINITY :
      this.progress.maxReads - this.progress.readCount;
  }

  private beforeRead(label: string): number {
    if (this.clock() - this.readTime.toMillis() > MAX_SNAPSHOT_AGE_MS) {
      throw new AuditIncompleteError("SNAPSHOT_AGE_LIMIT",
        `snapshot older than ${MAX_SNAPSHOT_AGE_MS / 60000} minutes while reading ${label}`);
    }
    const remaining = this.remaining();
    if (remaining < 1) {
      throw new AuditIncompleteError("MAX_READS_EXCEEDED",
        `--max-reads=${this.progress.maxReads} reached while reading ${label}`);
    }
    return remaining;
  }

  private charge(reads: number): void {
    this.progress.readCount += reads;
  }

  private baseQuery(key: AuditCollectionKey): Query<DocumentData> {
    const spec = AUDIT_COLLECTIONS[key];
    return spec.group ? this.db.collectionGroup(spec.collection) : this.db.collection(spec.collection);
  }

  async scan(key: AuditCollectionKey): Promise<AuditDoc[]> {
    const label = AUDIT_COLLECTIONS[key].collection;
    this.progress.inProgress = label;
    const documents: AuditDoc[] = [];
    let cursor: QueryDocumentSnapshot<DocumentData> | null = null;
    while (true) {
      const limit = Math.min(this.pageSize, this.beforeRead(label));
      let query = this.baseQuery(key).orderBy(FieldPath.documentId()).limit(limit);
      if (cursor) query = query.startAfter(cursor);
      const page = await this.transaction.get(query);
      this.charge(Math.max(page.size, 1));
      for (const snapshot of page.docs) {
        documents.push({id: snapshot.id, path: snapshot.ref.path, data: snapshot.data()});
      }
      if (page.size < limit) break;
      cursor = page.docs[page.docs.length - 1] ?? null;
    }
    this.progress.collectionsCompleted[label] = documents.length;
    this.progress.inProgress = null;
    return documents;
  }

  async count(label: string, query: Query<DocumentData>): Promise<number> {
    this.beforeRead(label);
    this.progress.inProgress = label;
    const snapshot = await this.transaction.get(query.count());
    const count = snapshot.data().count;
    // Billing: one read per batch of up to 1000 index entries, minimum one.
    this.charge(Math.max(1, Math.ceil(count / 1000)));
    this.progress.inProgress = null;
    return count;
  }

  /** Probe a full-mode query shape with limit(1) so missing indexes fail in the cheap step. */
  async probe(key: AuditCollectionKey): Promise<void> {
    const label = `probe:${AUDIT_COLLECTIONS[key].collection}`;
    this.beforeRead(label);
    const page = await this.transaction.get(this.baseQuery(key).orderBy(FieldPath.documentId()).limit(1));
    this.charge(Math.max(page.size, 1));
  }

  async existingUserIds(uids: string[]): Promise<Set<string>> {
    const existing = new Set<string>();
    this.progress.inProgress = "users(existence)";
    for (let offset = 0; offset < uids.length;) {
      const take = Math.min(100, uids.length - offset, this.beforeRead("users(existence)"));
      const refs = uids.slice(offset, offset + take).map((uid) => this.db.collection("users").doc(uid));
      const snapshots = await this.transaction.getAll(...refs, {fieldMask: [EXISTENCE_ONLY_FIELD]});
      this.charge(refs.length);
      for (const snapshot of snapshots) if (snapshot.exists) existing.add(snapshot.id);
      offset += take;
    }
    this.progress.collectionsCompleted["users(existence)"] = uids.length;
    this.progress.inProgress = null;
    return existing;
  }
}

function assertReadOnly(db: Firestore): void {
  if (!isReadOnlyFirestore(db)) throw new Error("audit_requires_read_only_firestore");
}

async function inSnapshot<T>(options: ScanOptions, run: (reader: SnapshotReader) => Promise<T>): Promise<T> {
  assertReadOnly(options.db);
  return options.db.runTransaction(
    (transaction) => run(new SnapshotReader(options.db, transaction, options.readTime,
      options.progress, options.pageSize, options.clock)),
    {readOnly: true, readTime: options.readTime},
  );
}

const UID_PATTERN = /^[^/]{1,128}$/;

export async function scanRelationshipAuditSource(options: ScanOptions): Promise<AuditSourceData> {
  return inSnapshot(options, async (reader) => {
    const loaded = {} as Record<AuditCollectionKey, AuditDoc[]>;
    for (const key of Object.keys(AUDIT_COLLECTIONS) as AuditCollectionKey[]) {
      loaded[key] = await reader.scan(key);
    }
    const blockUids = new Set<string>();
    for (const doc of loaded.userBlocks) {
      for (const field of ["ownerUserId", "blockerUid", "blockedUserId"]) {
        const value = doc.data[field];
        if (typeof value === "string" && UID_PATTERN.test(value.trim())) blockUids.add(value.trim());
      }
    }
    const checkedUserIds = [...blockUids].sort();
    const existingUserIds = await reader.existingUserIds(checkedUserIds);
    return {...loaded, checkedUserIds: new Set(checkedUserIds), existingUserIds};
  });
}

export type CountOnlyResult = {
  collectionCounts: Record<string, number>;
  bookingsByState: Record<string, number>;
  bookingsWithNonCanonicalState: number;
  estimatedFullRunReads: number;
  suggestedMaxReads: number;
  queryShapesProbed: number;
};

export async function countRelationshipAuditSource(options: ScanOptions): Promise<CountOnlyResult> {
  return inSnapshot(options, async (reader) => {
    const collectionCounts: Record<string, number> = {};
    for (const key of Object.keys(AUDIT_COLLECTIONS) as AuditCollectionKey[]) {
      const spec = AUDIT_COLLECTIONS[key];
      const query = spec.group ? options.db.collectionGroup(spec.collection) : options.db.collection(spec.collection);
      collectionCounts[spec.collection] = await reader.count(spec.collection, query);
    }
    const bookingsByState: Record<string, number> = {};
    for (const state of BOOKING_STATES_FOR_COUNT) {
      bookingsByState[state] = await reader.count(`bookings:${state}`,
        options.db.collection("bookings").where("state", "==", state));
    }
    let probed = 0;
    for (const key of Object.keys(AUDIT_COLLECTIONS) as AuditCollectionKey[]) {
      await reader.probe(key);
      probed += 1;
    }
    const canonicalTotal = Object.values(bookingsByState).reduce((sum, value) => sum + value, 0);
    const documents = Object.values(collectionCounts).reduce((sum, value) => sum + value, 0);
    const pageSize = Math.min(Math.max(Math.trunc(options.pageSize ?? DEFAULT_PAGE_SIZE), 1), MAX_PAGE_SIZE);
    const pageOverhead = Object.values(collectionCounts)
      .reduce((sum, value) => sum + Math.floor(value / pageSize) + 1, 0);
    // users/{uid} existence: at most two UIDs per directed block.
    const userExistence = 2 * (collectionCounts.userBlocks ?? 0);
    const estimatedFullRunReads = documents + pageOverhead + userExistence;
    return {
      collectionCounts,
      bookingsByState,
      bookingsWithNonCanonicalState: Math.max((collectionCounts.bookings ?? 0) - canonicalTotal, 0),
      estimatedFullRunReads,
      suggestedMaxReads: Math.ceil(estimatedFullRunReads * 1.25) + 500,
      queryShapesProbed: probed,
    };
  });
}

/** Snapshot time used by the CLI: slightly in the past so it is never ahead of the server clock. */
export function chooseReadTime(nowMillis: number): Timestamp {
  return Timestamp.fromMillis(Math.floor((nowMillis - 2000) / 1000) * 1000);
}
