const test = require("node:test");
const assert = require("node:assert/strict");

const {
  emailChangeVerificationPreview,
  emailChangeVerificationSubject,
  passwordResetEmailPreview,
  passwordResetEmailSubject,
  renderEmailChangeVerification,
  renderPasswordResetEmail,
  renderVerificationEmail,
  renderWelcomeEmail,
  verificationEmailPreview,
  verificationEmailSubject,
  welcomeEmailPreview,
  welcomeEmailSubject,
} = require("../lib/email/authEmailTemplates.js");
const {
  authEmailFrom,
  authEmailReplyTo,
} = require("../lib/email/authEmailTransport.js");

const actionLink =
  "https://pettxo.com/__/auth/action?mode=verifyEmail&oobCode=a%2Bb";

test("approved subjects and preheaders remain exact", () => {
  assert.equal(verificationEmailSubject, "Verify your email for Pettxo");
  assert.equal(
    emailChangeVerificationSubject,
    "Verify your new email for Pettxo",
  );
  assert.equal(passwordResetEmailSubject, "Reset your Pettxo password");
  assert.equal(
    emailChangeVerificationPreview,
    "Verify your new email address to complete your Pettxo account change.",
  );
  assert.equal(
    verificationEmailPreview,
    "One tap to confirm your email and secure your Pettxo account.",
  );
  assert.equal(
    passwordResetEmailPreview,
    "Use this link to choose a new password for your Pettxo account.",
  );
});

test("email change template reuses approved branding and preserves its secure action", () => {
  const html = renderEmailChangeVerification({
    name: "Priya & Co",
    email: "new@example.com",
    actionLink: actionLink.replace("verifyEmail", "verifyAndChangeEmail"),
  });

  assert.match(html, /Verify your new email/);
  assert.match(html, />Verify new email<\/a>/);
  assert.match(html, /Where pets and people connect\./);
  assert.match(html, /Pettxo Private Limited/);
  assert.match(html, /Hi Priya &amp; Co,/);
  assert.match(html, /New email address/);
  assert.ok(html.includes("mode=verifyAndChangeEmail&amp;oobCode=a%2Bb"));
  assert.equal(html.includes("RESEND_API_KEY"), false);
  assert.equal(html.includes("AIza"), false);
});

test("transactional sender identity remains exact", () => {
  assert.equal(authEmailFrom, "Pettxo <no-reply@pettxo.com>");
  assert.equal(authEmailReplyTo, "hello@pettxo.com");
});

test("verification template preserves approved content and escapes dynamic values", () => {
  const html = renderVerificationEmail({
    name: '<img src=x onerror="bad">',
    email: "person+<tag>@example.com",
    actionLink,
  });

  assert.match(html, /Confirm your email address/);
  assert.match(html, />Verify email<\/a>/);
  assert.match(html, /Where pets and people connect\./);
  assert.match(html, /Pettxo Private Limited/);
  assert.match(html, /Hi &lt;img src=x onerror=&quot;bad&quot;&gt;,/);
  assert.match(html, /person\+&lt;tag&gt;@example\.com/);
  assert.ok(html.includes("mode=verifyEmail&amp;oobCode=a%2Bb"));
  assert.equal(html.includes('<img src=x onerror="bad">'), false);
  assert.equal(html.includes("<iframe"), false);
  assert.equal(html.includes("srcdoc="), false);
  assert.equal(html.includes("showcase-nav"), false);
});

test("missing name renders the approved Hi there fallback", () => {
  const html = renderVerificationEmail({
    name: "  ",
    email: "person@example.com",
    actionLink,
  });
  assert.match(html, />Hi there,<\/p>/);
  assert.equal(html.includes("Hi null"), false);
  assert.equal(html.includes("Hi undefined"), false);
});

test("reset template preserves approved CTA, safety copy, and escaped link", () => {
  const html = renderPasswordResetEmail({
    name: "Priya & Co",
    email: "priya@example.com",
    actionLink: actionLink.replace("verifyEmail", "resetPassword"),
  });

  assert.match(html, /Reset your password/);
  assert.match(html, />Choose a new password<\/a>/);
  assert.match(html, /Didn't ask for this\?/);
  assert.match(html, /Pettxo will never ask for your password/);
  assert.match(html, /Hi Priya &amp; Co,/);
  assert.ok(html.includes("mode=resetPassword&amp;oobCode=a%2Bb"));
  assert.equal(html.includes("<iframe"), false);
  assert.equal(html.includes("srcdoc="), false);
});

test("welcome template preserves approved subject, preheader, CTA, and footer", () => {
  const html = renderWelcomeEmail({name: "Arjun"});
  assert.equal(welcomeEmailSubject("Arjun"), "Welcome to Pettxo, Arjun");
  assert.equal(welcomeEmailPreview, "Here's how to get started with Pettxo.");
  assert.match(html, /Welcome to Pettxo, Arjun/);
  assert.match(html, /Add your pet's profile/);
  assert.match(html, /Find care near you/);
  assert.match(html, /Say hello to the community/);
  assert.match(html, /href="https:\/\/pettxo\.com\/app"/);
  assert.match(html, />Open Pettxo<\/a>/);
  assert.match(html, /Pettxo Private Limited/);
  assert.match(html, /hello@pettxo\.com/);
  assert.equal(html.includes("<iframe"), false);
  assert.equal(html.includes("srcdoc="), false);
});

test("welcome name fallback and HTML escaping are safe", () => {
  const fallback = renderWelcomeEmail({name: "  "});
  const escaped = renderWelcomeEmail({name: '<img onerror="bad">'});
  assert.equal(welcomeEmailSubject(), "Welcome to Pettxo, there");
  assert.match(fallback, /Welcome to Pettxo, there/);
  assert.match(escaped, /Welcome to Pettxo, &lt;img onerror=&quot;bad&quot;&gt;/);
  assert.equal(escaped.includes('<img onerror="bad">'), false);
  assert.equal(
    welcomeEmailSubject("Person\r\nBcc: attacker@example.com"),
    "Welcome to Pettxo, Person Bcc: attacker@example.com",
  );
});
