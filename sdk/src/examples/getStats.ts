import { config } from '../config';
import { SpSTRKContract } from '../contracts/spSTRK';
import { getAccount } from '../utils/starknet';

export async function getStats() {
  const account = getAccount();

  const spSTRK = new SpSTRKContract(config.spStrkAddress, account);

  const result = await spSTRK.getStats();
  console.log('Stats Details:', result);
}
