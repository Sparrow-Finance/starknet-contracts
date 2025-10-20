import {
  Account,
  ec,
  json,
  stark,
  RpcProvider,
  hash,
  CallData,
  CairoOption,
  CairoOptionVariant,
  CairoCustomEnum,
} from 'starknet';

import { config } from '../config';
import { getProvider } from '../utils/starknet';

async function deployArgentXAccount() {
  //new Argent X account v0.4.0
  const argentXaccountClassHash =
    '0x036078334509b514626504edc9fb252328d1a240e4e948bef8d0c08dff45927f';

  // Generate public and private key pair.
  const privateKeyAX = config.privateKey;
  console.log('AX_ACCOUNT_PRIVATE_KEY=', privateKeyAX);
  const starkKeyPubAX = config.accountAddress;
  console.log('AX_ACCOUNT_PUBLIC_KEY=', starkKeyPubAX);

  // Calculate future address of the ArgentX account
  const axSigner = new CairoCustomEnum({ Starknet: { pubkey: starkKeyPubAX } });
  const axGuardian = new CairoOption<unknown>(CairoOptionVariant.None);

  const AXConstructorCallData = CallData.compile({
    owner: axSigner,
    guardian: axGuardian,
  });
  const AXcontractAddress = hash.calculateContractAddressFromHash(
    starkKeyPubAX,
    argentXaccountClassHash,
    AXConstructorCallData,
    0
  );
  console.log('Precalculated account address=', AXcontractAddress);

  const accountAX = new Account({
    provider: getProvider(),
    address: AXcontractAddress,
    signer: privateKeyAX,
  });

  const deployAccountPayload = {
    classHash: argentXaccountClassHash,
    constructorCalldata: AXConstructorCallData,
    contractAddress: AXcontractAddress,
    addressSalt: starkKeyPubAX,
  };

  const { transaction_hash: AXdAth, contract_address: AXcontractFinalAddress } =
    await accountAX.deployAccount(deployAccountPayload);
  console.log('✅ ArgentX wallet deployed at:', AXcontractFinalAddress);
}

async function deployOZAccount() {
  // new Open Zeppelin account v0.17.0
  // Generate public and private key pair.
  const privateKey = config.privateKey;
  console.log('New OZ account:\nprivateKey=', privateKey);
  const starkKeyPub = config.accountAddress;
  console.log('publicKey=', starkKeyPub);

  const OZaccountClassHash = '0x540d7f5ec7ecf317e68d48564934cb99259781b1ee3cedbbc37ec5337f8e688';
  // Calculate future address of the account
  const OZaccountConstructorCallData = CallData.compile({ publicKey: starkKeyPub });
  const OZcontractAddress = hash.calculateContractAddressFromHash(
    starkKeyPub,
    OZaccountClassHash,
    OZaccountConstructorCallData,
    0
  );
  console.log('Precalculated account address=', OZcontractAddress);

  const myProvider = getProvider();

  const OZaccount = new Account({
    provider: myProvider,
    address: OZcontractAddress,
    signer: privateKey,
  });

  const { transaction_hash, contract_address } = await OZaccount.deployAccount({
    classHash: OZaccountClassHash,
    constructorCalldata: OZaccountConstructorCallData,
    addressSalt: starkKeyPub,
  });

  await myProvider.waitForTransaction(transaction_hash);
  console.log('✅ New OpenZeppelin account created.\n   address =', contract_address);
}

// deployOZAccount();

deployArgentXAccount();
