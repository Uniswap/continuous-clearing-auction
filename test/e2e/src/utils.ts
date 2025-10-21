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
 * @param floorPrice - The auction's floor price (already in Q96 format)
 * @param tickSpacing - The auction's tick spacing
 * @returns The price in X96 format as a bigint
 */
export function tickNumberToPriceX96(tickNumber: number, floorPrice: bigint, tickSpacing: bigint): bigint {
  // Floor price is already in Q96, tick spacing is raw
  // price = floorPrice + (tickNumber - 1) * tickSpacing
  return floorPrice + (BigInt(tickNumber) - 1n) * tickSpacing;
}

/**
 * Calculates the bid price based on the price configuration.
 * @param priceConfig - Price configuration specifying type and value
 * @returns The calculated price as a bigint
 * @throws Error if price type is unsupported
 */
export async function calculatePrice(
  priceConfig: PriceConfig,
  floorPrice?: bigint,
  tickSpacing?: bigint,
): Promise<bigint> {
  let value: bigint;

  if (priceConfig.type === PriceType.TICK) {
    // Convert tick to actual price using the auction's parameters
    if (!floorPrice || !tickSpacing) {
      throw new Error("floorPrice and tickSpacing required for TICK price type");
    }
    value = tickNumberToPriceX96(parseInt(priceConfig.value.toString()), floorPrice, tickSpacing);
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
