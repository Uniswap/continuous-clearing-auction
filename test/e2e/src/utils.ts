import { PriceConfig, PriceType } from "../schemas/TestInteractionSchema";
import { ERROR_MESSAGES } from "./constants";
import { AuctionDeployer } from "./AuctionDeployer";

/**
 * Resolves a token identifier to its contract address.
 * @param tokenIdentifier - Token name or address (if starts with "0x", returns as-is)
 * @returns The resolved token address
 * @throws Error if token is not found
 */
export async function resolveTokenAddress(tokenIdentifier: string, auctionDeployer: AuctionDeployer): Promise<string> {
  if (tokenIdentifier.startsWith("0x")) {
    return tokenIdentifier; // It's already an address
  }
  // Look up by name in the deployed tokens (from AuctionDeployer)
  const tokenContract = auctionDeployer.getTokenByName(tokenIdentifier);
  if (tokenContract) {
    return await tokenContract.getAddress();
  }

  throw new Error(ERROR_MESSAGES.TOKEN_IDENTIFIER_NOT_FOUND(tokenIdentifier));
}

/**
 * Converts a tick number to a price in X96 format.
 * @param tickNumber - The tick number to convert
 * @returns The price in X96 format as a bigint
 */
export function tickNumberToPriceX96(tickNumber: number): bigint {
  // This mirrors the logic from AuctionBaseTest.sol
  const FLOOR_PRICE = 1000n * 2n ** 96n; // 1000 * 2^96
  const TICK_SPACING = 100n; // From our setup (matches Foundry test)

  return ((FLOOR_PRICE >> 96n) + (BigInt(tickNumber) - 1n) * TICK_SPACING) << 96n;
}

/**
 * Calculates the required currency amount for a bid.
 * @param exactIn - Whether the input amount is exact
 * @param amount - The input amount
 * @param maxPrice - The maximum price for the calculation
 * @returns The required currency amount as a bigint
 */
export async function calculateRequiredCurrencyAmount(
  exactIn: boolean,
  amount: bigint,
  maxPrice: bigint,
): Promise<bigint> {
  // This mirrors the BidLib.inputAmount logic
  if (exactIn) {
    // For exactIn bids, the amount is in currency units
    return amount;
  } else {
    // For non-exactIn bids, calculate amount * maxPrice / Q96
    const Q96 = BigInt(2) ** BigInt(96);
    return (amount * maxPrice) / Q96;
  }
}

/**
 * Calculates the bid price based on the price configuration.
 * @param priceConfig - Price configuration specifying type and value
 * @returns The calculated price as a bigint
 * @throws Error if price type is unsupported
 */
export async function calculatePrice(priceConfig: PriceConfig): Promise<bigint> {
  let value: bigint;

  if (priceConfig.type === PriceType.TICK) {
    // Convert tick to actual price using the same logic as the Foundry tests
    value = tickNumberToPriceX96(parseInt(priceConfig.value.toString()));
  } else {
    // Ensure the value is treated as a string to avoid scientific notation conversion
    value = BigInt(priceConfig.value.toString());
  }

  // Implement price variation
  if (priceConfig.variation) {
    const variationPercent = parseFloat(priceConfig.variation);
    const variationAmount = (Number(value) * variationPercent) / 100;
    const randomVariation = (Math.random() - 0.5) * 2 * variationAmount; // -variation to +variation
    const adjustedValue = Number(value) + randomVariation;

    // Ensure the price doesn't go negative
    value = BigInt(Math.max(0, Math.floor(adjustedValue)));
  }

  return value;
}

/**
 * Checks if a string is any possible stringified version of a true boolean value.
 * @param value - The string to parse
 * @returns True if the string is a stringified version of a true boolean value, false otherwise
 */
export function parseBoolean(value: string): boolean {
  return value.toLowerCase() === "true" || value === "1";
}
