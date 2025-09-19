import { TestSetupData, Address } from '../schemas/TestSetupSchema';
import { Contract } from "ethers";
import mockTokenArtifact from '../../../out/WorkingCustomMockToken.sol/WorkingCustomMockToken.json';
import auctionArtifact from '../../../out/Auction.sol/Auction.json';
import hre from "hardhat";
import { 
  NATIVE_CURRENCY_ADDRESS, 
  MPS,
  MAX_SYMBOL_LENGTH,
  HEX_PADDING_LENGTH,
  DEFAULT_TOTAL_SUPPLY,
  ERROR_MESSAGES,
  LOG_PREFIXES 
} from './constants';
import { logger } from './logger';
import { 
  AuctionContract, 
  TokenContract, 
  AuctionFactoryContract, 
  AuctionConfig,
  AuctionDeploymentError 
} from './types';

export interface TokenConfig {
  name: string;
  decimals: string;
  totalSupply: string;
  percentAuctioned: string;
}

export class AuctionDeployer {
  private ethers: typeof hre.ethers;
  private auctionFactory: AuctionFactoryContract | undefined;
  private auction: AuctionContract | undefined;
  private tokens: Map<string, TokenContract> = new Map(); // Map of token name -> contract instance

  constructor() {
    this.ethers = hre.ethers;
  }

  /**
   * Initialize the deployer with tokens and factory
   * This should be called once per test setup
   */
  async initialize(setupData: TestSetupData): Promise<void> {
    // Deploy auction factory
    await this.deployAuctionFactory();
    
    // Deploy all tokens once
    await this.deployAdditionalTokens(setupData.additionalTokens);
    
    logger.info(LOG_PREFIXES.SUCCESS, 'AuctionFactory deployed. Additional Tokens Deployer', setupData.additionalTokens.length, 'tokens');
  }

  async deployAdditionalTokens(additionalTokens: TokenConfig[]): Promise<void> {
    logger.info(LOG_PREFIXES.DEPLOY, 'Deploying additional tokens...');
    
    for (const tokenConfig of additionalTokens) {
      const token = await this.deployToken(tokenConfig);
      this.tokens.set(tokenConfig.name, token);
      logger.info(LOG_PREFIXES.SUCCESS, 'Deployed', tokenConfig.name, ':', await token.getAddress());
    }
  }

  /**
   * Deploy a single token
   */
  private async deployToken(tokenConfig: TokenConfig): Promise<TokenContract> {
    // Load artifact directly from Foundry's out directory
    const mockToken = await this.ethers.getContractFactory(mockTokenArtifact.abi, mockTokenArtifact.bytecode.object);
    const symbol = tokenConfig.name.substring(0, Math.min(MAX_SYMBOL_LENGTH, tokenConfig.name.length)).toUpperCase();
    const decimals = parseInt(tokenConfig.decimals);
    const totalSupply = tokenConfig.totalSupply || DEFAULT_TOTAL_SUPPLY;
    
    const token = await mockToken.deploy(tokenConfig.name, symbol, decimals, totalSupply);
    return token as TokenContract;
  }

  getTokenByName(tokenName: string): TokenContract | undefined {
    return this.tokens.get(tokenName);
  }

  async getTokenAddress(tokenName: string): Promise<Address | null> {
    const token = this.tokens.get(tokenName);
    return token ? await token.getAddress() as Address : null;
  }

  async deployAuctionFactory(): Promise<AuctionFactoryContract> {
    // Load artifact directly from Foundry's out directory
    const auctionFactoryArtifact = require('../../../out/AuctionFactory.sol/AuctionFactory.json');
    const AuctionFactory = await this.ethers.getContractFactory(auctionFactoryArtifact.abi, auctionFactoryArtifact.bytecode.object);
    this.auctionFactory = await AuctionFactory.deploy() as AuctionFactoryContract;
    return this.auctionFactory;
  }

  async createAuction(setupData: TestSetupData): Promise<AuctionContract> {
    if (!this.auctionFactory) {
      throw new AuctionDeploymentError('AuctionDeployer not initialized. Call initialize() first.');
    }

    // Get the auctioned token and currency (tokens should already be deployed)
    const auctionedToken = this.getTokenByName(setupData.auctionParameters.auctionedToken);
    if (!auctionedToken) {
      throw new AuctionDeploymentError(
        ERROR_MESSAGES.AUCTIONED_TOKEN_NOT_FOUND(setupData.auctionParameters.auctionedToken)
      );
    }

    const currencyAddress = await this.resolveCurrencyAddress(setupData.auctionParameters.currency as Address);
    
    // Calculate auction parameters
    const auctionConfig = this.calculateAuctionParameters(setupData);
    const auctionAmount = this.calculateAuctionAmount(setupData.auctionParameters.auctionedToken, setupData.additionalTokens);
    
    // Log auction configuration
    this.logAuctionConfiguration(auctionConfig, auctionAmount, currencyAddress, auctionedToken);
    
    try {
      // Encode and deploy auction
      const configData = this.encodeAuctionParameters(auctionConfig);
      const auctionAddress = await this.deployAuctionContract(auctionedToken, auctionAmount, configData);
      
      this.auction = await this.ethers.getContractAt(auctionArtifact.abi, auctionAddress) as AuctionContract;
      return this.auction;
    } catch (error: any) {
      logger.error(LOG_PREFIXES.ERROR, 'Auction creation failed:', error.message);
      throw new AuctionDeploymentError('Auction creation failed', { originalError: error });
    }
  }

  /**
   * Calculate auction timing parameters
   */
  private calculateAuctionParameters(setupData: TestSetupData): AuctionConfig {
    const { auctionParameters, env } = setupData;
    
    const startBlock = BigInt(env.startBlock) + BigInt(auctionParameters.startOffsetBlocks);
    const endBlock = startBlock + BigInt(auctionParameters.auctionDurationBlocks);
    const claimBlock = endBlock + BigInt(auctionParameters.claimDelayBlocks);
    
    return {
      currency: setupData.auctionParameters.currency as Address,
      tokensRecipient: auctionParameters.tokensRecipient,
      fundsRecipient: auctionParameters.fundsRecipient,
      startBlock: Number(startBlock),
      endBlock: Number(endBlock),
      claimBlock: Number(claimBlock),
      graduationThresholdMps: Number(auctionParameters.graduationThresholdMps),
      tickSpacing: Number(auctionParameters.tickSpacing),
      validationHook: auctionParameters.validationHook,
      floorPrice: auctionParameters.floorPrice,
      auctionStepsData: this.createSimpleAuctionStepsData(auctionParameters.auctionDurationBlocks)
    };
  }

  /**
   * Log auction configuration for debugging
   */
  private async logAuctionConfiguration(
    config: AuctionConfig, 
    auctionAmount: bigint, 
    currencyAddress: Address, 
    auctionedToken: TokenContract
  ): Promise<void> {
    const currentBlock = await this.ethers.provider.getBlockNumber();
    
    logger.info(LOG_PREFIXES.CONFIG, 'Current block number:', currentBlock);
    logger.info(LOG_PREFIXES.CONFIG, 'Calculated auction startBlock:', config.startBlock);
    logger.info(LOG_PREFIXES.CONFIG, 'Calculated auction endBlock:', config.endBlock);
    logger.info(LOG_PREFIXES.CONFIG, 'Calculated auction claimBlock:', config.claimBlock);
    logger.info(LOG_PREFIXES.CONFIG, 'Auction amount:', auctionAmount.toString());
    logger.info(LOG_PREFIXES.CONFIG, 'Currency address:', currencyAddress);
    logger.info(LOG_PREFIXES.CONFIG, 'Auctioned token address:', await auctionedToken.getAddress());
  }

  /**
   * Encode auction parameters for contract deployment
   */
  private encodeAuctionParameters(config: AuctionConfig): string {
    // Extract AuctionParameters struct definition from the auction artifact
    const auctionParametersType = auctionArtifact.abi.find((item: any) => 
      item.type === 'constructor' && 
      item.inputs && 
      item.inputs.some((input: any) => input.internalType === 'struct AuctionParameters')
    )?.inputs.find((input: any) => input.internalType === 'struct AuctionParameters');

    if (!auctionParametersType) {
      throw new AuctionDeploymentError(ERROR_MESSAGES.AUCTION_PARAMETERS_NOT_FOUND);
    }

    // Construct the tuple type string from the ABI components
    const components = (auctionParametersType as any).components.map((comp: any) => 
      `${comp.type} ${comp.name}`
    ).join(', ');
    const tupleType = `tuple(${components})`;
    
    const configData = this.ethers.AbiCoder.defaultAbiCoder().encode(
      [tupleType],
      [config]
    );

    logger.info(LOG_PREFIXES.CONFIG, 'Config data length:', configData.length);
    return configData;
  }

  /**
   * Deploy the auction contract
   */
  private async deployAuctionContract(
    auctionedToken: TokenContract, 
    auctionAmount: bigint, 
    configData: string
  ): Promise<string> {
    const salt = this.ethers.keccak256(this.ethers.toUtf8Bytes("test-salt"));
    
    const auctionAddress = await (this.auctionFactory!.initializeDistribution as any).staticCall(
      await auctionedToken.getAddress(),
      auctionAmount,
      configData,
      salt
    );
    
    // Execute the actual transaction
    const tx = await this.auctionFactory!.initializeDistribution(
      await auctionedToken.getAddress(),
      auctionAmount,
      configData,
      salt
    );
    await tx.wait();
    
    return auctionAddress;
  }

  async resolveCurrencyAddress(currency: Address): Promise<Address> {
    // If it's an address, return it directly
    if (currency.startsWith('0x')) {
      return currency;
    }
    // Otherwise, look up the token by name
    const address = await this.getTokenAddress(currency);
    if (!address) {
      throw new AuctionDeploymentError(ERROR_MESSAGES.TOKEN_NOT_FOUND(currency));
    }
    return address;
  }

  calculateAuctionAmount(tokenName: string, additionalTokens: TokenConfig[]): bigint {
    const tokenConfig = additionalTokens.find(t => t.name === tokenName);
    if (!tokenConfig) {
      throw new AuctionDeploymentError(ERROR_MESSAGES.TOKEN_NOT_FOUND(tokenName));
    }
    
    const totalSupply = BigInt(tokenConfig.totalSupply);
    const percentAuctioned = parseFloat(tokenConfig.percentAuctioned);
    return totalSupply * BigInt(Math.floor(percentAuctioned * 100)) / BigInt(10000);
  }

  createSimpleAuctionStepsData(auctionDurationBlocks: number): string {
    // Create a simple auction steps data that satisfies the validation
    // Format: each step is 8 bytes (uint64): 3 bytes mps + 5 bytes blockDelta
    // We need: sumMps = 1e7 (MPS constant) and sumBlockDelta = auctionDurationBlocks
    
    const blockDelta = parseInt(auctionDurationBlocks.toString());
    const mps = Math.floor(MPS / blockDelta); // mps * blockDelta should equal MPS
    
    logger.info(LOG_PREFIXES.INFO, 'Creating auction steps data:');
    logger.info(LOG_PREFIXES.INFO, 'MPS:', MPS);
    logger.info(LOG_PREFIXES.INFO, 'blockDelta:', blockDelta);
    logger.info(LOG_PREFIXES.INFO, 'mps:', mps);
    
    // Pack mps (24 bits) and blockDelta (40 bits) into 8 bytes
    // mps goes in the upper 24 bits, blockDelta in the lower 40 bits
    const packed = (BigInt(mps) << 40n) | BigInt(blockDelta);
    
    // Convert to hex string with proper padding (8 bytes = 16 hex chars)
    const hex = packed.toString(16).padStart(HEX_PADDING_LENGTH, '0');
    const result = '0x' + hex;
    
    logger.info(LOG_PREFIXES.INFO, 'packed:', packed.toString());
    logger.info(LOG_PREFIXES.INFO, 'hex:', result);
    
    return result;
  }

  async setupBalances(setupData: TestSetupData): Promise<void> {
    const { env } = setupData;
    if (!env.balances) return;

    logger.info(LOG_PREFIXES.ASSERTION, 'Setting up balances...');

    for (const balance of env.balances) {
      if (balance.token === NATIVE_CURRENCY_ADDRESS) {
        await this.setupNativeCurrencyBalance(balance.address, balance.amount);
      } else if (balance.token.startsWith('0x')) {
        await this.setupTokenBalanceByAddress(balance.address, balance.token as Address, balance.amount);
      } else {
        await this.setupTokenBalanceByName(balance.address, balance.token, balance.amount);
      }
    }
  }

  /**
   * Setup native currency balance
   */
  private async setupNativeCurrencyBalance(address: Address, amount: string): Promise<void> {
    const hexAmount = '0x' + BigInt(amount).toString(16);
    await hre.network.provider.send('hardhat_setBalance', [address, hexAmount]);
    logger.info(LOG_PREFIXES.SUCCESS, 'Set native currency balance:', address, '=', amount, 'wei');
  }

  /**
   * Setup token balance by contract address
   */
  private async setupTokenBalanceByAddress(address: Address, tokenAddress: Address, amount: string): Promise<void> {
    let token: TokenContract | null = null;
    for (const [name, tokenContract] of this.tokens) {
      if (await tokenContract.getAddress() === tokenAddress) {
        token = tokenContract;
        break;
      }
    }
    
    if (token) {
      await token.mint(address, amount);
      logger.info(LOG_PREFIXES.SUCCESS, 'Minted', amount, 'tokens to', address, '(', await token.getAddress(), ')');
    } else {
      logger.warn(LOG_PREFIXES.WARNING, 'Token not found for address:', tokenAddress);
    }
  }

  /**
   * Setup token balance by token name
   */
  private async setupTokenBalanceByName(address: Address, tokenName: string, amount: string): Promise<void> {
    const token = this.getTokenByName(tokenName);
    if (token) {
      await token.mint(address, amount);
      logger.info(LOG_PREFIXES.SUCCESS, 'Minted', amount, tokenName, 'to', address);
    } else {
      logger.warn(LOG_PREFIXES.WARNING, 'Token not found:', tokenName);
    }
  }
}
