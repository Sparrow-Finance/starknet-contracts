import { Account, RpcProvider, constants } from 'starknet';
import { config } from '../config';

export function getProvider(): RpcProvider {
  return new RpcProvider({ nodeUrl: config.rpcUrl, blockIdentifier: 'latest' });
}

export function getAccount(): Account {
  return new Account({
    provider: getProvider(),
    address: config.accountAddress,
    signer: config.privateKey,
  });
}

export function getChainId(): constants.StarknetChainId {
  switch (config.network) {
    case 'mainnet':
      return constants.StarknetChainId.SN_MAIN;
    case 'sepolia':
      return constants.StarknetChainId.SN_SEPOLIA;
    default:
      return constants.StarknetChainId.SN_SEPOLIA; // Use for devnet too
  }
}
