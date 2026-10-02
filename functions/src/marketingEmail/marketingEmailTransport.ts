interface MarketingResendClient {
  emails: {send(message: {from: string; replyTo: string; to: string[]; subject: string; html: string; headers?: Record<string, string>}, options?: {idempotencyKey?: string}): Promise<{data?: {id?: string}; error?: unknown}>};
}
interface MarketingResendConstructor {new(apiKey: string): MarketingResendClient}
const {Resend} = require("resend") as {Resend: MarketingResendConstructor};

export const marketingEmailFrom = "Pettxo <updates@updates.pettxo.com>";
export const marketingEmailReplyTo = "hello@pettxo.com";

export async function sendMarketingEmail(apiKey: string, message: {to: string; subject: string; html: string; unsubscribeUrl: string}, idempotencyKey: string): Promise<string> {
  const result = await new Resend(apiKey).emails.send({
    from: marketingEmailFrom,
    replyTo: marketingEmailReplyTo,
    to: [message.to],
    subject: message.subject,
    html: message.html,
    headers: {
      "List-Unsubscribe": `<${message.unsubscribeUrl}>`,
      "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
    },
  }, {idempotencyKey});
  if (result.error) throw new Error("Marketing email provider rejected the message.");
  return result.data?.id ?? "";
}
