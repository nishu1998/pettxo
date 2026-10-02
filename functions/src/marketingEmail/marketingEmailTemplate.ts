import {escapeMarketingHtml, type MarketingContent} from "./marketingEmailDomain";

export function renderMarketingEmail(params: {
  content: MarketingContent;
  unsubscribeUrl: string;
  testMode?: boolean;
}): string {
  const c = params.content;
  const body = escapeMarketingHtml(c.body).replace(/\r?\n/g, "<br>");
  const image = c.imageUrl ? `<img src="${escapeMarketingHtml(c.imageUrl)}" alt="" width="600" style="display:block;width:100%;height:auto;border:0;border-radius:20px;margin:0 0 28px">` : "";
  const cta = c.ctaText ? `<p style="margin:30px 0;text-align:center"><a href="${escapeMarketingHtml(c.ctaDestination)}" style="display:inline-block;background:#F47B35;color:#fff;text-decoration:none;font-weight:700;padding:14px 24px;border-radius:14px">${escapeMarketingHtml(c.ctaText)}</a></p>` : "";
  const test = params.testMode ? `<div style="background:#FFF3E9;color:#9A4B1F;padding:10px 18px;text-align:center;font-size:13px;font-weight:700">TEST EMAIL — no campaign delivery state was changed</div>` : "";
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="margin:0;background:#FBF6EF;font-family:Arial,sans-serif;color:#302B27"><span style="display:none!important;max-height:0;overflow:hidden;opacity:0">${escapeMarketingHtml(c.preheader)}</span><table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#FBF6EF"><tr><td align="center" style="padding:28px 12px"><table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:600px;background:#fff;border-radius:28px;overflow:hidden"><tr><td>${test}</td></tr><tr><td style="padding:34px 34px 10px"><div style="font-size:26px;font-weight:800;color:#F47B35;margin-bottom:28px">Pettxo</div>${image}<h1 style="font-size:28px;line-height:1.2;margin:0 0 18px">${escapeMarketingHtml(c.heading)}</h1><div style="font-size:16px;line-height:1.65;color:#5D554E">${body}</div>${cta}</td></tr><tr><td style="padding:24px 34px 32px;border-top:1px solid #F1E8DF;font-size:12px;line-height:1.6;color:#81776E">You received this because you opted in to Pettxo offers and updates. Essential account and service emails are unaffected.<br><a href="${escapeMarketingHtml(params.unsubscribeUrl)}" style="color:#6E6259">Unsubscribe from marketing emails</a></td></tr></table></td></tr></table></body></html>`;
}
