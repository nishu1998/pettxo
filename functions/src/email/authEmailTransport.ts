interface ResendClient {
  emails: {
    send(message: {
      from: string;
      replyTo: string;
      to: string[];
      subject: string;
      html: string;
    }, options?: {idempotencyKey?: string}): Promise<{error?: unknown}>;
  };
}

interface ResendConstructor {
  new (apiKey: string): ResendClient;
}

// Resend's public declarations include optional React template types. Pettxo
// sends approved raw HTML, so keep this transport typed to that smaller API.
const {Resend} = require("resend") as {Resend: ResendConstructor};

export const authEmailFrom = "Pettxo <no-reply@pettxo.com>";
export const authEmailReplyTo = "hello@pettxo.com";

export interface AuthEmailMessage {
  to: string;
  subject: string;
  html: string;
}

export interface AuthEmailSendOptions {
  idempotencyKey?: string;
}

export async function sendAuthEmail(
  apiKey: string,
  message: AuthEmailMessage,
  options: AuthEmailSendOptions = {},
): Promise<void> {
  const resend = new Resend(apiKey);
  const result = await resend.emails.send(
    {
      from: authEmailFrom,
      replyTo: authEmailReplyTo,
      to: [message.to],
      subject: message.subject,
      html: message.html,
    },
    options.idempotencyKey ?
      {idempotencyKey: options.idempotencyKey} :
      undefined,
  );

  if (result.error) {
    throw new Error("Transactional email provider rejected the message.");
  }
}
