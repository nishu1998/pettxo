const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const legacySource = fs.readFileSync(path.resolve(__dirname, "../src/legacyFunctions.ts"), "utf8");
const authServiceSource = fs.readFileSync(path.resolve(__dirname, "../../lib/features/auth/data/services/auth_service.dart"), "utf8");
const emailSignupSource = fs.readFileSync(path.resolve(__dirname, "../../lib/features/auth/presentation/screens/signup_screen.dart"), "utf8");
const phoneSignupSource = fs.readFileSync(path.resolve(__dirname, "../../lib/features/auth/presentation/screens/signup_with_phone_screen.dart"), "utf8");
const recoveryConsentSource = fs.readFileSync(path.resolve(__dirname, "../../lib/features/auth/presentation/screens/onboarding_consent_screen.dart"), "utf8");

test("phone, email, and recovery signup surfaces use the current visible communications disclosure", () => {
  for (const source of [emailSignupSource, phoneSignupSource, recoveryConsentSource]) {
    assert.match(source, /signupMarketingCommunicationsDisclosure/);
  }
  assert.match(authServiceSource, /termsCommunicationsPolicyVersion[\s\S]*signupTermsCommunicationsPolicyVersion/);
});

test("canonical onboarding validates the fixed version and initializes marketing in its transaction", () => {
  assert.match(legacySource, /resolveSignupTermsCommunicationsContract\(request\.data\)/);
  assert.match(legacySource, /termsCommunicationsContract === "current"/);
  assert.match(legacySource, /signupMarketingEmailPreferencePatch\([\s\S]*privateUser[\s\S]*signupTermsCommunicationsPolicyVersion[\s\S]*now/);
  assert.match(legacySource, /const completion = await db\.runTransaction/);
  assert.doesNotMatch(authServiceSource, /marketingEmailPreferenceSource|marketingEmailPreferenceUpdatedAt/);
});

test("legacy onboarding can complete without claiming current communications consent", () => {
  assert.match(legacySource, /termsCommunicationsContract === "current" &&[\s\S]*termsCommunicationsPolicyVersion:/);
  assert.match(legacySource, /termsCommunicationsContract === "current" \? signupMarketingEmailPreferencePatch/);
  assert.doesNotMatch(authServiceSource, /marketingEmailEnabled|marketingEmailPreferenceSource/);
});

test("signup preference initialization does not send marketing email or alter welcome trigger ownership", () => {
  const onboardingBlock = legacySource.match(/export const completeOnboardingProfile[\s\S]*?export const syncAuthIdentity/)?.[0] || "";
  assert.doesNotMatch(onboardingBlock, /sendMarketingEmail|RESEND_MARKETING_API_KEY/);
  assert.doesNotMatch(onboardingBlock, /sendWelcomeEmail/);
});
