import { config } from '../../config';
import { SpSTRKContract } from '../../contracts/spSTRK';
import { getAccount } from '../../utils/starknet';

export async function collectDAOFees() {
  const account = getAccount();

  const spSTRK = new SpSTRKContract(config.spStrkAddress, account);

  const collectTx = await spSTRK.collectDaoFees();
  console.log(`DAO fees collected: ${collectTx}`);
}

export async function collectDeveloperFees() {
  const account = getAccount();

  const spSTRK = new SpSTRKContract(config.spStrkAddress, account);

  const collectTx = await spSTRK.collectDevFees();
  console.log(`Developer fees collected: ${collectTx}`);
}
