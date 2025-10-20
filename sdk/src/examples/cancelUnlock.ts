import { config } from '../config';
import { SpSTRKContract } from '../contracts/spSTRK';
import { getAccount } from '../utils/starknet';

export async function cancelUnlockRequest() {
  const account = getAccount();

  const spSTRK = new SpSTRKContract(config.spStrkAddress, account);

  const cancelTx = await spSTRK.cancelUnlock();
  console.log(`Unlock requests cancelled: ${cancelTx}`);
}
