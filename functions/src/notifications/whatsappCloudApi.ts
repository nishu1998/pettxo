import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";

import {loadAdminActor} from "../booking/bookingAdminOperationsV3";
import {db} from "../shared/firebase";

const WHATSAPP_ACCESS_TOKEN = defineSecret("WHATSAPP_ACCESS_TOKEN");
const WHATSAPP_PHONE_NUMBER_ID = defineSecret("WHATSAPP_PHONE_NUMBER_ID");
const WHATSAPP_GRAPH_API_VERSION = defineSecret("WHATSAPP_GRAPH_API_VERSION");

export type SendWhatsAppTemplateParams = {
  recipientPhoneE164: string;
  templateName: string;
  languageCode: string;
  bodyParameters?: string[];
};

export type WhatsAppTemplatePayload = {
  messaging_product: "whatsapp";
  to: string;
  type: "template";
  template: {
    name: string;
    language: {
      code: string;
    };
    components?: Array<{
      type: "body";
      parameters: Array<{
        type: "text";
        text: string;
      }>;
    }>;
  };
};

export type SendWhatsAppTemplateResult = {
  provider: "meta_cloud_api";
  providerMessageId: string;
};

type WhatsAppCloudApiConfig = {
  accessToken: string;
  phoneNumberId: string;
  graphApiVersion: string;
};

type FetchLike = typeof fetch;

type MetaErrorPayload = {
  error?: {
    message?: unknown;
    type?: unknown;
    code?: unknown;
    error_subcode?: unknown;
    fbtrace_id?: unknown;
  };
  messages?: Array<{
    id?: unknown;
  }>;
};

type SendWhatsAppTemplateDeps = {
  fetchImpl?: FetchLike;
  config?: WhatsAppCloudApiConfig;
};

type SendTestWhatsAppTemplateResponse = {
  accepted: true;
  provider: "meta_cloud_api";
  providerMessageId: string;
};

type SendTestWhatsAppTemplateDeps = SendWhatsAppTemplateDeps & {
  loadAdminActorImpl?: typeof loadAdminActor;
};

export class WhatsAppTransportError extends Error {
  readonly safeDetails: {
    status: number;
    errorType: string;
    errorCode: string;
    errorSubcode: string;
    correlationId: string;
  };

  constructor(message: string, safeDetails: WhatsAppTransportError["safeDetails"]) {
    super(message);
    this.name = "WhatsAppTransportError";
    this.safeDetails = safeDetails;
  }
}

function asTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asDisplayString(value: unknown): string {
  if (typeof value === "string") return value.trim();
  if (typeof value === "number" && Number.isFinite(value)) {
    return String(value);
  }
  return "";
}

function asRecord(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value != null && !Array.isArray(value) ?
    value as Record<string, unknown> :
    {};
}

function requireSecretValue(secretName: string, value: string): string {
  const trimmed = value.trim();
  if (!trimmed) {
    throw new HttpsError("failed-precondition", `${secretName} is not configured.`);
  }
  return trimmed;
}

export function validateRecipientPhoneE164(recipientPhoneE164: string): string {
  const normalized = recipientPhoneE164.trim();
  if (!/^\+\d{8,15}$/.test(normalized)) {
    throw new HttpsError("invalid-argument", "recipientPhoneE164 must be a valid E.164 number.");
  }
  return normalized;
}

export function normalizeRecipientForMeta(recipientPhoneE164: string): string {
  return validateRecipientPhoneE164(recipientPhoneE164).slice(1);
}

export function validateTemplateName(templateName: string): string {
  const normalized = templateName.trim();
  if (!/^[a-z0-9_]+$/.test(normalized)) {
    throw new HttpsError("invalid-argument", "templateName must use approved Meta template naming.");
  }
  return normalized;
}

export function validateLanguageCode(languageCode: string): string {
  const normalized = languageCode.trim();
  if (!/^[a-z]{2}(?:_[A-Z]{2})?$/.test(normalized)) {
    throw new HttpsError("invalid-argument", "languageCode must be a valid Meta template language code.");
  }
  return normalized;
}

export function normalizeBodyParameters(bodyParameters: unknown): string[] {
  if (bodyParameters == null) return [];
  if (!Array.isArray(bodyParameters)) {
    throw new HttpsError("invalid-argument", "bodyParameters must be an array of strings.");
  }
  return bodyParameters.map((value) => {
    if (typeof value !== "string") {
      throw new HttpsError("invalid-argument", "bodyParameters must contain only strings.");
    }
    return value;
  });
}

export function buildWhatsAppTemplatePayload(
  params: SendWhatsAppTemplateParams,
): WhatsAppTemplatePayload {
  const to = normalizeRecipientForMeta(params.recipientPhoneE164);
  const templateName = validateTemplateName(params.templateName);
  const languageCode = validateLanguageCode(params.languageCode);
  const bodyParameters = normalizeBodyParameters(params.bodyParameters);

  const payload: WhatsAppTemplatePayload = {
    messaging_product: "whatsapp",
    to,
    type: "template",
    template: {
      name: templateName,
      language: {
        code: languageCode,
      },
    },
  };

  if (bodyParameters.length > 0) {
    payload.template.components = [{
      type: "body",
      parameters: bodyParameters.map((value) => ({
        type: "text",
        text: value,
      })),
    }];
  }

  return payload;
}

export function maskPhoneForLogs(recipientPhoneE164: string): string {
  const normalized = asTrimmedString(recipientPhoneE164);
  if (normalized.length <= 5) return "+****";
  const visiblePrefix = normalized.slice(0, 3);
  const visibleSuffix = normalized.slice(-4);
  const maskedLength = Math.max(normalized.length - visiblePrefix.length - visibleSuffix.length, 2);
  return `${visiblePrefix}${"*".repeat(maskedLength)}${visibleSuffix}`;
}

function getWhatsAppCloudApiConfigFromSecrets(): WhatsAppCloudApiConfig {
  return {
    accessToken: requireSecretValue(
      "WHATSAPP_ACCESS_TOKEN",
      WHATSAPP_ACCESS_TOKEN.value(),
    ),
    phoneNumberId: requireSecretValue(
      "WHATSAPP_PHONE_NUMBER_ID",
      WHATSAPP_PHONE_NUMBER_ID.value(),
    ),
    graphApiVersion: requireSecretValue(
      "WHATSAPP_GRAPH_API_VERSION",
      WHATSAPP_GRAPH_API_VERSION.value(),
    ),
  };
}

function buildGraphApiUrl(config: WhatsAppCloudApiConfig): string {
  const graphApiVersion = config.graphApiVersion.trim();
  if (!/^v\d+(?:\.\d+)?$/.test(graphApiVersion)) {
    throw new HttpsError("failed-precondition", "WHATSAPP_GRAPH_API_VERSION is invalid.");
  }
  const phoneNumberId = requireSecretValue("WHATSAPP_PHONE_NUMBER_ID", config.phoneNumberId);
  return `https://graph.facebook.com/${graphApiVersion}/${phoneNumberId}/messages`;
}

function sanitizeMetaError(
  status: number,
  payload: MetaErrorPayload,
  correlationId: string,
): WhatsAppTransportError {
  const errorRecord = asRecord(payload.error);
  return new WhatsAppTransportError("Meta WhatsApp template send failed.", {
    status,
    errorType: asDisplayString(errorRecord.type),
    errorCode: asDisplayString(errorRecord.code),
    errorSubcode: asDisplayString(errorRecord.error_subcode),
    correlationId: asDisplayString(errorRecord.fbtrace_id) || correlationId,
  });
}

function safeParseMetaResponse(responseText: string): MetaErrorPayload {
  if (!responseText) return {};
  try {
    return JSON.parse(responseText) as MetaErrorPayload;
  } catch {
    return {};
  }
}

export async function sendWhatsAppTemplate(
  params: SendWhatsAppTemplateParams,
  deps: SendWhatsAppTemplateDeps = {},
): Promise<SendWhatsAppTemplateResult> {
  const fetchImpl = deps.fetchImpl ?? fetch;
  const config = deps.config ?? getWhatsAppCloudApiConfigFromSecrets();
  const payload = buildWhatsAppTemplatePayload(params);
  const url = buildGraphApiUrl(config);
  const maskedPhone = maskPhoneForLogs(params.recipientPhoneE164);
  let response: Response;
  try {
    response = await fetchImpl(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${requireSecretValue("WHATSAPP_ACCESS_TOKEN", config.accessToken)}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });
  } catch {
    const error = new WhatsAppTransportError("Meta WhatsApp template send failed.", {
      status: 0,
      errorType: "FETCH_FAILED",
      errorCode: "",
      errorSubcode: "",
      correlationId: "",
    });
    console.error("WhatsApp template send failed", {
      maskedPhone,
      status: error.safeDetails.status,
      errorType: error.safeDetails.errorType,
      errorCode: error.safeDetails.errorCode,
      errorSubcode: error.safeDetails.errorSubcode,
      correlationId: error.safeDetails.correlationId,
    });
    throw error;
  }

  const responseText = await response.text();
  const responseBody = safeParseMetaResponse(responseText);
  const correlationId =
    response.headers.get("x-fb-trace-id") ??
    response.headers.get("x-fb-request-id") ??
    "";

  if (!response.ok) {
    const error = sanitizeMetaError(response.status, responseBody, correlationId);
    console.error("WhatsApp template send failed", {
      maskedPhone,
      status: error.safeDetails.status,
      errorType: error.safeDetails.errorType,
      errorCode: error.safeDetails.errorCode,
      errorSubcode: error.safeDetails.errorSubcode,
      correlationId: error.safeDetails.correlationId,
    });
    throw error;
  }

  const providerMessageId = asTrimmedString(responseBody.messages?.[0]?.id);
  if (!providerMessageId) {
    const error = new WhatsAppTransportError(
      "Meta WhatsApp template response did not include a message ID.",
      {
        status: response.status,
        errorType: "",
        errorCode: "",
        errorSubcode: "",
        correlationId,
      },
    );
    console.error("WhatsApp template send failed", {
      maskedPhone,
      status: error.safeDetails.status,
      errorType: error.safeDetails.errorType,
      errorCode: error.safeDetails.errorCode,
      errorSubcode: error.safeDetails.errorSubcode,
      correlationId: error.safeDetails.correlationId,
    });
    throw error;
  }

  console.info("WhatsApp template accepted", {
    maskedPhone,
    templateName: payload.template.name,
    languageCode: payload.template.language.code,
    providerMessageId,
  });

  return {
    provider: "meta_cloud_api",
    providerMessageId,
  };
}

export async function sendTestWhatsAppTemplateHandler(
  request: CallableRequest<unknown>,
  deps: SendTestWhatsAppTemplateDeps = {},
): Promise<SendTestWhatsAppTemplateResponse> {
  await (deps.loadAdminActorImpl ?? loadAdminActor)(db, request.auth, "dispute_nonfinancial");

  const data = asRecord(request.data);
  const result = await sendWhatsAppTemplate({
    recipientPhoneE164: asTrimmedString(data.recipientPhoneE164),
    templateName: asTrimmedString(data.templateName),
    languageCode: asTrimmedString(data.languageCode),
    bodyParameters: data.bodyParameters as string[] | undefined,
  }, deps);

  return {
    accepted: true,
    provider: result.provider,
    providerMessageId: result.providerMessageId,
  };
}

export const sendTestWhatsAppTemplate = onCall(
  {
    invoker: "private",
    secrets: [
      WHATSAPP_ACCESS_TOKEN,
      WHATSAPP_PHONE_NUMBER_ID,
      WHATSAPP_GRAPH_API_VERSION,
    ],
  },
  async (request) => sendTestWhatsAppTemplateHandler(request),
);
