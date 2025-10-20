import { config } from '../config';
import { SpSTRKContract } from '../contracts/spSTRK';
import { getAccount } from '../utils/starknet';
import { formatUnits } from '../utils/formatter';

export async function getUnlockRequest() {
  const account = getAccount();

  const spSTRK = new SpSTRKContract(config.spStrkAddress, account);

  const result = await spSTRK.getUnlockRequest(account.address);
  console.log('Unlock Request Details');
  console.log(`spSTRK Amount: ${formatUnits(result.request.sp_strk_amount)}`);
  console.log(`min STRK Amount: ${formatUnits(result.request.min_strk_out)}`);
  console.log(`STRK Amount: ${formatUnits(result.strk_amount)}`);
  console.log(
    `Unlock Time: ${new Date(Number(result.request.unlock_time) * 1000).toLocaleString()}`
  );
  console.log(
    `Expiry Time: ${new Date(Number(result.request.expiry_time) * 1000).toLocaleString()}`
  );
  console.log(`Is Ready: ${result.is_ready}`);
  console.log(`Is Expired: ${result.is_expired}`);
}
