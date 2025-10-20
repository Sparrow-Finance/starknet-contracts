import { config } from '../config';
import { SpSTRKContract } from '../contracts/spSTRK';
import { getAccount } from '../utils/starknet';

export async function claimUnlockRequest() {
  const account = getAccount();

  const spSTRK = new SpSTRKContract(config.spStrkAddress, account);

  const claimTx = await spSTRK.claimUnlock();
  console.log(`Unlock requests claimed: ${claimTx}`);
}
