const test = require("node:test");
const assert = require("node:assert/strict");

const {
  passwordResetEmailPreview,
  passwordResetEmailSubject,
  renderPasswordResetEmail,
  renderVerificationEmail,
  verificationEmailPreview,
  verificationEmailSubject,
} = require("../lib/email/authEmailTemplates.js");
const {
  authEmailFrom,
  authEmailReplyTo,
} = require("../lib/email/authEmailTransport.js");

const actionLink =
  "https://pettxo.com/__/auth/action?mode=verifyEmail&oobCode=a%2Bb";

test("approved subjects and preheaders remain exact", () => {
  assert.equal(verificationEmailSubject, "Verify your email for Pettxo");
  assert.equal(passwordResetEmailSubject, "Reset your Pettxo password");
  assert.equal(
    verificationEmailPreview,
    "One tap to confirm your email and secure your Pettxo account.",
  );
  assert.equal(
    passwordResetEmailPreview,
    "Use this link to choose a new password for your Pettxo account.",
  );
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
