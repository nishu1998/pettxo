export function canModerateService(role: string): boolean {
  return role === "superAdmin" || role === "customerSupportAdmin";
}

export function isServiceModerationAction(action: string): action is "approve" | "remove" {
  return action === "approve" || action === "remove";
}
