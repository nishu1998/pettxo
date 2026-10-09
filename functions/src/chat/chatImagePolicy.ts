export const CHAT_IMAGE_CONTENT_TYPE = "image/jpeg";
export const CHAT_IMAGE_MEDIA_SCHEMA_VERSION = 1;
export const MAX_CHAT_IMAGE_BYTES = 3 * 1024 * 1024;
export const MAX_CHAT_IMAGE_EDGE = 1600;
export const CHAT_IMAGE_CAPABILITY = "chatImageV1";

const FIRESTORE_AUTO_ID_PATTERN = /^[A-Za-z0-9]{20}$/;
const JPEG_START_OF_FRAME_MARKERS = new Set([
  0xc0, 0xc1, 0xc2, 0xc3,
  0xc5, 0xc6, 0xc7,
  0xc9, 0xca, 0xcb,
  0xcd, 0xce, 0xcf,
]);

export type ChatImageDimensions = {
  width: number;
  height: number;
};

export type ChatImageMetadata = {
  contentType?: unknown;
  size?: unknown;
  metadata?: Record<string, unknown> | null;
};

export type ExistingImageMessage = {
  type?: unknown;
  senderId?: unknown;
  receiverId?: unknown;
  storagePath?: unknown;
  mimeType?: unknown;
  imageWidth?: unknown;
  imageHeight?: unknown;
  imageSizeBytes?: unknown;
  mediaSchemaVersion?: unknown;
};

export function chatImageUnreadField(
  participantIds: [string, string],
  receiverId: string,
): "unreadCountCustomer" | "unreadCountProvider" {
  if (receiverId === participantIds[0]) return "unreadCountCustomer";
  if (receiverId === participantIds[1]) return "unreadCountProvider";
  throw new Error("receiver-not-participant");
}

export function buildChatImageMessageData(params: {
  senderId: string;
  receiverId: string;
  storagePath: string;
  width: number;
  height: number;
  size: number;
}): Record<string, unknown> {
  return {
    senderId: params.senderId,
    receiverId: params.receiverId,
    text: "",
    type: "image",
    deliveredTo: [],
    readBy: [],
    sourceServiceId: "",
    sourceServiceTitle: "",
    storagePath: params.storagePath,
    imageWidth: params.width,
    imageHeight: params.height,
    imageSizeBytes: params.size,
    mimeType: CHAT_IMAGE_CONTENT_TYPE,
    mediaSchemaVersion: CHAT_IMAGE_MEDIA_SCHEMA_VERSION,
  };
}

function trimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function positiveInteger(value: unknown): number | null {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

export function isValidChatImageMessageId(value: unknown): value is string {
  return typeof value === "string" && FIRESTORE_AUTO_ID_PATTERN.test(value);
}

export function chatImageStoragePath(chatId: string, messageId: string): string {
  return `chatMedia/${chatId}/${messageId}/image.jpg`;
}

export function validateChatImageObjectMetadata(params: {
  metadata: ChatImageMetadata;
  expectedPath: string;
  actualPath: string;
  chatId: string;
  messageId: string;
  senderId: string;
}): {size: number} {
  if (params.actualPath !== params.expectedPath) {
    throw new Error("storage-path-mismatch");
  }
  if (trimmedString(params.metadata.contentType).toLowerCase() !== CHAT_IMAGE_CONTENT_TYPE) {
    throw new Error("invalid-content-type");
  }
  const size = positiveInteger(params.metadata.size);
  if (size == null) throw new Error("empty-image");
  if (size > MAX_CHAT_IMAGE_BYTES) throw new Error("image-too-large");

  const custom = params.metadata.metadata ?? {};
  if (trimmedString(custom.chatId) !== params.chatId) {
    throw new Error("chat-metadata-mismatch");
  }
  if (trimmedString(custom.messageId) !== params.messageId) {
    throw new Error("message-metadata-mismatch");
  }
  if (trimmedString(custom.senderId) !== params.senderId) {
    throw new Error("sender-metadata-mismatch");
  }
  return {size};
}

export function inspectJpegDimensions(bytes: Uint8Array): ChatImageDimensions {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) {
    throw new Error("invalid-jpeg");
  }

  let offset = 2;
  while (offset < bytes.length) {
    while (offset < bytes.length && bytes[offset] !== 0xff) offset += 1;
    while (offset < bytes.length && bytes[offset] === 0xff) offset += 1;
    if (offset >= bytes.length) break;

    const marker = bytes[offset];
    offset += 1;
    if (marker === 0xd8 || marker === 0xd9 || marker === 0x01 ||
        (marker >= 0xd0 && marker <= 0xd7)) {
      continue;
    }
    if (offset + 1 >= bytes.length) throw new Error("invalid-jpeg");
    const segmentLength = (bytes[offset] << 8) | bytes[offset + 1];
    if (segmentLength < 2 || offset + segmentLength > bytes.length) {
      throw new Error("invalid-jpeg");
    }

    if (JPEG_START_OF_FRAME_MARKERS.has(marker)) {
      if (segmentLength < 7) throw new Error("invalid-jpeg");
      const height = (bytes[offset + 3] << 8) | bytes[offset + 4];
      const width = (bytes[offset + 5] << 8) | bytes[offset + 6];
      if (width <= 0 || height <= 0) throw new Error("invalid-dimensions");
      if (width > MAX_CHAT_IMAGE_EDGE || height > MAX_CHAT_IMAGE_EDGE) {
        throw new Error("image-dimensions-too-large");
      }
      return {width, height};
    }

    offset += segmentLength;
  }
  throw new Error("jpeg-dimensions-missing");
}

export function isIdenticalCommittedImageMessage(params: {
  message: ExistingImageMessage;
  senderId: string;
  receiverId: string;
  storagePath: string;
}): boolean {
  const message = params.message;
  return trimmedString(message.type) === "image" &&
    trimmedString(message.senderId) === params.senderId &&
    trimmedString(message.receiverId) === params.receiverId &&
    trimmedString(message.storagePath) === params.storagePath &&
    trimmedString(message.mimeType).toLowerCase() === CHAT_IMAGE_CONTENT_TYPE &&
    positiveInteger(message.imageWidth) != null &&
    positiveInteger(message.imageHeight) != null &&
    positiveInteger(message.imageSizeBytes) != null &&
    Number(message.mediaSchemaVersion) === CHAT_IMAGE_MEDIA_SCHEMA_VERSION;
}

export function allActiveDevicesSupportChatImages(
  tokenDocuments: Array<Record<string, unknown>>,
): boolean {
  const active = tokenDocuments.filter((token) => token.disabled !== true);
  return active.length > 0 && active.every((token) => token[CHAT_IMAGE_CAPABILITY] === true);
}

export function anyActiveDeviceSupportsChatImages(
  tokenDocuments: Array<Record<string, unknown>>,
): boolean {
  return tokenDocuments.some(
    (token) => token.disabled !== true && token[CHAT_IMAGE_CAPABILITY] === true,
  );
}

export function parseChatImageTesterUids(value: string): ReadonlySet<string> {
  return new Set(
    value
      .split(",")
      .map((uid) => uid.trim())
      .filter((uid) => uid.length > 0),
  );
}

export function canAccountUseChatImageMessaging(params: {
  publicEnabled: boolean;
  testerUids: ReadonlySet<string>;
  uid: string;
}): boolean {
  return params.publicEnabled || params.testerUids.has(params.uid);
}
