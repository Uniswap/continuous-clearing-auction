import { TestSetupData, Address, AdditionalToken, StepData } from "../schemas/TestSetupSchema";
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
  METHODS,
  PENDING_STATE,
} from "./constants";
import { AuctionContract, TokenContract, AuctionFactoryContract, AuctionConfig } from "./types";
import hre from "hardhat";

export class AuctionDeployer {
  private ethers: typeof hre.ethers;
  private auctionFactory: AuctionFactoryContract | undefined;
  private auction: AuctionContract | undefined;
  private tokens: Map<string, TokenContract> = new Map(); // Map of token name -> contract instance

  constructor() {
    this.ethers = hre.ethers;
  }

  /**
   * Sets the auction factory contract reference.
   * @param auctionFactory - The auction factory contract instance
   */
  setAuctionFactory(auctionFactory: AuctionFactoryContract): void {
    this.auctionFactory = auctionFactory;
  }
  /**
   * Sets a token contract reference by name.
   * @param name - The token name
   * @param token - The token contract instance
   */
  setToken(name: string, token: TokenContract): void {
    this.tokens.set(name, token);
  }

  /**
   * Initializes the deployer by deploying tokens and setting up the auction factory.
   * @param setupData - Test setup data containing auction parameters and additional tokens
   * @param setupTransactions - Array to collect setup transaction information
   * @throws Error if auction factory is not deployed or token deployment fails
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

  /**
   * Deploys additional tokens for the test setup.
   * @param additionalTokens - Array of additional token configurations
   * @param setupTransactions - Array to collect setup transaction information
   * @param increment - Starting increment value for deployment
   */
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
   * Deploys a single token contract.
   * @param tokenConfig - Token configuration containing name, symbol, decimals, and total supply
   * @param setupTransactions - Array to collect setup transaction information
   * @param increment - Increment value for deployment
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
    const nonce = await signer.getNonce(PENDING_STATE);
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

  /**
   * Gets a token contract by name.
   * @param tokenName - The name of the token
   * @returns The token contract instance or undefined if not found
   */
  getTokenByName(tokenName: string): TokenContract | undefined {
    return this.tokens.get(tokenName);
  }

  /**
   * Gets the address of a token by name.
   * @param tokenName - The name of the token
   * @returns The token address or null if not found
   */
  async getTokenAddress(tokenName: string): Promise<Address | null> {
    const token = this.tokens.get(tokenName);
    return token ? ((await token.getAddress()) as Address) : null;
  }

  /**
   * Gets a token contract by its address.
   * @param tokenAddress - The address of the token
   * @returns The token contract instance or undefined if not found
   */
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

  /**
   * Deploys the auction factory contract.
   * @param setupTransactions - Array to collect setup transaction information
   * @param increment - Increment value for deployment
   */
  async deployAuctionFactory(setupTransactions: TransactionInfo[], increment: number): Promise<void> {
    // Load artifact directly from Foundry's out directory
    const AuctionFactory = await this.ethers.getContractFactory(
      auctionFactoryArtifact.abi,
      auctionFactoryArtifact.bytecode.object,
    );

    const defaultFrom = await (await hre.ethers.getSigners())[0].getAddress();
    const from = hre.ethers.getAddress(defaultFrom);
    const signer = await hre.ethers.getSigner(from);
    const nonce = await signer.getNonce(PENDING_STATE);
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

  /**
   * Creates a new auction using the auction factory.
   * @param setupData - Test setup data containing auction parameters
   * @param setupTransactions - Array to collect setup transaction information
   * @returns The deployed auction contract instance
   * @throws Error if auction factory is not initialized or auction creation fails
   */
  async createAuction(setupData: TestSetupData, setupTransactions: TransactionInfo[]): Promise<AuctionContract> {
    if (!this.auctionFactory) {
      throw new Error(ERROR_MESSAGES.AUCTION_DEPLOYER_NOT_INITIALIZED);
    }

    // Get the auctioned token and currency (tokens should already be deployed)
    const auctionedToken = this.getTokenByName(setupData.auctionParameters.auctionedToken);
    if (!auctionedToken) {
      throw new Error(ERROR_MESSAGES.AUCTIONED_TOKEN_NOT_FOUND(setupData.auctionParameters.auctionedToken));
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

      await this.transferToAuction(auctionedToken, auctionAddress, auctionAmount, setupTransactions);

      await this.callOnTokensReceived(setupTransactions);

      return this.auction;
    } catch (error: unknown) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      console.error(LOG_PREFIXES.ERROR, "Auction creation failed:", errorMessage);
      throw new Error(ERROR_MESSAGES.AUCTION_CREATION_FAILED(errorMessage));
    }
  }

  async transferToAuction(
    auctionedToken: TokenContract,
    auctionAddress: string,
    auctionAmount: bigint,
    setupTransactions: TransactionInfo[],
  ): Promise<void> {
    // Transfer tokens to the auction contract before calling onTokensReceived()
    const transferTx = await auctionedToken.getFunction("transfer").populateTransaction(auctionAddress, auctionAmount);
    setupTransactions.push({
      tx: transferTx,
      from: null,
      msg: `Transferred ${auctionAmount} tokens to auction`,
    });
  }

  async callOnTokensReceived(setupTransactions: TransactionInfo[]): Promise<void> {
    if (!this.auction) {
      throw new Error(ERROR_MESSAGES.AUCTION_NOT_DEPLOYED);
    }
    const onTokensReceivedTx = await this.auction.getFunction("onTokensReceived").populateTransaction();
    setupTransactions.push({
      tx: onTokensReceivedTx,
      from: null,
      msg: "Called onTokensReceived on auction",
    });
  }

  /**
   * Calculates auction parameters from setup data.
   * @param setupData - Test setup data containing auction parameters and environment
   * @param currencyAddress - The resolved currency address
   * @returns Auction configuration object
   */
  private calculateAuctionParameters(setupData: TestSetupData, currencyAddress: Address): AuctionConfig {
    const { auctionParameters, env } = setupData;

    const startBlock = BigInt(env.startBlock) + BigInt(env.offsetBlocks ?? 0);

    // Ensure auction start block is always greater than 1
    if (startBlock <= 1n) {
      throw new Error(
        `Auction start block must be greater than 1. Calculated start block: ${startBlock.toString()}. Please increase env.startBlock or env.startOffsetBlocks.`,
      );
    }

    const endBlock = startBlock + BigInt(auctionParameters.auctionDurationBlocks);
    const claimBlock = endBlock + BigInt(auctionParameters.claimDelayBlocks);

    // Handle auctionStepsData: use provided value or generate simple schedule
    let auctionStepsData: string;
    if (auctionParameters.auctionStepsData) {
      if (typeof auctionParameters.auctionStepsData === "string") {
        // Raw hex string provided
        auctionStepsData = auctionParameters.auctionStepsData;
      } else {
        // Array of StepData provided
        auctionStepsData = this.createAuctionStepsDataFromArray(auctionParameters.auctionStepsData);
      }
    } else {
      // No steps data provided, use simple linear schedule
      const blockDelta = parseInt(auctionParameters.auctionDurationBlocks.toString());
      const stepData: StepData[] = [
        {
          mpsPerBlock: Math.floor(MPS / blockDelta),
          blockDelta: blockDelta,
        },
      ];
      auctionStepsData = this.createAuctionStepsDataFromArray(stepData);
    }

    return {
      currency: currencyAddress,
      tokensRecipient: auctionParameters.tokensRecipient,
      fundsRecipient: auctionParameters.fundsRecipient,
      startBlock: Number(startBlock),
      endBlock: Number(endBlock),
      claimBlock: Number(claimBlock),
      tickSpacing:
        typeof auctionParameters.tickSpacing === "string"
          ? BigInt(auctionParameters.tickSpacing)
          : auctionParameters.tickSpacing,
      validationHook: auctionParameters.validationHook,
      floorPrice: auctionParameters.floorPrice,
      auctionStepsData: auctionStepsData,
    };
  }

  /**
   * Logs auction configuration details for debugging purposes.
   * @param config - The auction configuration object
   * @param auctionAmount - The amount of tokens to be auctioned
   * @param currencyAddress - The address of the currency token
   * @param auctionedToken - The token contract being auctioned
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
   * Encodes auction parameters into the format expected by the contract.
   * @param config - Auction configuration object
   * @returns Encoded auction parameters as a hex string
   * @throws Error if auction parameters type is not found in ABI
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
      throw new Error(ERROR_MESSAGES.AUCTION_PARAMETERS_NOT_FOUND);
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
   * Deploys the auction contract with the specified parameters.
   * @param auctionedToken - The token contract to be auctioned
   * @param auctionAmount - The amount of tokens to be auctioned
   * @param configData - Encoded auction configuration data
   * @param setupTransactions - Array to collect setup transaction information
   * @returns The deployed auction contract address
   * @throws Error if auction factory is not initialized or deployment fails
   */
  private async deployAuctionContract(
    auctionedToken: TokenContract,
    auctionAmount: bigint,
    configData: string,
    setupTransactions: TransactionInfo[],
  ): Promise<string> {
    if (!this.auctionFactory) {
      throw new Error(ERROR_MESSAGES.AUCTION_FACTORY_NOT_DEPLOYED);
    }

    const salt = this.ethers.keccak256(this.ethers.toUtf8Bytes("test-salt"));

    const auctionAddress = await (this.auctionFactory.initializeDistribution as any).staticCall(
      await auctionedToken.getAddress(),
      auctionAmount,
      configData,
      salt,
    );
    // Generate the transaction
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

  /**
   * Resolves a currency identifier to its address.
   * @param currency - Currency address or identifier
   * @returns The resolved currency address
   * @throws Error if currency is not found
   */
  async resolveCurrencyAddress(currency: Address | string): Promise<Address> {
    // If it's an address, return it directly
    if (currency.startsWith("0x")) {
      return currency as Address;
    }
    // Otherwise, look up the token by name
    const address = await this.getTokenAddress(currency);
    if (!address) {
      throw new Error(ERROR_MESSAGES.TOKEN_NOT_FOUND(currency));
    }
    return address;
  }

  /**
   * Calculates the auction amount for a given token.
   * @param tokenName - The name of the token
   * @param additionalTokens - Array of additional token configurations
   * @returns The calculated auction amount as a bigint
   * @throws Error if token configuration is not found
   */
  calculateAuctionAmount(tokenName: string, additionalTokens: AdditionalToken[]): bigint {
    const tokenConfig = additionalTokens.find((t) => t.name === tokenName);
    if (!tokenConfig) {
      throw new Error(ERROR_MESSAGES.TOKEN_NOT_FOUND(tokenName));
    }

    const totalSupply = BigInt(tokenConfig.totalSupply);
    const percentAuctioned = parseFloat(tokenConfig.percentAuctioned);
    return (totalSupply * BigInt(Math.floor(percentAuctioned * 100))) / BigInt(10000);
  }

  /**
   * Creates auction steps data from an array of StepData objects.
   * @param steps - Array of step configurations with mpsPerBlock and blockDelta
   * @returns Hex string of concatenated packed step data
   * @throws Error if steps don't sum to correct totals
   */
  createAuctionStepsDataFromArray(steps: StepData[]): string {
    console.log(LOG_PREFIXES.INFO, "Creating auction steps data from array of", steps.length, "steps");

    let hexParts: string[] = [];
    let totalMps = 0;
    let totalBlocks = 0;

    for (const step of steps) {
      const mps = step.mpsPerBlock;
      const blockDelta = step.blockDelta;

      // Pack mps (24 bits) and blockDelta (40 bits) into 8 bytes
      const packed = (BigInt(mps) << 40n) | BigInt(blockDelta);
      const hex = packed.toString(16).padStart(HEX_PADDING_LENGTH, "0");
      hexParts.push(hex);

      totalMps += mps * blockDelta;
      totalBlocks += blockDelta;

      console.log(LOG_PREFIXES.INFO, `  Step: mps=${mps}, blockDelta=${blockDelta}, hex=0x${hex}`);
    }

    console.log(LOG_PREFIXES.INFO, "Total MPS:", totalMps, "(should be", MPS + ")");
    console.log(LOG_PREFIXES.INFO, "Total blocks:", totalBlocks);

    // Validation: total mps should equal MPS constant
    if (totalMps !== MPS) {
      console.warn(
        LOG_PREFIXES.WARNING,
        `Warning: Total MPS (${totalMps}) doesn't equal required MPS (${MPS}). Auction may fail to deploy.`,
      );
    }

    return "0x" + hexParts.join("");
  }
  /**
   * Creates simple auction steps data for a given duration.
   * @param auctionDurationBlocks - The duration of the auction in blocks
   * @returns The encoded auction steps data
   */
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

  /**
   * Sets up initial balances for test environment.
   * @param setupData - Test setup data containing environment configuration
   * @param setupTransactions - Array to collect setup transaction information
   */
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
   * Sets up native currency balance for an address.
   * @param address - The address to set the balance for
   * @param amount - The amount in wei as a string
   */
  private async setupNativeCurrencyBalance(address: Address, amount: string): Promise<void> {
    const hexAmount = "0x" + BigInt(amount).toString(16);
    await hre.network.provider.send(METHODS.HARDHAT.SET_BALANCE, [address, hexAmount]);
    console.log(LOG_PREFIXES.SUCCESS, "Set native currency balance:", address, "=", amount, "wei");
  }

  /**
   * Sets a token balance at bootup for an address using token address.
   * @param address - The address to set the balance for
   * @param tokenAddress - The token contract address
   * @param amount - The amount to set
   * @param setupTransactions - Array to collect setup transaction information
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
   * Sets a token balance at bootup for an address using token name.
   * @param address - The address to set the balance for
   * @param tokenName - The name of the token
   * @param amount - The amount to set
   * @param setupTransactions - Array to collect setup transaction information
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
