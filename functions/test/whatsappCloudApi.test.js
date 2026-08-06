const test = require("node:test");
const assert = require("node:assert/strict");

const {HttpsError} = require("firebase-functions/v2/https");
const {
  buildWhatsAppTemplatePayload,
  maskPhoneForLogs,
  normalizeRecipientForMeta,
  sendTestWhatsAppTemplateHandler,
  sendWhatsAppTemplate,
  validateLanguageCode,
  validateRecipientPhoneE164,
  validateTemplateName,
} = require("../lib/notifications/whatsappCloudApi.js");

function config() {
  return {
    accessToken: "secret-token",
    phoneNumberId: "1234567890",
    graphApiVersion: "v22.0",
  };
}

function captureConsole(methodName) {
  const original = console[methodName];
  const calls = [];
  console[methodName] = (...args) => {
    calls.push(args);
  };
  return {
    calls,
    restore() {
      console[methodName] = original;
    },
  };
}

test("phone validation accepts valid Indian E.164", () => {
  assert.equal(validateRecipientPhoneE164("+919876543210"), "+919876543210");
  assert.equal(normalizeRecipientForMeta("+919876543210"), "919876543210");
});

test("phone validation accepts valid non-Indian E.164", () => {
  assert.equal(validateRecipientPhoneE164("+14155552671"), "+14155552671");
  assert.equal(normalizeRecipientForMeta("+14155552671"), "14155552671");
});

test("phone validation rejects missing plus", () => {
  assert.throws(
    () => validateRecipientPhoneE164("919876543210"),
    /recipientPhoneE164 must be a valid E\.164 number\./,
  );
});

test("phone validation rejects letters", () => {
  assert.throws(
    () => validateRecipientPhoneE164("+91ABC765432"),
    /recipientPhoneE164 must be a valid E\.164 number\./,
  );
});

test("phone validation rejects spaces", () => {
  assert.throws(
    () => validateRecipientPhoneE164("+91 9876543210"),
    /recipientPhoneE164 must be a valid E\.164 number\./,
  );
});

test("phone validation rejects too short numbers", () => {
  assert.throws(
    () => validateRecipientPhoneE164("+1234567"),
    /recipientPhoneE164 must be a valid E\.164 number\./,
  );
});

test("phone validation rejects too long numbers", () => {
  assert.throws(
    () => validateRecipientPhoneE164("+1234567890123456"),
    /recipientPhoneE164 must be a valid E\.164 number\./,
  );
});

test("template and language validation reject malformed values", () => {
  assert.equal(validateTemplateName("hello_world"), "hello_world");
  assert.equal(validateLanguageCode("en_US"), "en_US");
  assert.throws(() => validateTemplateName("HelloWorld"), /templateName must use approved Meta template naming\./);
  assert.throws(() => validateLanguageCode("english"), /languageCode must be a valid Meta template language code\./);
});

test("payload construction omits components when no parameters exist", () => {
  const payload = buildWhatsAppTemplatePayload({
    recipientPhoneE164: "+919876543210",
    templateName: "hello_world",
    languageCode: "en_US",
  });

  assert.equal(payload.to, "919876543210");
  assert.equal(payload.template.name, "hello_world");
  assert.equal(payload.template.language.code, "en_US");
  assert.equal("components" in payload.template, false);
});

test("payload construction supports one body parameter", () => {
  const payload = buildWhatsAppTemplatePayload({
    recipientPhoneE164: "+919876543210",
    templateName: "hello_world",
    languageCode: "en_US",
    bodyParameters: ["Nisha"],
  });

  assert.deepEqual(payload.template.components, [{
    type: "body",
    parameters: [{type: "text", text: "Nisha"}],
  }]);
});

test("payload construction supports multiple body parameters", () => {
  const payload = buildWhatsAppTemplatePayload({
    recipientPhoneE164: "+14155552671",
    templateName: "hello_world",
    languageCode: "en_US",
    bodyParameters: ["Rishi", "Tomorrow", "9:00 AM"],
  });

  assert.deepEqual(
    payload.template.components[0].parameters.map((parameter) => parameter.text),
    ["Rishi", "Tomorrow", "9:00 AM"],
  );
});

test("successful transport request uses the Graph API template endpoint and returns the provider message id", async () => {
  const requests = [];
  const result = await sendWhatsAppTemplate({
    recipientPhoneE164: "+919876543210",
    templateName: "hello_world",
    languageCode: "en_US",
    bodyParameters: ["Rishi"],
  }, {
    config: config(),
    fetchImpl: async (url, init) => {
      requests.push({url, init});
      return {
        ok: true,
        status: 200,
        headers: new Headers(),
        text: async () => JSON.stringify({messages: [{id: "wamid.test-123"}]}),
      };
    },
  });

  assert.equal(requests.length, 1);
  assert.equal(requests[0].url, "https://graph.facebook.com/v22.0/1234567890/messages");
  assert.equal(requests[0].init.method, "POST");
  assert.equal(requests[0].init.headers.Authorization, "Bearer secret-token");
  assert.equal(requests[0].init.headers["Content-Type"], "application/json");
  const body = JSON.parse(requests[0].init.body);
  assert.equal(body.to, "919876543210");
  assert.equal(result.provider, "meta_cloud_api");
  assert.equal(result.providerMessageId, "wamid.test-123");
});

test("transport safely sanitizes Meta API errors", async () => {
  const errorLogs = captureConsole("error");
  try {
    await assert.rejects(
      () => sendWhatsAppTemplate({
        recipientPhoneE164: "+919876543210",
        templateName: "hello_world",
        languageCode: "en_US",
      }, {
        config: config(),
        fetchImpl: async () => ({
          ok: false,
          status: 400,
          headers: new Headers({"x-fb-trace-id": "trace-123"}),
          text: async () => JSON.stringify({
            error: {
              message: "Invalid token",
              type: "OAuthException",
              code: 190,
              error_subcode: 123456,
            },
          }),
        }),
      }),
      (error) => {
        assert.equal(error.name, "WhatsAppTransportError");
        assert.equal(error.message.includes("secret-token"), false);
        assert.equal(error.safeDetails.status, 400);
        assert.equal(error.safeDetails.errorType, "OAuthException");
        assert.equal(error.safeDetails.errorCode, "190");
        assert.equal(error.safeDetails.errorSubcode, "123456");
        assert.equal(error.safeDetails.correlationId, "trace-123");
        return true;
      },
    );
  } finally {
    errorLogs.restore();
  }

  const joinedLogs = JSON.stringify(errorLogs.calls);
  assert.equal(joinedLogs.includes("secret-token"), false);
  assert.equal(joinedLogs.includes("+919876543210"), false);
  assert.equal(joinedLogs.includes(maskPhoneForLogs("+919876543210")), true);
});

test("transport safely fails when fetch throws", async () => {
  await assert.rejects(
    () => sendWhatsAppTemplate({
      recipientPhoneE164: "+919876543210",
      templateName: "hello_world",
      languageCode: "en_US",
    }, {
      config: config(),
      fetchImpl: async () => {
        throw new Error("network down");
      },
    }),
    (error) => {
      assert.equal(error.name, "WhatsAppTransportError");
      assert.equal(error.safeDetails.status, 0);
      assert.equal(error.safeDetails.errorType, "FETCH_FAILED");
      return true;
    },
  );
});

test("callable rejects unauthenticated requests", async () => {
  await assert.rejects(
    () => sendTestWhatsAppTemplateHandler({
      auth: null,
      data: {},
    }, {
      loadAdminActorImpl: async () => {
        throw new HttpsError("unauthenticated", "Sign in required.");
      },
    }),
    (error) => error instanceof HttpsError && error.code === "unauthenticated",
  );
});

test("callable rejects unauthorized users", async () => {
  await assert.rejects(
    () => sendTestWhatsAppTemplateHandler({
      auth: {uid: "user-1"},
      data: {},
    }, {
      loadAdminActorImpl: async () => {
        throw new HttpsError("permission-denied", "Admin access required.");
      },
    }),
    (error) => error instanceof HttpsError && error.code === "permission-denied",
  );
});

test("authorized callable sends the template through the isolated transport", async () => {
  const result = await sendTestWhatsAppTemplateHandler({
    auth: {uid: "admin-1"},
    data: {
      recipientPhoneE164: "+919876543210",
      templateName: "hello_world",
      languageCode: "en_US",
      bodyParameters: ["Nisha"],
    },
  }, {
    loadAdminActorImpl: async () => ({
      uid: "admin-1",
      role: "superAdmin",
      canViewFinancials: true,
    }),
    config: config(),
    fetchImpl: async () => ({
      ok: true,
      status: 200,
      headers: new Headers(),
      text: async () => JSON.stringify({messages: [{id: "wamid.callable-1"}]}),
    }),
  });

  assert.deepEqual(result, {
    accepted: true,
    provider: "meta_cloud_api",
    providerMessageId: "wamid.callable-1",
  });
});
