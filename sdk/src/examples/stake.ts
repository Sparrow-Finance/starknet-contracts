import { config } from '../config';
import { SpSTRKContract } from '../contracts/spSTRK';
import { ERC20Contract } from '../contracts/erc20';
import { getAccount } from '../utils/starknet';
import { parseUnits } from '../utils/formatter';

export async function stake() {
  const account = getAccount();
  const amountToStake = parseUnits('1'); // Amount in wei (1 STRK)

  const strk = new ERC20Contract(config.strkAddress, account);
  const spSTRK = new SpSTRKContract(config.spStrkAddress, account);

  const allowance = await strk.allowance(account.address, spSTRK.address);
  console.log(`Current STRK allowance for spSTRK: ${allowance}`);

  if (allowance < amountToStake) {
    console.log(`Approving ${amountToStake} STRK for spSTRK contract...`);
    const approveTx = await strk.approve(spSTRK.address, amountToStake);
    console.log(`Approved: ${approveTx}`);
  }

  console.log(`Staking ${amountToStake} STRK for spSTRK...`);
  const minSpStrkOut = 0n; // Set to 0 for simplicity; in production, calculate based on slippage tolerance
  const stakeTx = await spSTRK.stake(amountToStake, minSpStrkOut);
  console.log(`Staked: ${stakeTx}`);
}
