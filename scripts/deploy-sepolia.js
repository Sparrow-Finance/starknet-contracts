const { Account, RpcProvider, Contract, json, stark, uint256, CallData, constants } = require("starknet");
const fs = require("fs");
const path = require("path");
require("dotenv").config();

async function main() {
    console.log("🚀 Starting spSTRK Deployment to Sepolia Testnet...\n");

    // Load environment variables
    const privateKey = process.env.PRIVATE_KEY;
    const rpcUrl = process.env.STARKNET_SEPOLIA_RPC_URL;
    const ownerAddress = process.env.OWNER_ADDRESS;
    const unlockPeriod = process.env.UNLOCK_PERIOD;
    const daoFeeBps = process.env.DAO_FEE_BPS;
    const devFeeBps = process.env.DEV_FEE_BPS;
    const minStakeAmount = process.env.MIN_STAKE_AMOUNT;
    const claimWindow = process.env.CLAIM_WINDOW;
    const strkToken = process.env.STRK_TOKEN_SEPOLIA || "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d";

    // Validate environment variables
    if (!privateKey) {
        throw new Error("❌ PRIVATE_KEY not found in .env file");
    }
    if (!rpcUrl) {
        throw new Error("❌ STARKNET_SEPOLIA_RPC_URL not found in .env file");
    }
    if (!ownerAddress) {
        throw new Error("❌ OWNER_ADDRESS not found in .env file");
    }

    console.log("📋 Deployment Configuration:");
    console.log(`   Owner Address: ${ownerAddress}`);
    console.log(`   STRK Token: ${strkToken}`);
    console.log(`   DAO Fee: ${daoFeeBps} bps (${daoFeeBps / 100}%)`);
    console.log(`   Dev Fee: ${devFeeBps} bps (${devFeeBps / 100}%)`);
    console.log(`   Min Stake: ${minStakeAmount} (${minStakeAmount / 1e18} STRK)`);
    console.log(`   Unlock Period: ${unlockPeriod} seconds (${unlockPeriod / 86400} days)`);
    console.log(`   Claim Window: ${claimWindow} seconds (${claimWindow / 86400} days)\n`);

    // Initialize provider
    console.log("🔗 Connecting to Starknet Sepolia...");
    const provider = new RpcProvider({ 
        nodeUrl: rpcUrl,
        chainId: constants.StarknetChainId.SN_SEPOLIA
    });

    // Initialize account
    const account = new Account(provider, ownerAddress, privateKey, "1");
    console.log("✅ Account connected\n");

    // Load compiled contract
    console.log("📦 Loading compiled contract...");
    const sierraPath = path.join(__dirname, "../target/dev/sp_strk_spSTRK.contract_class.json");
    const casmPath = path.join(__dirname, "../target/dev/sp_strk_spSTRK.compiled_contract_class.json");
    
    if (!fs.existsSync(sierraPath)) {
        throw new Error(`❌ Sierra file not found at: ${sierraPath}\n   Run 'scarb build' first!`);
    }
    if (!fs.existsSync(casmPath)) {
        throw new Error(`❌ CASM file not found at: ${casmPath}\n   Run 'scarb build' first!`);
    }

    const sierraContract = json.parse(fs.readFileSync(sierraPath).toString("ascii"));
    const casmContract = json.parse(fs.readFileSync(casmPath).toString("ascii"));
    console.log("✅ Contract files loaded\n");

    // Declare contract
    console.log("📝 Declaring contract class...");
    const declareResponse = await account.declare({
        contract: sierraContract,
        casm: casmContract,
    });

    console.log(`   Transaction Hash: ${declareResponse.transaction_hash}`);
    console.log("   Waiting for transaction confirmation...");
    
    await provider.waitForTransaction(declareResponse.transaction_hash);
    const classHash = declareResponse.class_hash;
    console.log(`✅ Contract declared! Class Hash: ${classHash}\n`);

    // Prepare constructor calldata
    console.log("🔧 Preparing constructor calldata...");
    const constructorCalldata = CallData.compile({
        owner: ownerAddress,
        strk_token: strkToken,
        dao_fee_basis_points: daoFeeBps,
        dev_fee_basis_points: devFeeBps,
        min_stake_amount: uint256.bnToUint256(minStakeAmount),
        unlock_period: unlockPeriod,
        claim_window: claimWindow,
    });
    console.log("✅ Calldata prepared\n");

    // Deploy contract
    console.log("🚀 Deploying contract...");
    const deployResponse = await account.deployContract({
        classHash: classHash,
        constructorCalldata: constructorCalldata,
    });

    console.log(`   Transaction Hash: ${deployResponse.transaction_hash}`);
    console.log("   Waiting for deployment confirmation...");
    
    await provider.waitForTransaction(deployResponse.transaction_hash);
    const contractAddress = deployResponse.contract_address;
    console.log(`✅ Contract deployed!\n`);

    // Summary
    console.log("═══════════════════════════════════════════════════════════");
    console.log("🎉 DEPLOYMENT SUCCESSFUL!");
    console.log("═══════════════════════════════════════════════════════════");
    console.log(`📍 Contract Address: ${contractAddress}`);
    console.log(`🔍 Explorer: https://sepolia.voyager.online/contract/${contractAddress}`);
    console.log(`📦 Class Hash: ${classHash}`);
    console.log(`🔗 Network: Starknet Sepolia Testnet`);
    console.log("═══════════════════════════════════════════════════════════\n");

    // Save deployment info
    const deploymentInfo = {
        network: "sepolia",
        contractAddress: contractAddress,
        classHash: classHash,
        owner: ownerAddress,
        strkToken: strkToken,
        daoFeeBps: daoFeeBps,
        devFeeBps: devFeeBps,
        minStakeAmount: minStakeAmount,
        unlockPeriod: unlockPeriod,
        claimWindow: claimWindow,
        deployedAt: new Date().toISOString(),
        transactionHash: deployResponse.transaction_hash,
    };

    const deploymentPath = path.join(__dirname, "../deployments/sepolia-latest.json");
    fs.mkdirSync(path.dirname(deploymentPath), { recursive: true });
    fs.writeFileSync(deploymentPath, JSON.stringify(deploymentInfo, null, 2));
    console.log(`💾 Deployment info saved to: ${deploymentPath}\n`);

    console.log("✅ All done! Your spSTRK contract is live on Sepolia! 🎉");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("\n❌ Deployment failed:");
        console.error(error);
        process.exit(1);
    });
