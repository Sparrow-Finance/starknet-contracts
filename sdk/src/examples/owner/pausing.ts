import { config } from '../../config';
import { SpSTRKContract } from '../../contracts/spSTRK';
import { getAccount } from '../../utils/starknet';

export async function pause() {
  const account = getAccount();

  const spSTRK = new SpSTRKContract(config.spStrkAddress, account);

  const pauseTx = await spSTRK.pause();
  console.log(`Contract paused: ${pauseTx}`);
}

export async function unpause() {
  const account = getAccount();

  const spSTRK = new SpSTRKContract(config.spStrkAddress, account);

  const unpauseTx = await spSTRK.unpause();
  console.log(`Contract unpaused: ${unpauseTx}`);
}
