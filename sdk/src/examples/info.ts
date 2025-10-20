import { config } from '../config';
import { SpSTRKContract } from '../contracts/spSTRK';

export async function getInfo() {
  const spSTRK = new SpSTRKContract(config.spStrkAddress);

  const [name, symbol, decimals, totalSupply, owner, paused] = await spSTRK.info();

  console.log('spSTRK Info:');
  console.log(`Name: ${name}`);
  console.log(`Symbol: ${symbol}`);
  console.log(`Decimals: ${decimals}`);
  console.log(`Total Supply: ${totalSupply}`);
  console.log(`Owner: ${owner}`);
  console.log(`Paused: ${paused}`);
}
