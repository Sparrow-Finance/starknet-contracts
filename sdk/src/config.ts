import dotenv from 'dotenv';

dotenv.config();

export const config = {
  network: process.env.NETWORK || 'devnet',
  rpcUrl: process.env.STARKNET_RPC_URL || 'http://127.0.0.1:5050',
  accountAddress: process.env.ACCOUNT_ADDRESS!,
  privateKey: process.env.PRIVATE_KEY!,
  strkAddress: process.env.STRK_ADDRESS!,
  spStrkAddress: process.env.SP_STRK_ADDRESS!,
};
