export type CanonicalDirectChatIdentity = {
  participantIds: [string, string];
  customerId: string;
  providerId: string;
};

function trimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export function chatIdForUidPair(leftUid: string, rightUid: string): string {
  return [leftUid.trim(), rightUid.trim()].sort().join("_");
}

export function canonicalChatIdForUidPair(leftUid: string, rightUid: string): string {
  return `chat_${chatIdForUidPair(leftUid, rightUid)}`;
}

export function canonicalParticipantIds(
  leftUid: string,
  rightUid: string,
): [string, string] | null {
  const participants = [leftUid.trim(), rightUid.trim()].sort();
  if (!participants[0] || !participants[1] || participants[0] === participants[1]) {
    return null;
  }
  return [participants[0], participants[1]];
}

export function canonicalUserDocumentMatches(
  uid: string,
  data: Record<string, unknown> | undefined,
): boolean {
  const canonicalUid = uid.trim();
  return canonicalUid.length > 0 && trimmedString(data?.uid) === canonicalUid;
}

export function canonicalDirectChatIdentity(
  data: Record<string, unknown>,
): CanonicalDirectChatIdentity | null {
  if (trimmedString(data.chatType) !== "directUser") return null;
  if (!Array.isArray(data.participantIds) || data.participantIds.length !== 2) {
    return null;
  }

  const leftUid = trimmedString(data.participantIds[0]);
  const rightUid = trimmedString(data.participantIds[1]);
  if (!leftUid || !rightUid || leftUid === rightUid) return null;
  if ([leftUid, rightUid].sort()[0] !== leftUid) return null;

  const customerId = trimmedString(data.customerId);
  const providerId = trimmedString(data.providerId);
  if (customerId !== leftUid || providerId !== rightUid) return null;

  return {
    participantIds: [leftUid, rightUid],
    customerId,
    providerId,
  };
}

export function canonicalDirectChatDocumentIdentity(
  chatId: string,
  data: Record<string, unknown>,
): CanonicalDirectChatIdentity | null {
  const identity = canonicalDirectChatIdentity(data);
  if (!identity) return null;
  return chatId.trim() === canonicalChatIdForUidPair(...identity.participantIds) ?
    identity :
    null;
}

export function otherDirectParticipantUid(
  identity: CanonicalDirectChatIdentity,
  currentUid: string,
): string | null {
  const uid = currentUid.trim();
  if (uid === identity.participantIds[0]) return identity.participantIds[1];
  if (uid === identity.participantIds[1]) return identity.participantIds[0];
  return null;
}

export function chatStatusAllowsMessages(chatType: string, status: string): boolean {
  const normalizedType = chatType.trim();
  const normalizedStatus = status.trim();
  if (normalizedType === "directUser") return normalizedStatus === "active";
  return false;
}
