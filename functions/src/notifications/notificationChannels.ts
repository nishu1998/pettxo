export const notificationChannelOrder = [
  "in_app",
  "push",
  "whatsapp",
] as const;

export type NotificationChannel = typeof notificationChannelOrder[number];

const notificationChannelSet = new Set<NotificationChannel>(
  notificationChannelOrder,
);

export function isNotificationChannel(value: unknown): value is NotificationChannel {
  return typeof value === "string" &&
    notificationChannelSet.has(value as NotificationChannel);
}

export function normalizeNotificationChannels(
  channels: ReadonlyArray<unknown> | null | undefined,
): NotificationChannel[] {
  if (!Array.isArray(channels) || channels.length === 0) return [];
  return notificationChannelOrder.filter((channel) => channels.includes(channel));
}

export function parseStoredNotificationChannels(
  channels: unknown,
): NotificationChannel[] | null {
  if (channels == null) return null;
  if (!Array.isArray(channels)) return [];
  return normalizeNotificationChannels(channels);
}

export function notificationSupportsChannel(
  channels: unknown,
  channel: NotificationChannel,
): boolean {
  const normalized = parseStoredNotificationChannels(channels);
  if (normalized == null) {
    return channel === "in_app" || channel === "push";
  }
  return normalized.includes(channel);
}

export function notificationVisibleInApp(channels: unknown): boolean {
  return notificationSupportsChannel(channels, "in_app");
}

export function notificationDeliversPush(channels: unknown): boolean {
  return notificationSupportsChannel(channels, "push");
}

export function buildStoredBookingNotificationDocument(params: {
  notification: {
    recipientUserId: string;
    type: string;
    title: string;
    body: string;
    channels: ReadonlyArray<unknown> | null | undefined;
    data: Record<string, string>;
  };
  actorId: string;
  createdAt: unknown;
  updatedAt: unknown;
  source: string;
}): Record<string, unknown> {
  const channels = normalizeNotificationChannels(params.notification.channels);
  return {
    userId: params.notification.recipientUserId,
    category: "booking",
    type: params.notification.type,
    title: params.notification.title,
    body: params.notification.body,
    read: false,
    isRead: false,
    actorId: params.actorId,
    bookingId: params.notification.data.bookingId ?? "",
    serviceId: params.notification.data.serviceId ?? "",
    recipientRole: params.notification.data.recipientRole ?? "",
    data: params.notification.data,
    channels,
    visibleInApp: channels.includes("in_app"),
    createdAt: params.createdAt,
    updatedAt: params.updatedAt,
    source: params.source,
  };
}

export function buildStoredPromotionalNotificationDocument(params: {
  recipientUserId: string;
  broadcastId: string;
  title: string;
  body: string;
  createdAt: unknown;
  updatedAt: unknown;
  source: string;
}): Record<string, unknown> {
  const channels = normalizeNotificationChannels(["in_app", "push"]);
  const data = {
    category: "promotion",
    type: "promotionalBroadcast",
    broadcastId: params.broadcastId,
  };

  return {
    userId: params.recipientUserId,
    category: "promotion",
    type: "promotionalBroadcast",
    title: params.title,
    body: params.body,
    read: false,
    isRead: false,
    data,
    channels,
    visibleInApp: true,
    broadcastId: params.broadcastId,
    createdAt: params.createdAt,
    updatedAt: params.updatedAt,
    source: params.source,
  };
}
