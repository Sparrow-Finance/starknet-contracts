import { config } from '../config';
import { SpSTRKContract } from '../contracts/spSTRK';
import { getAccount } from '../utils/starknet';

export async function unlockRequest() {
  const account = getAccount();

  const spSTRK = new SpSTRKContract(config.spStrkAddress, account);

  const spSTRKBalance = await spSTRK.balanceOf(account.address);
  if (spSTRKBalance === 0n) {
    throw new Error('No spSTRK balance to unlock');
  }

  console.log(`Requesting unlock of ${spSTRKBalance} spSTRK...`);
  const unlockTx = await spSTRK.requestUnlock(spSTRKBalance, 0n);
  console.log(`Unlock requested: ${unlockTx}`);
}
