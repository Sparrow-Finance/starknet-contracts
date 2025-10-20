import { config } from '../config';
import { SpSTRKContract } from '../contracts/spSTRK';
import { getAccount } from '../utils/starknet';

async function upgrade() {
  const account = getAccount();
  const result = await SpSTRKContract.declare(account);

  console.log('New spSTRK class hash:', result.class_hash);
  console.log('Transaction hash:', result.transaction_hash);

  const spSTRK = new SpSTRKContract(config.spStrkAddress, account);
  await spSTRK.upgrade(result.class_hash);
  console.log('spSTRK contract upgraded to new class hash:', result.class_hash);
}

upgrade();
