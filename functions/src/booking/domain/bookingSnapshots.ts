import {isBookingType, type BookingType} from "./bookingContracts";

export type BookingServiceSnapshot = {
  serviceId: string;
  providerId: string;
  serviceTitle: string;
  animalType: string;
  category: string;
  bookingType: BookingType;
  timezone: string;
  serviceUnitPricePaise?: number;
  durationMinutes?: number;
  pricePerNightPaise?: number;
  selectedSlotCount?: number;
  totalDurationMinutes?: number;
  checkInDateTime?: Date;
  checkOutDateTime?: Date;
  capacitySnapshot: number;
  serviceLocationType: string;
  currency: string;
  snapshotVersion: 1;
};

export type BookingFinancialSnapshot = {
  currency: string;
  serviceSubtotalPaise: number;
  couponDiscountPaise: number;
  customerPaidPaise: number;
  platformCommissionRateBasisPoints: number;
  platformCommissionPaise: number;
  providerPayoutPaise: number;
  pettxoCouponFundingPaise: number;
  gatewayFeeSunkPaise: number;
  providerFaultCostPaise: number;
  refundAmountPaise: number;
  pettxoNetBeforeGatewayPaise: number;
  pricingVersion: 1;
};

function isNonNegativeInteger(value: unknown): value is number {
  return Number.isInteger(value) && (value as number) >= 0;
}

export function isBookingServiceSnapshot(value: unknown): value is BookingServiceSnapshot {
  if (typeof value !== "object" || value == null) return false;
  const snapshot = value as Partial<BookingServiceSnapshot>;
  if (!isBookingType(snapshot.bookingType)) return false;
  if (!isNonNegativeInteger(snapshot.capacitySnapshot)) return false;
  if (snapshot.snapshotVersion !== 1) return false;
  if (typeof snapshot.serviceId !== "string" || !snapshot.serviceId.trim()) return false;
  if (typeof snapshot.providerId !== "string" || !snapshot.providerId.trim()) return false;
  if (typeof snapshot.serviceTitle !== "string") return false;
  if (typeof snapshot.currency !== "string" || !snapshot.currency.trim()) return false;
  return true;
}

export function isBookingFinancialSnapshot(value: unknown): value is BookingFinancialSnapshot {
  if (typeof value !== "object" || value == null) return false;
  const snapshot = value as Partial<BookingFinancialSnapshot>;
  if (snapshot.pricingVersion !== 1) return false;
  if (typeof snapshot.currency !== "string" || !snapshot.currency.trim()) return false;
  return isNonNegativeInteger(snapshot.serviceSubtotalPaise) &&
    isNonNegativeInteger(snapshot.couponDiscountPaise) &&
    isNonNegativeInteger(snapshot.customerPaidPaise) &&
    isNonNegativeInteger(snapshot.platformCommissionRateBasisPoints) &&
    isNonNegativeInteger(snapshot.platformCommissionPaise) &&
    isNonNegativeInteger(snapshot.providerPayoutPaise) &&
    isNonNegativeInteger(snapshot.pettxoCouponFundingPaise) &&
    isNonNegativeInteger(snapshot.gatewayFeeSunkPaise) &&
    isNonNegativeInteger(snapshot.providerFaultCostPaise) &&
    isNonNegativeInteger(snapshot.refundAmountPaise) &&
    Number.isInteger(snapshot.pettxoNetBeforeGatewayPaise);
}
