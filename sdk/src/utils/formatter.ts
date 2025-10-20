import { uint256, Uint256 } from 'starknet';

export function toBigint(result: number | bigint | boolean | string | object | Uint256): bigint {
  if (typeof result === 'boolean') {
    return result ? BigInt(1) : BigInt(0);
  } else if (typeof result === 'bigint') {
    return result;
  } else if (typeof result === 'number' || typeof result === 'string') {
    return BigInt(result);
  } else if (typeof result === 'object' && result !== null) {
    throw new Error('Cannot convert object to bigint');
  }
  return uint256.uint256ToBN(result);
}

export function parseUnits(amount: string, decimals: number = 18): bigint {
  return BigInt(amount) * 10n ** BigInt(decimals);
}

export function formatUnits(amount: bigint, decimals: number = 18): string {
  return (Number(amount) / 10 ** decimals).toString();
}
