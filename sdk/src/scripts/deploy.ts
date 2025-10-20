import { SpSTRKContract } from '../contracts/spSTRK';
import { getAccount } from '../utils/starknet';

async function deploy() {
  const account = getAccount();
  const { declare, deploy } = await SpSTRKContract.declareAndDeploy(account, {
    owner: '0x00f4e5d2310fC00fA88653E1445A1cf1734E67765ba97A28A793239a0fAF5483',
    strk_token: '0x4718F5A0FC34CC1AF16A1CDEE98FFB20C31F5CD61D6AB07201858F4287C938D',
    min_stake_amount: 10000000000000000n,
    dao_fee_basis_points: 500, // 5%
    dev_fee_basis_points: 300, // 3%
    unlock_period: 60, // 1 minute
    claim_window: 604800, // 1 week
  });

  console.log('Declared SpSTRK at:', declare.class_hash);
  console.log('Transaction hash:', declare.transaction_hash);
  console.log('\n');
  console.log('Deployed SpSTRK at:', deploy.contract_address);
  console.log('Transaction hash:', deploy.transaction_hash);
}

deploy();
