const test = require("node:test");
const assert = require("node:assert/strict");

const bookingNotifications = require(
  "../lib/booking/application/bookingNotificationsV3.js",
);
const {
  buildSocialNotificationCopy,
  socialNotificationDocumentId,
} = require("../lib/legacyFunctions.js");

const bookingBase = {
  bookingId: "booking-1",
  parentId: "parent-1",
  providerId: "provider-1",
  bookingType: "SLOT",
  state: "CONFIRMED",
};

test("major booking lifecycle notifications use compact user-facing copy", () => {
  const providerRequest =
    bookingNotifications.buildProviderActionRequiredNotification({
      ...bookingBase,
      serviceName: "Very Good Dog Walking",
    });
  assert.equal(providerRequest.title, "New booking request");
  assert.equal(
    providerRequest.body,
    "Very Good Dog Walking. Respond before the request expires.",
  );

  const accepted = bookingNotifications.buildPaymentRequiredNotification(
    bookingBase,
  );
  assert.equal(accepted.title, "Request accepted");
  assert.equal(
    accepted.body,
    "Complete payment within 60 minutes to confirm availability.",
  );

  const [paymentReady] =
    bookingNotifications.buildPaymentOrderReadyNotification(bookingBase);
  assert.equal(paymentReady.title, "Payment ready");
  assert.equal(
    paymentReady.body,
    "Complete payment before the payment window ends.",
  );

  const confirmed = bookingNotifications.buildBookingConfirmedNotification({
    ...bookingBase,
    serviceName: "Very Good Dog Walking",
  });
  assert.deepEqual(
    confirmed.map(({title, body}) => ({title, body})),
    [
      {
        title: "Booking confirmed",
        body: "OTP, contact, and chat are available in booking details.",
      },
      {
        title: "Booking confirmed",
        body: "Payment successful for Very Good Dog Walking.",
      },
    ],
  );

  const [customerNoShow, providerNoShow] =
    bookingNotifications.buildBookingNoShowNotifications(bookingBase);
  assert.equal(customerNoShow.title, "Booking marked no-show");
  assert.equal(
    customerNoShow.body,
    "The service OTP was not entered before the service window ended.",
  );
  assert.equal(providerNoShow.body, customerNoShow.body);

  const [completed] =
    bookingNotifications.buildServiceCompletedNotification(bookingBase);
  assert.equal(completed.title, "Service completed");
  assert.equal(
    completed.body,
    "Review your experience or raise a dispute within 24 hours.",
  );

  const dispute =
    bookingNotifications.buildBookingDisputeOpenedNotification(bookingBase);
  assert.equal(dispute.title, "Booking dispute opened");
  assert.equal(
    dispute.body,
    "Settlement is on hold while Pettxo reviews the case.",
  );
});

test("booking notification identities remain deterministic by event and recipient", () => {
  const first = bookingNotifications.buildBookingConfirmedNotification({
    ...bookingBase,
    serviceName: "Dog Walking",
  });
  const replay = bookingNotifications.buildBookingConfirmedNotification({
    ...bookingBase,
    serviceName: "Dog Walking",
  });

  assert.deepEqual(
    replay.map((notification) => notification.idempotencyKey),
    first.map((notification) => notification.idempotencyKey),
  );
  assert.notEqual(first[0].idempotencyKey, first[1].idempotencyKey);
});

test("social copy stays compact and preserves comment context", () => {
  assert.deepEqual(
    buildSocialNotificationCopy({
      type: "socialFollow",
      senderDisplayName: "Vedant",
    }),
    {title: "Vedant followed you", body: ""},
  );
  assert.deepEqual(
    buildSocialNotificationCopy({
      type: "socialLike",
      senderDisplayName: "Tanmay",
    }),
    {title: "Tanmay liked your post", body: ""},
  );
  assert.deepEqual(
    buildSocialNotificationCopy({
      type: "socialComment",
      senderDisplayName: "Aarav",
      commentText: "Such a happy dog!",
    }),
    {
      title: "Aarav commented on your post",
      body: "Such a happy dog!",
    },
  );
});

test("social notification identities deduplicate retries but retain new events", () => {
  const input = {
    type: "socialLike",
    senderId: "sender-1",
    recipientId: "recipient-1",
    sourceEventId: "post-1:1720000000000",
  };
  const first = socialNotificationDocumentId(input);
  const replay = socialNotificationDocumentId(input);
  const laterLike = socialNotificationDocumentId({
    ...input,
    sourceEventId: "post-1:1720000001000",
  });

  assert.equal(replay, first);
  assert.notEqual(laterLike, first);
});
