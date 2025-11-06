const { Account, RpcProvider, Contract, json, stark, uint256, CallData, constants } = require("starknet");
const fs = require("fs");
const path = require("path");
require("dotenv").config();

async function main() {
    console.log("🔄 Starting spSTRK Contract Upgrade...\n");

    // Load environment variables
    const privateKey = process.env.PRIVATE_KEY;
    const rpcUrl = process.env.STARKNET_SEPOLIA_RPC_URL;
    const ownerAddress = process.env.OWNER_ADDRESS;
    const contractAddress = process.env.spSTRK_SEPOLIA;

    if (!privateKey || !rpcUrl || !ownerAddress || !contractAddress) {
        throw new Error("❌ Missing environment variables");
    }

    console.log("📋 Upgrade Configuration:");
    console.log(`   Contract Address: ${contractAddress}`);
    console.log(`   Owner Address: ${ownerAddress}\n`);

    // Initialize provider and account
    console.log("🔗 Connecting to Starknet Sepolia...");
    const provider = new RpcProvider({ 
        nodeUrl: rpcUrl,
        chainId: constants.StarknetChainId.SN_SEPOLIA
    });
    const account = new Account(provider, ownerAddress, privateKey, "1");
    console.log("✅ Account connected\n");

    // Load compiled contract
    console.log("📦 Loading new contract version...");
    const sierraPath = path.join(__dirname, "../target/dev/sp_strk_spSTRK.contract_class.json");
    const casmPath = path.join(__dirname, "../target/dev/sp_strk_spSTRK.compiled_contract_class.json");
    
    if (!fs.existsSync(sierraPath) || !fs.existsSync(casmPath)) {
        throw new Error(`❌ Compiled contract not found. Run 'scarb build' first!`);
    }

    const sierraContract = json.parse(fs.readFileSync(sierraPath).toString("ascii"));
    const casmContract = json.parse(fs.readFileSync(casmPath).toString("ascii"));
    console.log("✅ New contract version loaded\n");

    // Declare new contract class (skip if already declared)
    console.log("📝 Declaring new contract class...");
    let newClassHash;
    
    try {
        const declareResponse = await account.declare({
            contract: sierraContract,
            casm: casmContract,
        });

        console.log(`   Transaction Hash: ${declareResponse.transaction_hash}`);
        console.log("   Waiting for declaration confirmation...");
        
        await provider.waitForTransaction(declareResponse.transaction_hash);
        newClassHash = declareResponse.class_hash;
        console.log(`✅ New class declared! Class Hash: ${newClassHash}\n`);
    } catch (error) {
        if (error.message.includes('already declared')) {
            // Class already declared, use the existing class hash
            newClassHash = '0x3918e55999c979fdd711bf4cc6c754d708b6f83109b0eef2a45a94282f3b44b';
            console.log(`ℹ️  Class already declared, using existing class hash: ${newClassHash}\n`);
        } else {
            throw error;
        }
    }

    // Upgrade contract
    console.log("🚀 Upgrading contract...");
    
    // Call upgrade function on the contract
    const upgradeCall = {
        contractAddress: contractAddress,
        entrypoint: "upgrade",
        calldata: CallData.compile({
            new_class_hash: newClassHash
        })
    };

    const upgradeResponse = await account.execute(upgradeCall);
    console.log(`   Transaction Hash: ${upgradeResponse.transaction_hash}`);
    console.log("   Waiting for upgrade confirmation...");
    
    await provider.waitForTransaction(upgradeResponse.transaction_hash);
    console.log("✅ Contract upgraded!\n");

    // Summary
    console.log("═══════════════════════════════════════════════════════════");
    console.log("🎉 UPGRADE SUCCESSFUL!");
    console.log("═══════════════════════════════════════════════════════════");
    console.log(`📍 Contract Address: ${contractAddress} (unchanged)`);
    console.log(`🔍 Explorer: https://sepolia.voyager.online/contract/${contractAddress}`);
    console.log(`📦 New Class Hash: ${newClassHash}`);
    console.log(`🔄 Upgrade TX: https://sepolia.voyager.online/tx/${upgradeResponse.transaction_hash}`);
    console.log("═══════════════════════════════════════════════════════════\n");

    // Save upgrade info
    const upgradeInfo = {
        network: "sepolia",
        contractAddress: contractAddress,
        oldClassHash: "0x7f27b5793f256787928ecb5d1e2b3e1f3578605e35add20f432f703b049df74",
        newClassHash: newClassHash,
        upgradedAt: new Date().toISOString(),
        upgradeTransactionHash: upgradeResponse.transaction_hash,
    };

    const upgradePath = path.join(__dirname, "../deployments/sepolia-upgrade-latest.json");
    fs.writeFileSync(upgradePath, JSON.stringify(upgradeInfo, null, 2));
    console.log(`💾 Upgrade info saved to: ${upgradePath}\n`);

    console.log("✅ Contract upgraded successfully! 🎉");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("\n❌ Upgrade failed:");
        console.error(error);
        process.exit(1);
    });
