import { TestSetupData, Address, AdditionalToken } from "../schemas/TestSetupSchema";
import mockTokenArtifact from "../../../out/WorkingCustomMockToken.sol/WorkingCustomMockToken.json";
import auctionArtifact from "../../../out/Auction.sol/Auction.json";
import auctionFactoryArtifact from "../../../out/AuctionFactory.sol/AuctionFactory.json";
import { AuctionParametersStruct } from "../../../typechain-types/out/Auction";
import { TransactionInfo } from "./types";
import {
  NATIVE_CURRENCY_ADDRESS,
  MPS,
  MAX_SYMBOL_LENGTH,
  HEX_PADDING_LENGTH,
  DEFAULT_TOTAL_SUPPLY,
  ERROR_MESSAGES,
  LOG_PREFIXES,
} from "./constants";
import { AuctionContract, TokenContract, AuctionFactoryContract, AuctionConfig, AuctionDeploymentError } from "./types";
import hre from "hardhat";

export class AuctionDeployer {
  private ethers: typeof hre.ethers;
  private auctionFactory: AuctionFactoryContract | undefined;
  private auction: AuctionContract | undefined;
  private tokens: Map<string, TokenContract> = new Map(); // Map of token name -> contract instance

  constructor() {
    this.ethers = hre.ethers;
  }

  setAuctionFactory(auctionFactory: AuctionFactoryContract): void {
    this.auctionFactory = auctionFactory;
  }
  setToken(name: string, token: TokenContract): void {
    this.tokens.set(name, token);
  }

  /**
   * Initialize the deployer with tokens and factory
   * This should be called once per test setup
   */
  async initialize(setupData: TestSetupData, setupTransactions: TransactionInfo[]): Promise<void> {
    // Deploy auction factory
    await this.deployAuctionFactory(setupTransactions, 0);

    // Deploy all tokens once
    await this.deployAdditionalTokens(setupData.additionalTokens, setupTransactions, 1);

    console.log(
      LOG_PREFIXES.SUCCESS,
      "AuctionFactory deployed. Additional Tokens Deployer",
      setupData.additionalTokens.length,
      "tokens",
    );
  }

  async deployAdditionalTokens(
    additionalTokens: AdditionalToken[],
    setupTransactions: TransactionInfo[],
    increment: number,
  ): Promise<void> {
    console.log(LOG_PREFIXES.DEPLOY, "Deploying additional tokens...");
    let i = 0;
    for (const tokenConfig of additionalTokens) {
      await this.deployToken(tokenConfig, setupTransactions, i + increment);
      increment++;
    }
  }

  /**
   * Deploy a single token
   */
  private async deployToken(
    tokenConfig: AdditionalToken,
    setupTransactions: TransactionInfo[],
    increment: number,
  ): Promise<void> {
    // Load artifact directly from Foundry's out directory
    const mockToken = await this.ethers.getContractFactory(mockTokenArtifact.abi, mockTokenArtifact.bytecode.object);
    const symbol = tokenConfig.name.substring(0, Math.min(MAX_SYMBOL_LENGTH, tokenConfig.name.length)).toUpperCase();
    const decimals = parseInt(tokenConfig.decimals);
    const totalSupply = tokenConfig.totalSupply || DEFAULT_TOTAL_SUPPLY;
    const defaultFrom = await (await hre.ethers.getSigners())[0].getAddress();
    const from = hre.ethers.getAddress(defaultFrom);
    const signer = await hre.ethers.getSigner(from);
    const nonce = await signer.getNonce("pending");
    const predicted = hre.ethers.getCreateAddress({ from, nonce: nonce + increment });
    const tx = await mockToken.getDeployTransaction(tokenConfig.name, symbol, decimals, totalSupply);
    setupTransactions.push({
      tx,
      from: null,
      msg: "Deployed Token",
    });
    const tokenContract = await hre.ethers.getContractAt("MockToken", predicted as Address);
    this.tokens.set(tokenConfig.name, tokenContract as TokenContract);
    return;
  }

  getTokenByName(tokenName: string): TokenContract | undefined {
    return this.tokens.get(tokenName);
  }

  async getTokenAddress(tokenName: string): Promise<Address | null> {
    const token = this.tokens.get(tokenName);
    return token ? ((await token.getAddress()) as Address) : null;
  }

  async getTokenByAddress(tokenAddress: string): Promise<TokenContract | undefined> {
    // Find token by address in the tokens map
    for (const [, token] of this.tokens) {
      const address = await token.getAddress();
      if (address === tokenAddress) {
        return token;
      }
    }
    return undefined;
  }

  async deployAuctionFactory(setupTransactions: TransactionInfo[], increment: number): Promise<void> {
    // Load artifact directly from Foundry's out directory
    const AuctionFactory = await this.ethers.getContractFactory(
      auctionFactoryArtifact.abi,
      auctionFactoryArtifact.bytecode.object,
    );

    const defaultFrom = await (await hre.ethers.getSigners())[0].getAddress();
    const from = hre.ethers.getAddress(defaultFrom);
    const signer = await hre.ethers.getSigner(from);
    const nonce = await signer.getNonce("pending");
    const predicted = hre.ethers.getCreateAddress({ from, nonce: nonce + increment });
    const tx = await AuctionFactory.getDeployTransaction();
    setupTransactions.push({
      tx,
      from: null,
      msg: "Deployed AuctionFactory",
    });
    const auctionFactoryContract = await hre.ethers.getContractAt("AuctionFactory", predicted as Address);
    this.auctionFactory = auctionFactoryContract as AuctionFactoryContract;
    return;
  }

  async createAuction(setupData: TestSetupData, setupTransactions: TransactionInfo[]): Promise<AuctionContract> {
    if (!this.auctionFactory) {
      throw new AuctionDeploymentError("AuctionDeployer not initialized. Call initialize() first.");
    }

    // Get the auctioned token and currency (tokens should already be deployed)
    const auctionedToken = this.getTokenByName(setupData.auctionParameters.auctionedToken);
    if (!auctionedToken) {
      throw new AuctionDeploymentError(
        ERROR_MESSAGES.AUCTIONED_TOKEN_NOT_FOUND(setupData.auctionParameters.auctionedToken),
      );
    }

    const currencyAddress = await this.resolveCurrencyAddress(setupData.auctionParameters.currency);

    // Calculate auction parameters
    const auctionConfig = this.calculateAuctionParameters(setupData, currencyAddress);
    const auctionAmount = this.calculateAuctionAmount(
      setupData.auctionParameters.auctionedToken,
      setupData.additionalTokens,
    );

    // Log auction configuration
    this.logAuctionConfiguration(auctionConfig, auctionAmount, currencyAddress, auctionedToken);

    try {
      // Encode and deploy auction
      const configData = this.encodeAuctionParameters(auctionConfig);
      const auctionAddress = await this.deployAuctionContract(
        auctionedToken,
        auctionAmount,
        configData,
        setupTransactions,
      );

      this.auction = (await this.ethers.getContractAt(auctionArtifact.abi, auctionAddress)) as AuctionContract;
      return this.auction;
    } catch (error: unknown) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      console.error(LOG_PREFIXES.ERROR, "Auction creation failed:", errorMessage);
      throw new AuctionDeploymentError("Auction creation failed", { originalError: error });
    }
  }

  /**
   * Calculate auction timing parameters
   */
  private calculateAuctionParameters(setupData: TestSetupData, currencyAddress: Address): AuctionConfig {
    const { auctionParameters, env } = setupData;

    const startBlock = BigInt(env.startBlock) + BigInt(auctionParameters.startOffsetBlocks);
    const endBlock = startBlock + BigInt(auctionParameters.auctionDurationBlocks);
    const claimBlock = endBlock + BigInt(auctionParameters.claimDelayBlocks);

    return {
      currency: currencyAddress,
      tokensRecipient: auctionParameters.tokensRecipient,
      fundsRecipient: auctionParameters.fundsRecipient,
      startBlock: Number(startBlock),
      endBlock: Number(endBlock),
      claimBlock: Number(claimBlock),
      graduationThresholdMps: Number(auctionParameters.graduationThresholdMps),
      tickSpacing: Number(auctionParameters.tickSpacing),
      validationHook: auctionParameters.validationHook,
      floorPrice: auctionParameters.floorPrice,
      auctionStepsData: this.createSimpleAuctionStepsData(auctionParameters.auctionDurationBlocks),
    };
  }

  /**
   * Log auction configuration for debugging
   */
  private async logAuctionConfiguration(
    config: AuctionConfig,
    auctionAmount: bigint,
    currencyAddress: Address,
    auctionedToken: TokenContract,
  ): Promise<void> {
    const currentBlock = await this.ethers.provider.getBlockNumber();

    console.log(LOG_PREFIXES.CONFIG, "Current block number:", currentBlock);
    console.log(LOG_PREFIXES.CONFIG, "Calculated auction startBlock:", config.startBlock);
    console.log(LOG_PREFIXES.CONFIG, "Calculated auction endBlock:", config.endBlock);
    console.log(LOG_PREFIXES.CONFIG, "Calculated auction claimBlock:", config.claimBlock);
    console.log(LOG_PREFIXES.CONFIG, "Auction amount:", auctionAmount.toString());
    console.log(LOG_PREFIXES.CONFIG, "Currency address:", currencyAddress);
    console.log(LOG_PREFIXES.CONFIG, "Auctioned token address:", await auctionedToken.getAddress());
  }

  /**
   * Encode auction parameters for contract deployment
   */
  private encodeAuctionParameters(config: AuctionConfig): string {
    // Extract AuctionParameters struct definition from the auction artifact
    const auctionParametersType = auctionArtifact.abi
      .find(
        (item: unknown) =>
          (item as any).type === "constructor" &&
          (item as any).inputs &&
          (item as any).inputs.some((input: any) => input.internalType === "struct AuctionParameters"),
      )
      ?.inputs.find((input: any) => input.internalType === "struct AuctionParameters");

    if (!auctionParametersType) {
      throw new AuctionDeploymentError(ERROR_MESSAGES.AUCTION_PARAMETERS_NOT_FOUND);
    }

    // Construct the tuple type string from the ABI components
    const components = (auctionParametersType as any).components
      .map((comp: any) => `${comp.type} ${comp.name}`)
      .join(", ");
    const tupleType = `tuple(${components})`;

    const auctionParameters: AuctionParametersStruct = {
      currency: config.currency,
      tokensRecipient: config.tokensRecipient,
      fundsRecipient: config.fundsRecipient,
      startBlock: config.startBlock,
      endBlock: config.endBlock,
      claimBlock: config.claimBlock,
      graduationThresholdMps: config.graduationThresholdMps,
      tickSpacing: config.tickSpacing,
      validationHook: config.validationHook,
      floorPrice: config.floorPrice,
      auctionStepsData: config.auctionStepsData,
    };

    const configData = this.ethers.AbiCoder.defaultAbiCoder().encode([tupleType], [auctionParameters]);

    console.log(LOG_PREFIXES.CONFIG, "Config data length:", configData.length);
    return configData;
  }

  /**
   * Deploy the auction contract
   */
  private async deployAuctionContract(
    auctionedToken: TokenContract,
    auctionAmount: bigint,
    configData: string,
    setupTransactions: TransactionInfo[],
  ): Promise<string> {
    if (!this.auctionFactory) {
      throw new AuctionDeploymentError(ERROR_MESSAGES.AUCTION_FACTORY_NOT_DEPLOYED);
    }

    const salt = this.ethers.keccak256(this.ethers.toUtf8Bytes("test-salt"));

    const auctionAddress = await (this.auctionFactory.initializeDistribution as any).staticCall(
      await auctionedToken.getAddress(),
      auctionAmount,
      configData,
      salt,
    );

    // Execute the actual transaction
    const tx = await this.auctionFactory
      .getFunction("initializeDistribution")
      .populateTransaction(await auctionedToken.getAddress(), auctionAmount, configData, salt);
    const defaultFrom = await (await hre.ethers.getSigners())[0].getAddress();
    setupTransactions.push({
      tx,
      from: defaultFrom,
      msg: "Deployed Auction",
    });

    return auctionAddress;
  }

  async resolveCurrencyAddress(currency: Address | string): Promise<Address> {
    // If it's an address, return it directly
    if (currency.startsWith("0x")) {
      return currency as Address;
    }
    // Otherwise, look up the token by name
    const address = await this.getTokenAddress(currency);
    if (!address) {
      throw new AuctionDeploymentError(ERROR_MESSAGES.TOKEN_NOT_FOUND(currency));
    }
    return address;
  }

  calculateAuctionAmount(tokenName: string, additionalTokens: AdditionalToken[]): bigint {
    const tokenConfig = additionalTokens.find((t) => t.name === tokenName);
    if (!tokenConfig) {
      throw new AuctionDeploymentError(ERROR_MESSAGES.TOKEN_NOT_FOUND(tokenName));
    }

    const totalSupply = BigInt(tokenConfig.totalSupply);
    const percentAuctioned = parseFloat(tokenConfig.percentAuctioned);
    return (totalSupply * BigInt(Math.floor(percentAuctioned * 100))) / BigInt(10000);
  }

  createSimpleAuctionStepsData(auctionDurationBlocks: number): string {
    // Create a simple auction steps data that satisfies the validation
    // Format: each step is 8 bytes (uint64): 3 bytes mps + 5 bytes blockDelta
    // We need: sumMps = 1e7 (MPS constant) and sumBlockDelta = auctionDurationBlocks

    const blockDelta = parseInt(auctionDurationBlocks.toString());
    const mps = Math.floor(MPS / blockDelta); // mps * blockDelta should equal MPS

    console.log(LOG_PREFIXES.INFO, "Creating auction steps data:");
    console.log(LOG_PREFIXES.INFO, "MPS:", MPS);
    console.log(LOG_PREFIXES.INFO, "blockDelta:", blockDelta);
    console.log(LOG_PREFIXES.INFO, "mps:", mps);

    // Pack mps (24 bits) and blockDelta (40 bits) into 8 bytes
    // mps goes in the upper 24 bits, blockDelta in the lower 40 bits
    const packed = (BigInt(mps) << 40n) | BigInt(blockDelta);

    // Convert to hex string with proper padding (8 bytes = 16 hex chars)
    const hex = packed.toString(16).padStart(HEX_PADDING_LENGTH, "0");
    const result = "0x" + hex;

    console.log(LOG_PREFIXES.INFO, "packed:", packed.toString());
    console.log(LOG_PREFIXES.INFO, "hex:", result);

    return result;
  }

  async setupBalances(setupData: TestSetupData, setupTransactions: TransactionInfo[]): Promise<void> {
    const { env } = setupData;
    if (!env.balances) return;

    console.log(LOG_PREFIXES.ASSERTION, "Setting up balances...");

    for (const balance of env.balances) {
      if (balance.token === NATIVE_CURRENCY_ADDRESS) {
        await this.setupNativeCurrencyBalance(balance.address, balance.amount);
      } else if (balance.token.startsWith("0x")) {
        await this.setupTokenBalanceByAddress(
          balance.address,
          balance.token as Address,
          balance.amount,
          setupTransactions,
        );
      } else {
        await this.setupTokenBalanceByName(balance.address, balance.token, balance.amount, setupTransactions);
      }
    }
  }

  /**
   * Setup native currency balance
   */
  private async setupNativeCurrencyBalance(address: Address, amount: string): Promise<void> {
    const hexAmount = "0x" + BigInt(amount).toString(16);
    await hre.network.provider.send("hardhat_setBalance", [address, hexAmount]);
    console.log(LOG_PREFIXES.SUCCESS, "Set native currency balance:", address, "=", amount, "wei");
  }

  /**
   * Setup token balance by contract address
   */
  private async setupTokenBalanceByAddress(
    address: Address,
    tokenAddress: Address,
    amount: string,
    setupTransactions: TransactionInfo[],
  ): Promise<void> {
    let token: TokenContract | null = null;
    for (const [, tokenContract] of this.tokens) {
      if ((await tokenContract.getAddress()) === tokenAddress) {
        token = tokenContract;
        break;
      }
    }

    if (token) {
      let tx = await token.getFunction("mint").populateTransaction(address, amount);
      setupTransactions.push({ tx, from: null, msg: "Minted" });
      console.log(LOG_PREFIXES.SUCCESS, "Minted", amount, "tokens to", address, "(", await token.getAddress(), ")");
    } else {
      console.warn(LOG_PREFIXES.WARNING, "Token not found for address:", tokenAddress);
    }
  }

  /**
   * Setup token balance by token name
   */
  private async setupTokenBalanceByName(
    address: Address,
    tokenName: string,
    amount: string,
    setupTransactions: TransactionInfo[],
  ): Promise<void> {
    const token = this.getTokenByName(tokenName);
    if (token) {
      let tx = await token.getFunction("transfer").populateTransaction(address, amount);
      setupTransactions.push({
        tx,
        from: null,
        msg: "Minted",
      });
      console.log(LOG_PREFIXES.SUCCESS, "Minted", amount, tokenName, "to", address);
    } else {
      console.warn(LOG_PREFIXES.WARNING, "Token not found:", tokenName);
    }
  }
}
