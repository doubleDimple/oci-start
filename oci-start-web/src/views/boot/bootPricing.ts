import type { BootArchitecture } from '@/api/ociBoot'

export interface ShapePricingRule {
  shapeName: string
  ocpuPerHourUsd: number
  memoryPerGbHourUsd: number
  storagePerGbMonthUsd: number
}

export interface BootPriceEstimate {
  shapeName: string
  ocpuPerHourUsd: number
  memoryPerGbHourUsd: number
  storagePerGbMonthUsd: number
  perInstanceComputeHourlyUsd: number
  perInstanceStorageHourlyUsd: number
  perInstanceHourlyUsd: number
  perInstanceComputeMonthlyUsd: number
  perInstanceStorageMonthlyUsd: number
  perInstanceMonthlyUsd: number
  count: number
  totalHourlyUsd: number
  totalMonthlyUsd: number
}

export const OCI_HOURS_PER_MONTH = 744
export const OCI_BOOT_STORAGE_GB_MONTH_USD = 0.0255

export const PAID_SHAPE_PRICING: Partial<Record<BootArchitecture, ShapePricingRule>> = {
  ARM_PAID_A2: {
    shapeName: 'VM.Standard.A2.Flex',
    ocpuPerHourUsd: 0.014,
    memoryPerGbHourUsd: 0.002,
    storagePerGbMonthUsd: OCI_BOOT_STORAGE_GB_MONTH_USD,
  },
  AMD_PAID_E3: {
    shapeName: 'VM.Standard3.Flex',
    ocpuPerHourUsd: 0.04,
    memoryPerGbHourUsd: 0.0015,
    storagePerGbMonthUsd: OCI_BOOT_STORAGE_GB_MONTH_USD,
  },
  AMD_PAID_E4: {
    shapeName: 'VM.Standard.E4.Flex',
    ocpuPerHourUsd: 0.025,
    memoryPerGbHourUsd: 0.0015,
    storagePerGbMonthUsd: OCI_BOOT_STORAGE_GB_MONTH_USD,
  },
  AMD_PAID_E5: {
    shapeName: 'VM.Standard.E5.Flex',
    ocpuPerHourUsd: 0.03,
    memoryPerGbHourUsd: 0.002,
    storagePerGbMonthUsd: OCI_BOOT_STORAGE_GB_MONTH_USD,
  },
}

export function estimateBootTemplatePrice(
  spec: { architecture: BootArchitecture; ocpu: number; memory: number; disk: number; paid?: boolean },
  count = 1,
): BootPriceEstimate | null {
  const rule = PAID_SHAPE_PRICING[spec.architecture]
  if (!rule || spec.paid === false) return null
  const normalizedCount = Number.isInteger(count) && count >= 1 ? count : 1
  const perInstanceComputeHourlyUsd = spec.ocpu * rule.ocpuPerHourUsd + spec.memory * rule.memoryPerGbHourUsd
  const perInstanceStorageMonthlyUsd = spec.disk * rule.storagePerGbMonthUsd
  const perInstanceStorageHourlyUsd = perInstanceStorageMonthlyUsd / OCI_HOURS_PER_MONTH
  const perInstanceHourlyUsd = perInstanceComputeHourlyUsd + perInstanceStorageHourlyUsd
  const perInstanceComputeMonthlyUsd = perInstanceComputeHourlyUsd * OCI_HOURS_PER_MONTH
  const perInstanceMonthlyUsd = perInstanceComputeMonthlyUsd + perInstanceStorageMonthlyUsd
  return {
    shapeName: rule.shapeName,
    ocpuPerHourUsd: rule.ocpuPerHourUsd,
    memoryPerGbHourUsd: rule.memoryPerGbHourUsd,
    storagePerGbMonthUsd: rule.storagePerGbMonthUsd,
    perInstanceComputeHourlyUsd,
    perInstanceStorageHourlyUsd,
    perInstanceHourlyUsd,
    perInstanceComputeMonthlyUsd,
    perInstanceStorageMonthlyUsd,
    perInstanceMonthlyUsd,
    count: normalizedCount,
    totalHourlyUsd: perInstanceHourlyUsd * normalizedCount,
    totalMonthlyUsd: perInstanceMonthlyUsd * normalizedCount,
  }
}

export function formatUsd(amount: number, decimals = 2): string {
  return `$${amount.toFixed(decimals)}`
}
