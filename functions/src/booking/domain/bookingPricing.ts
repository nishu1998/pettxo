import {PLATFORM_COMMISSION_BASIS_POINTS} from "./bookingConstants";
import type {BookingFinancialSnapshot} from "./bookingSnapshots";

export type PricingRoundingStrategy = "floor";

export type PricingCalculationInput = {
  currency: string;
  serviceSubtotalPaise: number;
  couponDiscountPaise: number;
  platformCommissionRateBasisPoints?: number;
  gatewayFeeSunkPaise?: number;
  providerFaultCostPaise?: number;
  refundAmountPaise?: number;
};

function assertNonNegativeInteger(value: number, field: string): void {
  if (!Number.isInteger(value) || value < 0) {
    throw new Error(`${field} must be a non-negative integer paise value.`);
  }
}

export function calculateBasisPointsAmount(
  amountPaise: number,
  basisPoints: number,
  strategy: PricingRoundingStrategy = "floor",
): number {
  assertNonNegativeInteger(amountPaise, "amountPaise");
  assertNonNegativeInteger(basisPoints, "basisPoints");
  if (strategy !== "floor") {
    throw new Error(`Unsupported pricing rounding strategy: ${strategy}`);
  }
  return Math.floor((amountPaise * basisPoints) / 10000);
}

export function calculateBookingFinancialSnapshot(
  input: PricingCalculationInput,
): BookingFinancialSnapshot {
  const serviceSubtotalPaise = input.serviceSubtotalPaise;
  const couponDiscountPaise = input.couponDiscountPaise;
  const commissionBasisPoints = input.platformCommissionRateBasisPoints ??
    PLATFORM_COMMISSION_BASIS_POINTS;
  const gatewayFeeSunkPaise = input.gatewayFeeSunkPaise ?? 0;
  const providerFaultCostPaise = input.providerFaultCostPaise ?? 0;
  const refundAmountPaise = input.refundAmountPaise ?? 0;

  assertNonNegativeInteger(serviceSubtotalPaise, "serviceSubtotalPaise");
  assertNonNegativeInteger(couponDiscountPaise, "couponDiscountPaise");
  assertNonNegativeInteger(gatewayFeeSunkPaise, "gatewayFeeSunkPaise");
  assertNonNegativeInteger(providerFaultCostPaise, "providerFaultCostPaise");
  assertNonNegativeInteger(refundAmountPaise, "refundAmountPaise");
  if (!Number.isInteger(commissionBasisPoints) ||
    commissionBasisPoints < 0 ||
    commissionBasisPoints > 10000) {
    throw new Error("platformCommissionRateBasisPoints must be an integer between 0 and 10000.");
  }

  const platformCommissionPaise = calculateBasisPointsAmount(
    serviceSubtotalPaise,
    commissionBasisPoints,
  );
  const providerPayoutPaise = serviceSubtotalPaise - platformCommissionPaise;
  const customerPaidPaise = Math.max(0, serviceSubtotalPaise - couponDiscountPaise);
  const pettxoCouponFundingPaise = couponDiscountPaise;
  const pettxoNetBeforeGatewayPaise = customerPaidPaise - providerPayoutPaise;

  if (providerPayoutPaise + platformCommissionPaise !== serviceSubtotalPaise) {
    throw new Error("Provider payout plus commission must equal the service subtotal.");
  }
  if (customerPaidPaise + pettxoCouponFundingPaise < serviceSubtotalPaise) {
    throw new Error("Customer paid plus Pettxo coupon funding cannot be less than the service subtotal.");
  }

  return {
    currency: input.currency.trim() || "INR",
    serviceSubtotalPaise,
    couponDiscountPaise,
    customerPaidPaise,
    platformCommissionRateBasisPoints: commissionBasisPoints,
    platformCommissionPaise,
    providerPayoutPaise,
    pettxoCouponFundingPaise,
    gatewayFeeSunkPaise,
    providerFaultCostPaise,
    refundAmountPaise,
    pettxoNetBeforeGatewayPaise,
    pricingVersion: 1,
  };
}

export function calculateRefundAmountFromCustomerPaid(params: {
  customerPaidPaise: number;
  refundBasisPoints: number;
}): number {
  assertNonNegativeInteger(params.customerPaidPaise, "customerPaidPaise");
  if (!Number.isInteger(params.refundBasisPoints) ||
    params.refundBasisPoints < 0 ||
    params.refundBasisPoints > 10000) {
    throw new Error("refundBasisPoints must be an integer between 0 and 10000.");
  }
  return calculateBasisPointsAmount(
    params.customerPaidPaise,
    params.refundBasisPoints,
  );
}
