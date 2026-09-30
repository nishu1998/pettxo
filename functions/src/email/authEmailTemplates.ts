export const verificationEmailSubject = "Verify your email for Pettxo";
export const passwordResetEmailSubject = "Reset your Pettxo password";
export const verificationEmailPreview =
  "One tap to confirm your email and secure your Pettxo account.";
export const passwordResetEmailPreview =
  "Use this link to choose a new password for your Pettxo account.";
export const welcomeEmailPreview = "Here's how to get started with Pettxo.";
export const welcomeEmailAppUrl = "https://pettxo.com/app";

export interface AuthEmailTemplateData {
  name?: string | null;
  email: string;
  actionLink: string;
}

export function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function safeGreetingName(value: string | null | undefined): string {
  const trimmed = typeof value === "string" ? value.trim() : "";
  return escapeHtml(trimmed || "there");
}

interface AuthEmailCopy {
  title: string;
  preview: string;
  heading: string;
  greetingName: string;
  body: string;
  accountLabel: string;
  email: string;
  actionLink: string;
  buttonLabel: string;
  safetyCopy: string;
}

function renderApprovedAuthEmail(copy: AuthEmailCopy): string {
  return `<!DOCTYPE html>
<html lang="en" xmlns="http://www.w3.org/1999/xhtml" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<meta name="x-apple-disable-message-reformatting">
<meta name="format-detection" content="telephone=no, date=no, address=no, email=no">
<meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark">
<title>${copy.title}</title>
<link href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;600;700&display=swap" rel="stylesheet">
<!--[if mso]>
<noscript><xml><o:OfficeDocumentSettings><o:PixelsPerInch>96</o:PixelsPerInch></o:OfficeDocumentSettings></xml></noscript>
<style>td,th,div,p,a,h1,h2,span{font-family:Arial,sans-serif !important;}</style>
<![endif]-->
<style>
  body,table,td,a{-webkit-text-size-adjust:100%;-ms-text-size-adjust:100%;}
  table,td{mso-table-lspace:0pt;mso-table-rspace:0pt;}
  body{margin:0 !important;padding:0 !important;width:100% !important;}
  a[x-apple-data-detectors]{color:inherit !important;text-decoration:none !important;}
  u + #body a{color:inherit;text-decoration:none;}
  @media only screen and (max-width:620px){
    .container{width:100% !important;}
    .px{padding-left:24px !important;padding-right:24px !important;}
    .h1{font-size:25px !important;line-height:32px !important;}
    .hero{font-size:32px !important;line-height:38px !important;}
    .btn-td{width:100% !important;}
    .btn-a{display:block !important;}
    .store{display:block !important;width:100% !important;padding:0 0 10px 0 !important;}
  }
  @media (prefers-color-scheme: dark){
    .bg-page{background-color:#161412 !important;}
    .bg-card{background-color:#1F2937 !important;}
    .bg-soft{background-color:#2B3442 !important;border-color:#374151 !important;}
    .t-body{color:#F9FAFB !important;}
    .t-muted{color:#D1D5DB !important;}
    .t-legal{color:#9CA3AF !important;}
    .line td{border-color:#374151 !important;}
  }
  [data-ogsc] .t-body{color:#F9FAFB !important;}
  [data-ogsc] .t-muted{color:#D1D5DB !important;}
</style>
</head>
<body id="body" class="bg-page" style="margin:0;padding:0;background-color:#F5EFE6;">

<div style="display:none;font-size:1px;line-height:1px;max-height:0;max-width:0;opacity:0;overflow:hidden;mso-hide:all;">${copy.preview}&#8203;&nbsp;&#8203;&nbsp;&#8203;&nbsp;&#8203;&nbsp;&#8203;&nbsp;&#8203;&nbsp;&#8203;&nbsp;&#8203;&nbsp;&#8203;&nbsp;&#8203;&nbsp;&#8203;&nbsp;&#8203;&nbsp;</div>

<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" class="bg-page" style="background-color:#F5EFE6;">
<tr><td align="center" style="padding:32px 12px 24px 12px;">
<!--[if mso]><table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0"><tr><td><![endif]-->
<table role="presentation" class="container" width="600" cellpadding="0" cellspacing="0" border="0" style="width:600px;max-width:600px;">

  <!-- HEADER -->
  <tr>
    <td bgcolor="#F75927" class="px" style="background-color:#F75927;padding:30px 40px 28px 40px;border-radius:16px 16px 0 0;">
      <a href="https://pettxo.com" target="_blank" style="text-decoration:none;"><span style="font-family:Poppins,Arial,Helvetica,sans-serif;font-size:26px;line-height:30px;font-weight:700;letter-spacing:4px;color:#FFFFFF;">PETTXO</span></a>
      <div style="font-family:Poppins,Arial,Helvetica,sans-serif;font-size:14px;line-height:20px;color:#FFFFFF;padding-top:6px;">Where pets and people connect.</div>
    </td>
  </tr>

  <!-- CONTENT -->
  <tr>
    <td class="bg-card px" bgcolor="#FFFFFF" style="background-color:#FFFFFF;padding:44px 40px 40px 40px;">
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 16px 0;"><tr><td bgcolor="#FDF4EE" class="bg-soft" style="background-color:#FDF4EE;border:1px solid #F0E2D5;border-radius:20px;padding:5px 14px;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:13px;line-height:18px;font-weight:600;color:#F75927;">Account security</td></tr></table>
      <h1 class="h1 t-body" style="margin:0 0 16px 0;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:28px;line-height:35px;font-weight:700;color:#1F2937;">${copy.heading}</h1>
      <p class="t-body" style="margin:0 0 18px 0;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:16px;line-height:26px;color:#1F2937;">Hi ${copy.greetingName},</p>
      <p class="t-body" style="margin:0 0 10px 0;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:16px;line-height:26px;color:#1F2937;">${copy.body}</p>
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:6px 0 28px 0;"><tr>
        <td bgcolor="#FDF4EE" class="bg-soft" style="background-color:#FDF4EE;border:1px solid #F0E2D5;border-radius:10px;padding:14px 18px;">
          <p class="t-muted" style="margin:0 0 2px 0;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:12px;line-height:18px;color:#6B7280;">${copy.accountLabel}</p>
          <p class="t-body" style="margin:0;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:16px;line-height:22px;font-weight:600;color:#1F2937;word-break:break-all;">${copy.email}</p>
        </td></tr></table>
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 16px 0;"><tr>
        <td class="btn-td" align="center" bgcolor="#F75927" style="background-color:#F75927;border-radius:10px;">
          <!--[if mso]><v:roundrect xmlns:v="urn:schemas-microsoft-com:vml" href="${copy.actionLink}" style="height:52px;v-text-anchor:middle;width:260px;" arcsize="19%" stroke="f" fillcolor="#F75927"><w:anchorlock/><center style="color:#FFFFFF;font-family:Arial,sans-serif;font-size:16px;font-weight:bold;">${copy.buttonLabel}</center></v:roundrect><![endif]-->
          <!--[if !mso]><!--><a class="btn-a" href="${copy.actionLink}" target="_blank" style="display:inline-block;padding:16px 40px;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:16px;line-height:20px;font-weight:600;color:#FFFFFF;text-decoration:none;border-radius:10px;">${copy.buttonLabel}</a><!--<![endif]-->
        </td></tr></table>
      <p class="t-muted" style="margin:0 0 28px 0;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:13px;line-height:20px;color:#6B7280;">Button not working? Copy this link into your browser:<br><a href="${copy.actionLink}" style="color:#F75927;word-break:break-all;">${copy.actionLink}</a></p>
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 28px 0;"><tr>
        <td bgcolor="#FDF4EE" class="bg-soft t-body" style="background-color:#FDF4EE;border:1px solid #F0E2D5;border-radius:10px;padding:16px 18px;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:14px;line-height:22px;color:#1F2937;">${copy.safetyCopy}</td></tr></table>
      <p class="t-body" style="margin:0;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:16px;line-height:26px;color:#1F2937;">Team Pettxo</p>
    </td>
  </tr>

  <!-- FOOTER (orange) -->
  <tr>
    <td bgcolor="#F75927" class="px" style="background-color:#F75927;padding:24px 40px;border-radius:0 0 16px 16px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
        <td style="font-family:Poppins,Arial,Helvetica,sans-serif;font-size:15px;line-height:22px;color:#FFFFFF;">
          Need help? We're at <a href="mailto:hello@pettxo.com" style="color:#FFFFFF;font-weight:700;text-decoration:underline;">hello@pettxo.com</a>
        </td>
      </tr></table>
    </td>
  </tr>

  <!-- LEGAL (on beige, below the card) -->
  <tr>
    <td class="px" align="center" style="padding:24px 40px 8px 40px;">
      <p class="t-legal" style="margin:0 0 10px 0;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:12px;line-height:18px;color:#6B7280;">You're receiving this because this email address was used on Pettxo.</p>
      <p class="t-legal" style="margin:0 0 10px 0;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:12px;line-height:18px;color:#6B7280;">
        <a href="https://pettxo.com/terms" target="_blank" style="color:#6B7280;text-decoration:underline;">Terms</a>&nbsp;&nbsp;&nbsp;
        <a href="https://pettxo.com/privacy" target="_blank" style="color:#6B7280;text-decoration:underline;">Privacy</a>&nbsp;&nbsp;&nbsp;
        <a href="https://pettxo.com/refund-policy" target="_blank" style="color:#6B7280;text-decoration:underline;">Refunds</a>
      </p>
      <p class="t-legal" style="margin:0;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:12px;line-height:18px;color:#9CA3AF;">Pettxo Private Limited&nbsp;&nbsp;|&nbsp;&nbsp;CIN U47912MP2026PTC082658</p>
    </td>
  </tr>

</table>
<!--[if mso]></td></tr></table><![endif]-->
</td></tr>
</table>
</body>
</html>
`;
}

export function renderVerificationEmail(data: AuthEmailTemplateData): string {
  return renderApprovedAuthEmail({
    title: verificationEmailSubject,
    preview: verificationEmailPreview,
    heading: "Confirm your email address",
    greetingName: safeGreetingName(data.name),
    body:
      "Thanks for joining Pettxo. Please confirm this is your email so we can keep your account secure and reach you about your account.",
    accountLabel: "Email to verify",
    email: escapeHtml(data.email),
    actionLink: escapeHtml(data.actionLink),
    buttonLabel: "Verify email",
    safetyCopy:
      "<strong>Didn't sign up for Pettxo?</strong> You can ignore this email. The account won't be verified unless someone taps the button.",
  });
}

export function renderPasswordResetEmail(data: AuthEmailTemplateData): string {
  return renderApprovedAuthEmail({
    title: passwordResetEmailSubject,
    preview: passwordResetEmailPreview,
    heading: "Reset your password",
    greetingName: safeGreetingName(data.name),
    body: "We received a request to reset the password for your Pettxo account.",
    accountLabel: "Account",
    email: escapeHtml(data.email),
    actionLink: escapeHtml(data.actionLink),
    buttonLabel: "Choose a new password",
    safetyCopy:
      "<strong>Didn't ask for this?</strong> Ignore this email. Your password stays the same unless you tap the button.<br><br>Pettxo will never ask for your password on a call, in chat or on WhatsApp.",
  });
}

function safeWelcomeName(value: string | null | undefined): string {
  const trimmed = typeof value === "string" ? value.trim() : "";
  const withoutHeaderBreaks = trimmed.replace(/[\r\n]+/g, " ");
  return (withoutHeaderBreaks || "there").slice(0, 100);
}

export function welcomeEmailSubject(name?: string | null): string {
  return `Welcome to Pettxo, ${safeWelcomeName(name)}`;
}

export function renderWelcomeEmail(data: {
  name?: string | null;
  appUrl?: string;
}): string {
  const name = escapeHtml(safeWelcomeName(data.name));
  const subject = escapeHtml(welcomeEmailSubject(data.name));
  const appUrl = escapeHtml(data.appUrl ?? welcomeEmailAppUrl);
  return `<!DOCTYPE html>
<html lang="en" xmlns="http://www.w3.org/1999/xhtml" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<meta name="x-apple-disable-message-reformatting">
<meta name="format-detection" content="telephone=no, date=no, address=no, email=no">
<meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark">
<title>${subject}</title>
<link href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;600;700&display=swap" rel="stylesheet">
<!--[if mso]>
<noscript><xml><o:OfficeDocumentSettings><o:PixelsPerInch>96</o:PixelsPerInch></o:OfficeDocumentSettings></xml></noscript>
<style>td,th,div,p,a,h1,h2,span{font-family:Arial,sans-serif !important;}</style>
<![endif]-->
<style>
  body,table,td,a{-webkit-text-size-adjust:100%;-ms-text-size-adjust:100%;}
  table,td{mso-table-lspace:0pt;mso-table-rspace:0pt;}
  body{margin:0 !important;padding:0 !important;width:100% !important;}
  a[x-apple-data-detectors]{color:inherit !important;text-decoration:none !important;}
  u + #body a{color:inherit;text-decoration:none;}
  @media only screen and (max-width:620px){
    .container{width:100% !important;}
    .px{padding-left:24px !important;padding-right:24px !important;}
    .h1{font-size:25px !important;line-height:32px !important;}
    .hero{font-size:32px !important;line-height:38px !important;}
    .btn-td{width:100% !important;}
    .btn-a{display:block !important;}
    .store{display:block !important;width:100% !important;padding:0 0 10px 0 !important;}
  }
  @media (prefers-color-scheme: dark){
    .bg-page{background-color:#161412 !important;}
    .bg-card{background-color:#1F2937 !important;}
    .bg-soft{background-color:#2B3442 !important;border-color:#374151 !important;}
    .t-body{color:#F9FAFB !important;}
    .t-muted{color:#D1D5DB !important;}
    .t-legal{color:#9CA3AF !important;}
    .line td{border-color:#374151 !important;}
  }
  [data-ogsc] .t-body{color:#F9FAFB !important;}
  [data-ogsc] .t-muted{color:#D1D5DB !important;}
</style>
</head>
<body id="body" class="bg-page" style="margin:0;padding:0;background-color:#F5EFE6;">

<div style="display:none;font-size:1px;line-height:1px;max-height:0;max-width:0;opacity:0;overflow:hidden;mso-hide:all;">${welcomeEmailPreview}&#8203;&nbsp;&#8203;&nbsp;&#8203;&nbsp;&#8203;&nbsp;&#8203;&nbsp;&#8203;&nbsp;&#8203;&nbsp;&#8203;&nbsp;&#8203;&nbsp;&#8203;&nbsp;&#8203;&nbsp;&#8203;&nbsp;</div>

<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" class="bg-page" style="background-color:#F5EFE6;">
<tr><td align="center" style="padding:32px 12px 24px 12px;">
<!--[if mso]><table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0"><tr><td><![endif]-->
<table role="presentation" class="container" width="600" cellpadding="0" cellspacing="0" border="0" style="width:600px;max-width:600px;">

  <!-- HEADER -->
  <tr>
    <td bgcolor="#F75927" class="px" style="background-color:#F75927;padding:30px 40px 28px 40px;border-radius:16px 16px 0 0;">
      <a href="https://pettxo.com" target="_blank" style="text-decoration:none;"><span style="font-family:Poppins,Arial,Helvetica,sans-serif;font-size:26px;line-height:30px;font-weight:700;letter-spacing:4px;color:#FFFFFF;">PETTXO</span></a>
      <div style="font-family:Poppins,Arial,Helvetica,sans-serif;font-size:14px;line-height:20px;color:#FFFFFF;padding-top:6px;">Where pets and people connect.</div>
    </td>
  </tr>

  <!-- CONTENT -->
  <tr>
    <td class="bg-card px" bgcolor="#FFFFFF" style="background-color:#FFFFFF;padding:44px 40px 40px 40px;">
      <h1 class="h1 t-body" style="margin:0 0 16px 0;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:28px;line-height:35px;font-weight:700;color:#1F2937;">Welcome to Pettxo, ${name}</h1>
      <p class="t-body" style="margin:0 0 24px 0;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:16px;line-height:26px;color:#1F2937;">You're now part of a community built for pets and the people who care for them. Here's how to get the most out of it:</p>
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:6px 0 12px 0;">
        <tr>
          <td valign="top" width="44" style="padding:0 0 20px 0;">
            <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr><td align="center" valign="middle" width="32" height="32" bgcolor="#F75927" style="width:32px;height:32px;background-color:#F75927;border-radius:16px;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:15px;font-weight:700;color:#FFFFFF;">1</td></tr></table>
          </td>
          <td valign="top" style="padding:3px 0 20px 0;">
            <p class="t-body" style="margin:0 0 3px 0;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:16px;line-height:22px;font-weight:600;color:#1F2937;">Add your pet's profile</p>
            <p class="t-muted" style="margin:0;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:14px;line-height:22px;color:#6B7280;">A name, a photo and a few details. It takes a minute and makes every booking easier.</p>
          </td>
        </tr>
        <tr>
          <td valign="top" width="44" style="padding:0 0 20px 0;">
            <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr><td align="center" valign="middle" width="32" height="32" bgcolor="#F75927" style="width:32px;height:32px;background-color:#F75927;border-radius:16px;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:15px;font-weight:700;color:#FFFFFF;">2</td></tr></table>
          </td>
          <td valign="top" style="padding:3px 0 20px 0;">
            <p class="t-body" style="margin:0 0 3px 0;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:16px;line-height:22px;font-weight:600;color:#1F2937;">Find care near you</p>
            <p class="t-muted" style="margin:0;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:14px;line-height:22px;color:#6B7280;">Browse verified providers for grooming, walking, training, boarding and more.</p>
          </td>
        </tr>
        <tr>
          <td valign="top" width="44" style="padding:0 0 20px 0;">
            <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr><td align="center" valign="middle" width="32" height="32" bgcolor="#F75927" style="width:32px;height:32px;background-color:#F75927;border-radius:16px;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:15px;font-weight:700;color:#FFFFFF;">3</td></tr></table>
          </td>
          <td valign="top" style="padding:3px 0 20px 0;">
            <p class="t-body" style="margin:0 0 3px 0;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:16px;line-height:22px;font-weight:600;color:#1F2937;">Say hello to the community</p>
            <p class="t-muted" style="margin:0;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:14px;line-height:22px;color:#6B7280;">Share your pet's moments and follow pet parents and providers nearby.</p>
          </td>
        </tr>
      </table>
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 28px 0;"><tr>
        <td class="btn-td" align="center" bgcolor="#F75927" style="background-color:#F75927;border-radius:10px;">
          <!--[if mso]><v:roundrect xmlns:v="urn:schemas-microsoft-com:vml" href="${appUrl}" style="height:52px;v-text-anchor:middle;width:260px;" arcsize="19%" stroke="f" fillcolor="#F75927"><w:anchorlock/><center style="color:#FFFFFF;font-family:Arial,sans-serif;font-size:16px;font-weight:bold;">Open Pettxo</center></v:roundrect><![endif]-->
          <!--[if !mso]><!--><a class="btn-a" href="${appUrl}" target="_blank" style="display:inline-block;padding:16px 40px;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:16px;line-height:20px;font-weight:600;color:#FFFFFF;text-decoration:none;border-radius:10px;">Open Pettxo</a><!--<![endif]-->
        </td></tr></table>
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 28px 0;"><tr>
        <td bgcolor="#FDF4EE" class="bg-soft t-body" style="background-color:#FDF4EE;border:1px solid #F0E2D5;border-radius:10px;padding:16px 18px;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:14px;line-height:22px;color:#1F2937;"><strong>Your payment is protected.</strong> When you book, Pettxo holds your payment and releases it to the provider only after the service is done.</td></tr></table>
      <p class="t-body" style="margin:0;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:16px;line-height:26px;color:#1F2937;">Team Pettxo</p>
    </td>
  </tr>

  <!-- FOOTER (orange) -->
  <tr>
    <td bgcolor="#F75927" class="px" style="background-color:#F75927;padding:24px 40px;border-radius:0 0 16px 16px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
        <td style="font-family:Poppins,Arial,Helvetica,sans-serif;font-size:15px;line-height:22px;color:#FFFFFF;">
          Need help? We're at <a href="mailto:hello@pettxo.com" style="color:#FFFFFF;font-weight:700;text-decoration:underline;">hello@pettxo.com</a>
        </td>
      </tr></table>
    </td>
  </tr>

  <!-- LEGAL (on beige, below the card) -->
  <tr>
    <td class="px" align="center" style="padding:24px 40px 8px 40px;">
      <p class="t-legal" style="margin:0 0 10px 0;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:12px;line-height:18px;color:#6B7280;">You're receiving this service email about your Pettxo account.</p>
      <p class="t-legal" style="margin:0 0 10px 0;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:12px;line-height:18px;color:#6B7280;">
        <a href="https://pettxo.com/terms" target="_blank" style="color:#6B7280;text-decoration:underline;">Terms</a>&nbsp;&nbsp;&nbsp;
        <a href="https://pettxo.com/privacy" target="_blank" style="color:#6B7280;text-decoration:underline;">Privacy</a>&nbsp;&nbsp;&nbsp;
        <a href="https://pettxo.com/refund-policy" target="_blank" style="color:#6B7280;text-decoration:underline;">Refunds</a>
      </p>
      <p class="t-legal" style="margin:0;font-family:Poppins,Arial,Helvetica,sans-serif;font-size:12px;line-height:18px;color:#9CA3AF;">Pettxo Private Limited&nbsp;&nbsp;|&nbsp;&nbsp;CIN U47912MP2026PTC082658</p>
    </td>
  </tr>

</table>
<!--[if mso]></td></tr></table><![endif]-->
</td></tr>
</table>
</body>
</html>
`;
}
