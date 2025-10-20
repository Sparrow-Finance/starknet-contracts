import { config } from '../../config';
import { SpSTRKContract } from '../../contracts/spSTRK';
import { ERC20Contract } from '../../contracts/erc20';
import { getAccount } from '../../utils/starknet';
import { parseUnits } from '../../utils/formatter';

export async function addRewards() {
  const account = getAccount();
  const rewardAmount = parseUnits('1'); // Amount in wei (1 STRK)

  const strk = new ERC20Contract(config.strkAddress, account);
  const spSTRK = new SpSTRKContract(config.spStrkAddress, account);

  const allowance = await strk.allowance(account.address, spSTRK.address);
  console.log(`Current STRK allowance for spSTRK: ${allowance}`);

  if (allowance < rewardAmount) {
    console.log(`Approving ${rewardAmount} STRK for spSTRK contract...`);
    const approveTx = await strk.approve(spSTRK.address, rewardAmount);
    console.log(`Approved: ${approveTx}`);
  }

  console.log(`Adding ${rewardAmount} STRK for spSTRK...`);
  const addRewardsTx = await spSTRK.addRewards(rewardAmount);
  console.log(`Added rewards: ${addRewardsTx}`);
}
