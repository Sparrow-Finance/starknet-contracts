import { config } from '../../config';
import { SpSTRKContract } from '../../contracts/spSTRK';
import { getAccount } from '../../utils/starknet';

export async function transferOwnership() {
  const account = getAccount();

  const newOwner = '0x073eb5658ce8291f795aad5584000dfc52aa197600b4df98568b4d480b9fdb65'; // Replace with the new owner's address
  const spSTRK = new SpSTRKContract(config.spStrkAddress, account);

  const transferTx = await spSTRK.transferOwnership(newOwner);
  console.log(`Ownership transferred: ${transferTx}`);
}
