import fs from 'fs';
import {
  Account,
  Contract,
  CallData,
  cairo,
  TypedContractV2,
  ProviderOrAccount,
  validateAndParseAddress,
} from 'starknet';

import { ABI } from '../abis/types/spSTRK';
import spSTRKAbi from '../abis/spSTRK.json';
import { getProvider } from '../utils/starknet';
import { toBigint } from '../utils/formatter';

export interface InitParams {
  owner: string;
  strk_token: string;
  dao_fee_basis_points: number;
  dev_fee_basis_points: number;
  min_stake_amount: bigint;
  unlock_period: number;
  claim_window: number;
}

export interface UnlockRequest {
  sp_strk_amount: bigint;
  min_strk_out: bigint;
  unlock_time: number;
  expiry_time: number;
}

export interface Stats {
  total_pooled_STRK: bigint;
  total_supply: bigint;
  exchange_rate: bigint;
  contract_balance: bigint;
  accumulated_dao_fees: bigint;
  accumulated_dev_fees: bigint;
  dao_fee_basis_points: number;
  dev_fee_basis_points: number;
}

export class SpSTRKContract {
  private readonly contract: TypedContractV2<typeof ABI>;
  private readonly provider: ProviderOrAccount;

  constructor(contractAddress: string, account: Account | null = null) {
    this.provider = account || getProvider();
    this.contract = new Contract({
      abi: spSTRKAbi,
      address: contractAddress,
      providerOrAccount: this.provider,
    }).typedv2(ABI);
  }

  static getCompiledSierra() {
    return JSON.parse(
      fs
        .readFileSync(`${__dirname}/../../../target/dev/sp_strk_spSTRK.contract_class.json`)
        .toString('ascii')
    );
  }

  static getCompiledCasm() {
    return JSON.parse(
      fs
        .readFileSync(
          `${__dirname}/../../../target/dev/sp_strk_spSTRK.compiled_contract_class.json`
        )
        .toString('ascii')
    );
  }

  // Serialize constructor calldata
  static getConstructorCalldata(params: InitParams): ReturnType<typeof CallData.compile> {
    // const contractCallData = new CallData(spSTRKAbi);
    // return contractCallData.compile('constructor', {
    //   owner: params.owner,
    //   strk_token: params.strk_token,
    //   dao_fee_basis_points: params.dao_fee_basis_points,
    //   dev_fee_basis_points: params.dev_fee_basis_points,
    //   min_stake_amount: cairo.uint256(params.min_stake_amount),
    //   unlock_period: params.unlock_period,
    //   claim_window: params.claim_window,
    // });

    return CallData.compile({
      owner: params.owner,
      strk_token: params.strk_token,
      dao_fee_basis_points: params.dao_fee_basis_points,
      dev_fee_basis_points: params.dev_fee_basis_points,
      min_stake_amount: cairo.uint256(params.min_stake_amount),
      unlock_period: params.unlock_period,
      claim_window: params.claim_window,
    });
  }

  /**
   * Deploy a new spSTRK contract
   */
  static async deploy(
    account: Account,
    classHash: string,
    params: InitParams
  ): Promise<ReturnType<typeof Account.prototype.deploy>> {
    return await account.deploy({
      classHash,
      constructorCalldata: SpSTRKContract.getConstructorCalldata(params),
    });
  }

  /**
   * Declare and deploy a new spSTRK contract
   */
  static async declareAndDeploy(
    account: Account,
    params: InitParams
  ): Promise<ReturnType<typeof Account.prototype.declareAndDeploy>> {
    return await account.declareAndDeploy({
      contract: SpSTRKContract.getCompiledSierra(),
      casm: SpSTRKContract.getCompiledCasm(),
      constructorCalldata: SpSTRKContract.getConstructorCalldata(params),
    });
  }

  /**
   * Declare new spSTRK contract
   */
  static async declare(account: Account): Promise<ReturnType<typeof Account.prototype.declare>> {
    return await account.declare({
      contract: SpSTRKContract.getCompiledSierra(),
      casm: SpSTRKContract.getCompiledCasm(),
    });
  }

  get address(): string {
    return this.contract.address;
  }

  /**
   * Get basic contract info
   */
  async info() {
    return await Promise.all([
      this.contract.name(),
      this.contract.symbol(),
      this.contract.decimals(),
      this.contract.totalSupply(),
      validateAndParseAddress(await this.contract.owner()),
      this.contract.is_paused(),
    ]);
  }

  /**
   * Get token balance of a user
   */
  async balanceOf(user: string): Promise<bigint> {
    const result = await this.contract.balanceOf(user);
    return toBigint(result);
  }

  /**
   * Check user's allowance
   */
  async allowance(owner: string, spender: string): Promise<bigint> {
    const result = await this.contract.allowance(owner, spender);
    return toBigint(result);
  }

  /**
   * Approve spSTRK tokens for spending
   */
  async approve(spender: string, amount: bigint): Promise<string> {
    const result = await this.contract.approve(spender, cairo.uint256(amount));
    await this.provider.waitForTransaction(result.transaction_hash);
    return result.transaction_hash;
  }

  /**
   * Transfer spSTRK tokens to another user
   */
  async transfer(recipient: string, amount: bigint): Promise<string> {
    const result = await this.contract.transfer(recipient, cairo.uint256(amount));
    await this.provider.waitForTransaction(result.transaction_hash);
    return result.transaction_hash;
  }

  /**
   * Stake STRK tokens to receive spSTRK
   */
  async stake(strkAmount: bigint, minSpStrkOut: bigint): Promise<string> {
    const result = await this.contract.stake(
      cairo.uint256(strkAmount),
      cairo.uint256(minSpStrkOut)
    );
    await this.provider.waitForTransaction(result.transaction_hash);
    return result.transaction_hash;
  }

  /**
   * Request to unlock spSTRK tokens
   */
  async requestUnlock(spStrkAmount: bigint, minStrkOut: bigint): Promise<string> {
    const result = await this.contract.request_unlock(
      cairo.uint256(spStrkAmount),
      cairo.uint256(minStrkOut)
    );
    await this.provider.waitForTransaction(result.transaction_hash);
    return result.transaction_hash;
  }

  /**
   * Claim unlocked tokens after cooldown period
   */
  async claimUnlock(): Promise<string> {
    const result = await this.contract.claim_unlock();
    await this.provider.waitForTransaction(result.transaction_hash);
    return result.transaction_hash;
  }

  /**
   * Cancel pending unlock request
   */
  async cancelUnlock(): Promise<string> {
    const result = await this.contract.cancel_unlock();
    await this.provider.waitForTransaction(result.transaction_hash);
    return result.transaction_hash;
  }

  /**
   * Get unlock request details
   */
  async getUnlockRequest(user: string): Promise<{
    request: UnlockRequest;
    strk_amount: bigint;
    is_ready: boolean;
    is_expired: boolean;
  }> {
    const result = await this.contract.get_unlock_request(user);
    const request = result[0] as any;

    return {
      request: {
        sp_strk_amount: toBigint(request.sp_strk_amount),
        min_strk_out: toBigint(request.min_strk_out),
        unlock_time: Number(request.unlock_time),
        expiry_time: Number(request.expiry_time),
      },
      strk_amount: toBigint(result[1]),
      is_ready: Boolean(result[2]),
      is_expired: Boolean(result[3]),
    };
  }

  /**
   * Get exchange rate (STRK per spSTRK)
   */
  async getExchangeRate(): Promise<bigint> {
    const result = await this.contract.get_exchange_rate();
    return toBigint(result);
  }

  /**
   * Preview how much spSTRK you'll receive for staking
   */
  async previewStake(strkAmount: bigint): Promise<bigint> {
    const result = await this.contract.preview_stake(cairo.uint256(strkAmount));
    return toBigint(result);
  }

  /**
   * Preview how much STRK you'll receive for unlocking
   */
  async previewUnlock(spStrkAmount: bigint): Promise<bigint> {
    const result = await this.contract.preview_unlock(cairo.uint256(spStrkAmount));
    return toBigint(result);
  }

  /**
   * Get contract statistics
   */
  async getStats(): Promise<Stats> {
    const result = await this.contract.get_stats();

    return {
      total_pooled_STRK: toBigint(result[0]),
      total_supply: toBigint(result[1]),
      exchange_rate: toBigint(result[2]),
      contract_balance: toBigint(result[3]),
      accumulated_dao_fees: toBigint(result[4]),
      accumulated_dev_fees: toBigint(result[5]),
      dao_fee_basis_points: Number(result[6]),
      dev_fee_basis_points: Number(result[7]),
    };
  }

  /**
   * Add rewards (owner only)
   */
  async addRewards(strkAmount: bigint): Promise<string> {
    const result = await this.contract.add_rewards(cairo.uint256(strkAmount));
    await this.provider.waitForTransaction(result.transaction_hash);
    return result.transaction_hash;
  }

  /**
   * Collect DAO fees (owner only)
   */
  async collectDaoFees(): Promise<string> {
    const result = await this.contract.collect_dao_fees();
    await this.provider.waitForTransaction(result.transaction_hash);
    return result.transaction_hash;
  }

  /**
   * Collect dev fees (owner only)
   */
  async collectDevFees(): Promise<string> {
    const result = await this.contract.collect_dev_fees();
    await this.provider.waitForTransaction(result.transaction_hash);
    return result.transaction_hash;
  }

  /**
   * Pause contract (owner only)
   */
  async pause(): Promise<string> {
    const result = await this.contract.pause();
    await this.provider.waitForTransaction(result.transaction_hash);
    return result.transaction_hash;
  }

  /**
   * Unpause contract (owner only)
   */
  async unpause(): Promise<string> {
    const result = await this.contract.unpause();
    await this.provider.waitForTransaction(result.transaction_hash);
    return result.transaction_hash;
  }

  /**
   * Upgrade contract (owner only)
   */
  async upgrade(newClassHash: string): Promise<string> {
    const result = await this.contract.upgrade(newClassHash);
    await this.provider.waitForTransaction(result.transaction_hash);
    return result.transaction_hash;
  }
}
