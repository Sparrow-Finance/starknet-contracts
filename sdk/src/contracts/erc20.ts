import {
  Account,
  Contract,
  cairo,
  ProviderOrAccount,
  TypedContractV2,
  shortString,
} from 'starknet';

import erc20Abi from '../abis/erc20.json';
import { ABI } from '../abis/types/erc20';
import { getProvider } from '../utils/starknet';
import { toBigint } from '../utils/formatter';

export class ERC20Contract {
  private contract: TypedContractV2<typeof ABI>;
  private readonly provider: ProviderOrAccount;

  constructor(address: string, account?: Account) {
    this.provider = account || getProvider();
    this.contract = new Contract({
      abi: erc20Abi,
      address,
      providerOrAccount: this.provider,
    }).typedv2(ABI);
  }

  async name(): Promise<string> {
    return this.contract.name();
  }

  async symbol(): Promise<string> {
    return this.contract.symbol();
  }

  async decimals(): Promise<number> {
    const result = await this.contract.decimals();
    return typeof result === 'number' ? result : Number(result);
  }

  async totalSupply(): Promise<bigint> {
    const result = await this.contract.total_supply();
    return toBigint(result);
  }

  async balanceOf(account: string): Promise<bigint> {
    const result = await this.contract.balance_of(account);
    return toBigint(result);
  }

  async allowance(owner: string, spender: string): Promise<bigint> {
    const result = await this.contract.allowance(owner, spender);
    return toBigint(result);
  }

  async approve(spender: string, amount: bigint): Promise<string> {
    const result = await this.contract.approve(spender, cairo.uint256(amount));
    await this.provider.waitForTransaction(result.transaction_hash);
    return result.transaction_hash;
  }

  async transfer(recipient: string, amount: bigint): Promise<string> {
    const result = await this.contract.transfer(recipient, cairo.uint256(amount));
    await this.provider.waitForTransaction(result.transaction_hash);
    return result.transaction_hash;
  }
}
