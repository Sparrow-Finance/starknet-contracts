#[starknet::contract]
pub mod spSTRK {
    use core::num::traits::Zero;
    use openzeppelin_access::ownable::OwnableComponent;
    use openzeppelin_interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin_interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
    use openzeppelin_interfaces::upgrades::IUpgradeable;
    use openzeppelin_security::pausable::PausableComponent;
    use openzeppelin_security::reentrancyguard::ReentrancyGuardComponent;
    use openzeppelin_token::erc20::extensions::erc4626::{
        DefaultConfig, ERC4626Component, ERC4626DefaultNoFees, ERC4626DefaultNoLimits,
        ERC4626EmptyHooks, ERC4626SelfAssetsManagement,
    };
    use openzeppelin_token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use openzeppelin_upgrades::UpgradeableComponent;
    use sp_strk::components::constants::Constants;
    use sp_strk::interfaces::sp_strk::{Errors, IspSTRK, UnlockRequest};
    use sp_strk::interfaces::validator_pool::{
        IValidatorPoolDispatcher, IValidatorPoolDispatcherTrait,
    };
    use sp_strk::interfaces::withdrawal_queue::{
        IWithdrawalQueueNFTDispatcher, IWithdrawalQueueNFTDispatcherTrait,
    };
    use sp_strk::types::init::InitParams;
    use starknet::event::EventEmitter;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{
        ClassHash, ContractAddress, get_block_timestamp, get_caller_address, get_contract_address,
    };

    // ====================================
    // OpenZeppelin components and their implementations
    // ====================================
    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: ERC4626Component, storage: erc4626, event: ERC4626Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(
        path: ReentrancyGuardComponent, storage: reentrancy_guard, event: ReentrancyGuardEvent,
    );

    // ====================================
    // ERC20 Configuration - REQUIRED
    // ====================================
    impl ERC20ImmutableConfigImpl of ERC20Component::ImmutableConfig {
        const DECIMALS: u8 = 18;
    }
    impl ERC20HooksImpl = ERC20HooksEmptyImpl<ContractState>; // <-- FIX THIS LINE

    // ====================================
    // Component Implementations
    // ====================================

    // ERC20 Mixin
    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    // ERC4626
    // ERC4626 - EXPOSED
    // ERC4626
    impl ERC4626Impl = ERC4626Component::ERC4626Impl<ContractState>;
    impl ERC4626InternalImpl = ERC4626Component::InternalImpl<ContractState>;

    // ERC4626 Config
    impl ERC4626ImmutableConfig = openzeppelin_token::erc20::extensions::erc4626::DefaultConfig;
    impl ERC4626HooksImpl =
        openzeppelin_token::erc20::extensions::erc4626::ERC4626EmptyHooks<ContractState>;
    impl ERC4626FeeConfigImpl =
        openzeppelin_token::erc20::extensions::erc4626::ERC4626DefaultNoFees<ContractState>;
    impl ERC4626LimitConfigImpl =
        openzeppelin_token::erc20::extensions::erc4626::ERC4626DefaultNoLimits<ContractState>;
    impl ERC4626AssetsManagementImpl =
        openzeppelin_token::erc20::extensions::erc4626::ERC4626SelfAssetsManagement<ContractState>;

    // Ownable Mixin
    #[abi(embed_v0)]
    impl OwnableTwoStepMixinImpl =
        OwnableComponent::OwnableTwoStepMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    // Upgradeable
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    // Pausable Mixin
    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;
    impl PausableInternalImpl = PausableComponent::InternalImpl<ContractState>;

    // ReentrancyGuard
    impl ReentrancyGuardInternalImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;

    // ====================================
    // Storage
    // ====================================
    #[storage]
    struct Storage {
        // address of the STRK token contract
        strk_token: ContractAddress,
        // mapping of user address to their unlock request
        unlock_requests: Map<(ContractAddress, u256), UnlockRequest>,
        unlock_request_count: Map<ContractAddress, u256>,
        // total accumulated DAO fees
        accumulated_dao_fees: u256,
        // total accumulated developer fees
        accumulated_dev_fees: u256,
        // minimum STRK amount allowable to stake
        min_stake_amount: u256,
        // total STRK pooled in the contract
        total_pooled_STRK: u256,
        // time period for claimable unlocks
        claim_window: u64,
        // time period required for unlocks
        unlock_period: u64,
        // DAO fee in basis points
        dao_fee_basis_points: u16,
        // Developer fee in basis points
        dev_fee_basis_points: u16,
        total_locked_in_unlocks: u256,
        // Validator pool contract address
        validator_pool: ContractAddress,
        // Total STRK delegated to validator
        total_delegated_to_validator: u256,
        // Track pending unbonding from validator
        pending_validator_unbonding: u256,
        // Timestamp when unbonding completes
        validator_unbond_time: u64,
        withdrawal_queue_nft: ContractAddress,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        reentrancy_guard: ReentrancyGuardComponent::Storage,
        #[substorage(v0)]
        erc4626: ERC4626Component::Storage,
    }

    // ====================================
    // Events
    // ====================================
    #[derive(Drop, starknet::Event)]
    struct Staked {
        #[key]
        user: ContractAddress,
        strk_amount: u256,
        sp_strk_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct UnlockRequested {
        #[key]
        user: ContractAddress,
        strk_amount: u256,
        sp_strk_amount: u256,
        unlock_time: u64,
        expiry_time: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct Unstaked {
        #[key]
        user: ContractAddress,
        strk_amount: u256,
        sp_strk_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct UnlockCancelled {
        #[key]
        user: ContractAddress,
        #[flat]
        request: UnlockRequest,
    }

    #[derive(Drop, starknet::Event)]
    struct UnlockExpired {
        #[key]
        user: ContractAddress,
        index: u256,
        sp_strk_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Deposited {
        #[key]
        from: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Withdrawn {
        #[key]
        to: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct RewardsAdded {
        total_rewards: u256,
        user_rewards: u256,
        dao_fees: u256,
        dev_fees: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct AllFeesCollected {
        #[key]
        to: ContractAddress,
        dao_amount: u256,
        dev_amount: u256,
        total_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct DaoFeesCollected {
        #[key]
        to: ContractAddress,
        fees: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct DevFeesCollected {
        #[key]
        to: ContractAddress,
        fees: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct FeesUpdated {
        dao_fee_bps: u16,
        dev_fee_bps: u16,
    }

    #[derive(Drop, starknet::Event)]
    struct MinStakeAmountUpdated {
        old_amount: u256,
        new_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct UnlockPeriodUpdated {
        old_period: u64,
        new_period: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct ClaimWindowUpdated {
        old_window: u64,
        new_window: u64,
    }

    //validator
    #[derive(Drop, starknet::Event)]
    struct ValidatorRewardsClaimed {
        rewards: u256,
        dao_fees: u256,
        dev_fees: u256,
        user_rewards: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct ValidatorUnbondingStarted {
        amount: u256,
        unbond_time: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct ValidatorUnbondingCompleted {
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct DelegatedToValidator {
        amount: u256,
        total_delegated: u256,
    }


    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Staked: Staked,
        UnlockRequested: UnlockRequested,
        Unstaked: Unstaked,
        UnlockCancelled: UnlockCancelled,
        UnlockExpired: UnlockExpired,
        Deposited: Deposited,
        Withdrawn: Withdrawn,
        RewardsAdded: RewardsAdded,
        AllFeesCollected: AllFeesCollected,
        DaoFeesCollected: DaoFeesCollected,
        DevFeesCollected: DevFeesCollected,
        FeesUpdated: FeesUpdated,
        MinStakeAmountUpdated: MinStakeAmountUpdated,
        UnlockPeriodUpdated: UnlockPeriodUpdated,
        ClaimWindowUpdated: ClaimWindowUpdated,
        //validator
        ValidatorRewardsClaimed: ValidatorRewardsClaimed,
        ValidatorUnbondingStarted: ValidatorUnbondingStarted,
        ValidatorUnbondingCompleted: ValidatorUnbondingCompleted,
        DelegatedToValidator: DelegatedToValidator,
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        ReentrancyGuardEvent: ReentrancyGuardComponent::Event,
        ERC4626Event: ERC4626Component::Event,
    }

    // ====================================
    // Constructor
    // ====================================
    #[constructor]
    fn constructor(ref self: ContractState, params: InitParams) {
        // Initialize Ownable
        self.ownable.initializer(params.owner);

        // Initialize ERC20
        self.erc20.initializer("Sparrow Staked STRK", "spSTRK");
        self.erc4626.initializer(params.strk_token);

        // Initialize Config params
        self.strk_token.write(params.strk_token);
        //validaot pool initialization
        self.validator_pool.write(params.validator_pool);

        self.withdrawal_queue_nft.write(params.withdrawal_queue_nft);

        self._set_fees(params.dao_fee_basis_points, params.dev_fee_basis_points);
        self._set_min_stake_amount(params.min_stake_amount);
        self._set_unlock_period(params.unlock_period);
        self._set_claim_window(params.claim_window);
    }

    // ====================================
    // Upgradeable Implementation
    // ====================================
    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        /// Upgrade the contract to a new class hash
        /// # Arguments
        /// * `new_class_hash` - The class hash of the new implementation contract
        /// # Access Control
        /// Only the contract owner can call this function
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable.upgrade(new_class_hash);
        }
    }

    // ====================================
    // spSTRK Implementation
    // ====================================
    #[abi(embed_v0)]
    impl spSTRKImpl of IspSTRK<ContractState> {
        // ========== ERC4626 Standard Functions ==========

        // Metadata
        fn asset(self: @ContractState) -> ContractAddress {
            self.erc4626.asset()
        }

        fn total_assets(self: @ContractState) -> u256 {
            self.erc4626.total_assets()
        }

        // Conversions
        fn convert_to_shares(self: @ContractState, assets: u256) -> u256 {
            self.erc4626.convert_to_shares(assets)
        }

        fn convert_to_assets(self: @ContractState, shares: u256) -> u256 {
            self.erc4626.convert_to_assets(shares)
        }

        // Deposit functions - use standard implementation
        fn max_deposit(self: @ContractState, receiver: ContractAddress) -> u256 {
            self.erc4626.max_deposit(receiver)
        }

        fn preview_deposit(self: @ContractState, assets: u256) -> u256 {
            self.erc4626.preview_deposit(assets)
        }

        fn deposit(ref self: ContractState, assets: u256, receiver: ContractAddress) -> u256 {
            self.pausable.assert_not_paused();
            self.erc4626.deposit(assets, receiver)
        }

        fn max_mint(self: @ContractState, receiver: ContractAddress) -> u256 {
            self.erc4626.max_mint(receiver)
        }

        fn preview_mint(self: @ContractState, shares: u256) -> u256 {
            self.erc4626.preview_mint(shares)
        }

        fn mint(ref self: ContractState, shares: u256, receiver: ContractAddress) -> u256 {
            self.pausable.assert_not_paused();
            self.erc4626.mint(shares, receiver)
        }

        // Withdraw functions - REDIRECT to NFT system
        fn max_withdraw(self: @ContractState, owner: ContractAddress) -> u256 {
            // Return owner's balance converted to assets
            let shares = self.erc20.balance_of(owner);
            self.erc4626.convert_to_assets(shares)
        }

        fn preview_withdraw(self: @ContractState, assets: u256) -> u256 {
            self.erc4626.preview_withdraw(assets)
        }

        fn withdraw(
            ref self: ContractState,
            assets: u256,
            receiver: ContractAddress,
            owner: ContractAddress,
        ) -> u256 {
            self.pausable.assert_not_paused();

            // Convert assets to shares
            let shares = self.erc4626.convert_to_shares(assets);

            // Redirect to NFT-based unlock system
            // User must be the owner or have approval
            let caller = get_caller_address();
            assert(caller == owner, 'Not owner');

            // Request unlock returns NFT token_id
            let _token_id = self.request_unlock(shares, assets);

            // Return shares as per ERC4626 spec
            shares
        }

        fn max_redeem(self: @ContractState, owner: ContractAddress) -> u256 {
            self.erc4626.max_redeem(owner)
        }

        fn preview_redeem(self: @ContractState, shares: u256) -> u256 {
            self.erc4626.preview_redeem(shares)
        }

        fn redeem(
            ref self: ContractState,
            shares: u256,
            receiver: ContractAddress,
            owner: ContractAddress,
        ) -> u256 {
            self.pausable.assert_not_paused();

            // Convert shares to assets
            let assets = self.erc4626.convert_to_assets(shares);

            // Redirect to NFT-based unlock system
            let caller = get_caller_address();
            assert(caller == owner, 'Not owner');

            // Request unlock returns NFT token_id
            let _token_id = self.request_unlock(shares, assets);

            // Return assets as per ERC4626 spec
            assets
        }

        /// Stake STRK tokens and receive spSTRK tokens
        /// # Arguments
        /// * `strk_amount` - The amount of STRK tokens to stake
        /// * `min_sp_strk_out` - The minimum amount of spSTRK tokens to receive
        /// # Returns
        /// The amount of spSTRK tokens minted
        fn stake(ref self: ContractState, strk_amount: u256, min_sp_strk_out: u256) -> u256 {
            // Ensure contract is not paused and prevent reentrancy
            self.pausable.assert_not_paused();
            // Start reentrancy guard
            self.reentrancy_guard.start();

            // Validate stake amount
            assert(strk_amount >= self.min_stake_amount.read(), Errors::BELOW_MINIMUM_STAKE);

            // Calculate spSTRK amount to mint
            let sp_strk_amount = self._strk_to_sp_strk(strk_amount);

            // Ensure non-zero shares are minted
            assert(sp_strk_amount > 0, Errors::INSUFFICIENT_SHARES);

            // Enforce slippage protection
            assert(sp_strk_amount >= min_sp_strk_out, Errors::SLIPPAGE_EXCEEDED);

            // Get caller address
            let user = get_caller_address();

            // Transfer STRK tokens from user to contract
            self._strk_transfer(user, get_contract_address(), strk_amount);
            // Mint spSTRK tokens to user
            self.erc20.mint(user, sp_strk_amount);

            // Update total pooled STRK
            self.total_pooled_STRK.write(self.total_pooled_STRK.read() + strk_amount);

            // Emit Staked event
            self.emit(Staked { user, strk_amount, sp_strk_amount });

            // Auto-delegate excess to validator (only on user stake)
            self._auto_delegate_to_validator();

            // End reentrancy guard
            self.reentrancy_guard.end();

            // Return minted spSTRK amount
            sp_strk_amount
        }

        /// Request to unlock staked spSTRK tokens
        /// # Arguments
        /// * `sp_strk_amount` - The amount of spSTRK tokens to unlock
        /// * `min_strk_out` - The minimum amount of STRK tokens to receive
        /// # Returns
        /// The amount of STRK tokens that will be received upon claiming
        fn request_unlock(
            ref self: ContractState, sp_strk_amount: u256, min_strk_out: u256,
        ) -> u256 {
            // Ensure contract is not paused and prevent reentrancy
            self.pausable.assert_not_paused();
            // Start reentrancy guard
            self.reentrancy_guard.start();

            // Get caller address
            let user = get_caller_address();

            // Validate unlock request
            assert(sp_strk_amount > 0, Errors::INVALID_AMOUNT);
            // The total spSTRK supply must be greater than zero
            assert(self.erc20.total_supply() > 0, Errors::NO_SHARES_EXIST);
            // User must have enough spSTRK balance
            assert(self.erc20.balance_of(user) >= sp_strk_amount, Errors::INSUFFICIENT_BALANCE);

            // Ensure no pending unlock request exists
            let request_count = self.unlock_request_count.entry(user).read();
            assert(request_count < Constants::MAX_UNLOCK_REQUESTS, Errors::TOO_MANY_REQUESTS);

            // Calculate STRK amount to be received
            let strk_amount = self._sp_strk_to_strk(sp_strk_amount);
            // Validate calculated STRK amount
            assert(strk_amount > 0, Errors::INSUFFICIENT_SHARES);
            // Enforce slippage protection
            assert(strk_amount >= min_strk_out, Errors::SLIPPAGE_EXCEEDED);

            // Transfer spSTRK tokens from user to contract
            self.erc20._transfer(user, get_contract_address(), sp_strk_amount);

            // Calculate unlock time
            let unlock_time = get_block_timestamp() + self.unlock_period.read();
            // Calculate expiry time
            let expiry_time = unlock_time + self.claim_window.read();
            // Store unlock request
            self
                .unlock_requests
                .entry((user, request_count))
                .write(UnlockRequest { sp_strk_amount, strk_amount, unlock_time, expiry_time });

            self.unlock_request_count.entry(user).write(request_count + 1);

            // ALSO mint NFT
            let nft = IWithdrawalQueueNFTDispatcher {
                contract_address: self.withdrawal_queue_nft.read(),
            };
            let _nft_token_id = nft
                .mint_request(
                    user, UnlockRequest { sp_strk_amount, strk_amount, unlock_time, expiry_time },
                );

            self.total_locked_in_unlocks.write(self.total_locked_in_unlocks.read() + strk_amount);

            // Emit UnlockRequested event
            self
                .emit(
                    UnlockRequested { user, strk_amount, sp_strk_amount, unlock_time, expiry_time },
                );

            // End reentrancy guard
            self.reentrancy_guard.end();

            // Return the STRK amount that will be received
            strk_amount
        }

        /// Claim unlocked STRK tokens after the unlock period
        /// # Access Control
        /// The caller must have a valid unlock request that is ready to be claimed
        fn claim_unlock(ref self: ContractState, request_index: u256) {
            // Ensure contract is not paused and prevent reentrancy
            self.pausable.assert_not_paused();
            // Start reentrancy guard
            self.reentrancy_guard.start();

            // Get caller address and their unlock request
            let user = get_caller_address();
            let request_count = self.unlock_request_count.entry(user).read();
            assert(request_index < request_count, Errors::INVALID_REQUEST_INDEX);

            let request = self.unlock_requests.entry((user, request_index)).read();
            assert(request.expiry_time != 0, Errors::REQUEST_NOT_EXIST);

            // Validate unlock request
            assert(request.expiry_time != 0, Errors::REQUEST_NOT_EXIST);
            // Ensure request has not expired
            assert(request.expiry_time >= get_block_timestamp(), Errors::REQUEST_EXPIRED);
            // Ensure unlock time has passed
            assert(request.unlock_time <= get_block_timestamp(), Errors::REQUEST_NOT_READY);

            // Calculate STRK amount to be received
            let strk_amount = request.strk_amount;

            // Validate calculated STRK amount
            assert(strk_amount > 0, Errors::INVALID_STRK_AMOUNT);
            // Ensure contract has enough STRK balance
            assert(
                self._strk_balance_of(get_contract_address()) >= strk_amount,
                Errors::INSUFFICIENT_STARK,
            );
            // Enforce slippage protection
            // assert(strk_amount >= request.min_strk_out, Errors::SLIPPAGE_EXCEEDED);

            // Clear the unlock request
            let last_index = request_count - 1;
            if request_index != last_index {
                let last_request = self.unlock_requests.entry((user, last_index)).read();
                self.unlock_requests.entry((user, request_index)).write(last_request);
            }

            self
                .unlock_requests
                .entry((user, last_index))
                .write(
                    UnlockRequest {
                        sp_strk_amount: 0_u256,
                        strk_amount: 0_u256,
                        unlock_time: 0_u64,
                        expiry_time: 0_u64,
                    },
                );

            self.unlock_request_count.entry(user).write(last_index);

            // Update total pooled STRK
            self.total_pooled_STRK.write(self.total_pooled_STRK.read() - strk_amount);

            self.total_locked_in_unlocks.write(self.total_locked_in_unlocks.read() - strk_amount);

            // Burn spSTRK tokens and transfer STRK tokens to user
            self.erc20.burn(get_contract_address(), request.sp_strk_amount);
            self._strk_transfer(get_contract_address(), user, strk_amount);

            // Emit Unstaked event
            self.emit(Unstaked { user, strk_amount, sp_strk_amount: request.sp_strk_amount });

            // End reentrancy guard
            self.reentrancy_guard.end();
        }

        fn claim_unlock_with_nft(ref self: ContractState, token_id: u256) {
            self.pausable.assert_not_paused();
            self.reentrancy_guard.start();

            let caller = get_caller_address();
            let nft_address = self.withdrawal_queue_nft.read();

            // Use custom interface for withdrawal-specific functions
            let nft = IWithdrawalQueueNFTDispatcher { contract_address: nft_address };

            // Use ERC721 interface for standard NFT functions
            let erc721 = IERC721Dispatcher { contract_address: nft_address };

            // Verify NFT is claimable
            assert(nft.is_claimable(token_id), 'Not claimable');

            // Verify caller owns the NFT
            let nft_owner = erc721.owner_of(token_id);
            assert(caller == nft_owner, 'Not NFT owner');

            // Get request data from NFT
            let request = nft.get_request(token_id);

            let strk_amount = request.strk_amount;
            let sp_strk_amount = request.sp_strk_amount;

            // Validate
            assert(strk_amount > 0, Errors::INVALID_STRK_AMOUNT);
            assert(
                self._strk_balance_of(get_contract_address()) >= strk_amount,
                Errors::INSUFFICIENT_STARK,
            );

            // Update state
            self.total_pooled_STRK.write(self.total_pooled_STRK.read() - strk_amount);
            self.total_locked_in_unlocks.write(self.total_locked_in_unlocks.read() - strk_amount);

            // Burn spSTRK and transfer STRK
            self.erc20.burn(get_contract_address(), sp_strk_amount);
            self._strk_transfer(get_contract_address(), caller, strk_amount);

            // Burn NFT
            nft.burn_request(token_id);

            self.emit(Unstaked { user: caller, strk_amount, sp_strk_amount });

            self.reentrancy_guard.end();
        }

        /// Cancel a pending unlock request and return spSTRK tokens to the user
        /// # Access Control
        /// The caller must have a valid unlock request
        fn cancel_unlock(ref self: ContractState, request_index: u256) {
            // Ensure contract is not paused and prevent reentrancy
            self.pausable.assert_not_paused();
            // Start reentrancy guard
            self.reentrancy_guard.start();

            // Get caller address and their unlock request
            let user = get_caller_address();
            let request_count = self.unlock_request_count.entry(user).read();
            assert(request_index < request_count, 'Invalid request index');

            let request = self.unlock_requests.entry((user, request_index)).read();

            // Ensure a valid unlock request exists
            assert(request.expiry_time != 0, Errors::REQUEST_NOT_EXIST);

            let strk_amount = request.strk_amount;

            // Ensure a valid unlock request exists
            assert(request.expiry_time != 0, Errors::REQUEST_NOT_EXIST);

            self.total_locked_in_unlocks.write(self.total_locked_in_unlocks.read() - strk_amount);

            // Remove request by swapping with last element
            let last_index = request_count - 1;
            if request_index != last_index {
                let last_request = self.unlock_requests.entry((user, last_index)).read();
                self.unlock_requests.entry((user, request_index)).write(last_request);
            }

            // Clear the last request slot
            self
                .unlock_requests
                .entry((user, last_index))
                .write(
                    UnlockRequest {
                        sp_strk_amount: 0_u256,
                        strk_amount: 0_u256,
                        unlock_time: 0_u64,
                        expiry_time: 0_u64,
                    },
                );

            // Decrement count
            self.unlock_request_count.entry(user).write(last_index);

            // Return spSTRK tokens to the user
            self.erc20._transfer(get_contract_address(), user, request.sp_strk_amount);

            // Emit UnlockCancelled event
            self.emit(UnlockCancelled { user, request });

            // End reentrancy guard
            self.reentrancy_guard.end();
        }

        /// Claim expired unlock request (returns spSTRK after claim window expires)
        /// # Arguments
        /// * `request_index` - Index of the expired unlock request
        fn claim_expired(ref self: ContractState, request_index: u256) {
            self.pausable.assert_not_paused();
            self.reentrancy_guard.start();

            // Get caller address and validate index
            let user = get_caller_address();
            let request_count = self.unlock_request_count.entry(user).read();
            assert(request_index < request_count, 'Invalid request index');

            // Get the unlock request
            let request = self.unlock_requests.entry((user, request_index)).read();

            // Validate it's expired
            assert(request.expiry_time != 0, Errors::REQUEST_NOT_EXIST);
            assert(get_block_timestamp() > request.expiry_time, 'Request not expired');

            // Remove request by swapping with last element
            let last_index = request_count - 1;
            if request_index != last_index {
                let last_request = self.unlock_requests.entry((user, last_index)).read();
                self.unlock_requests.entry((user, request_index)).write(last_request);
            }

            // Clear the last request slot
            self
                .unlock_requests
                .entry((user, last_index))
                .write(
                    UnlockRequest {
                        sp_strk_amount: 0_u256,
                        strk_amount: 0_u256,
                        unlock_time: 0_u64,
                        expiry_time: 0_u64,
                    },
                );

            // Decrement count
            self.unlock_request_count.entry(user).write(last_index);

            // Reduce locked amount
            self
                .total_locked_in_unlocks
                .write(self.total_locked_in_unlocks.read() - request.strk_amount);

            // Return spSTRK to user
            self.erc20._transfer(get_contract_address(), user, request.sp_strk_amount);

            self
                .emit(
                    UnlockExpired {
                        user, index: request_index, sp_strk_amount: request.sp_strk_amount,
                    },
                );

            self.reentrancy_guard.end();
        }

        /// Get number of pending unlock requests for a user
        /// # Arguments
        /// * `user` - User address
        /// # Returns
        /// Number of pending requests
        fn get_unlock_request_count(self: @ContractState, user: ContractAddress) -> u256 {
            self.unlock_request_count.entry(user).read()
        }

        /// Get the unlock request details for a user
        /// # Arguments
        /// * `user` - The address of the user
        /// # Returns
        /// A tuple containing the UnlockRequest, the STRK amount, a boolean indicating if it's
        /// ready to claim, and a boolean indicating if it has expired
        fn get_unlock_request(
            self: @ContractState, user: ContractAddress, request_index: u256,
        ) -> (UnlockRequest, u256, bool, bool) {
            // Validate index
            let request_count = self.unlock_request_count.entry(user).read();
            assert(request_index < request_count, 'Invalid request index');

            // Retrieve the unlock request
            let request = self.unlock_requests.entry((user, request_index)).read();

            // Calculate STRK amount to be received
            let strk_amount = request.strk_amount;
            // Determine if the request is ready to claim or has expired
            let is_ready = get_block_timestamp() >= request.unlock_time;
            // Ensure the request has not been claimed
            let is_expired = get_block_timestamp() >= request.expiry_time;

            // Return the unlock request details
            (request, strk_amount, is_ready, is_expired)
        }

        /// Get the current exchange rate between STRK and spSTRK
        /// # Returns
        /// The exchange rate as a u256 value
        fn get_exchange_rate(self: @ContractState) -> u256 {
            // If no spSTRK supply or pooled STRK, return initial rate of 1:1
            if self.erc20.total_supply() == 0 || self.total_pooled_STRK.read() == 0 {
                1_000_000_000_000_000_000_u256
            } else {
                // Calculate exchange rate scaled by 1e18 for precision
                (self.total_pooled_STRK.read() * 1_000_000_000_000_000_000_u256)
                    / self.erc20.total_supply()
            }
        }

        /// Preview the amount of spSTRK tokens received for staking a given amount of STRK
        /// # Arguments
        /// * `strk_amount` - The amount of STRK tokens to stake
        /// # Returns
        /// The amount of spSTRK tokens that will be received
        fn preview_stake(self: @ContractState, strk_amount: u256) -> u256 {
            self._strk_to_sp_strk(strk_amount)
        }

        /// Preview the amount of STRK tokens received for unlocking a given amount of spSTRK
        /// # Arguments
        /// * `sp_strk_amount` - The amount of spSTRK tokens to unlock
        /// # Returns
        /// The amount of STRK tokens that will be received
        fn preview_unlock(self: @ContractState, sp_strk_amount: u256) -> u256 {
            self._sp_strk_to_strk(sp_strk_amount)
        }

        /// Get various statistics about the contract
        /// # Returns
        /// A tuple containing total pooled STRK, total spSTRK supply, exchange rate,
        /// contract STRK balance, accumulated DAO fees, accumulated developer fees,
        /// DAO fee basis points, and developer fee basis points
        fn get_stats(self: @ContractState) -> (u256, u256, u256, u256, u256, u256, u16, u16) {
            (
                self.total_pooled_STRK.read(),
                self.erc20.total_supply(),
                self.get_exchange_rate(),
                self._strk_balance_of(get_contract_address()),
                self.accumulated_dao_fees.read(),
                self.accumulated_dev_fees.read(),
                self.dao_fee_basis_points.read(),
                self.dev_fee_basis_points.read(),
            )
        }

        /// Get validator unbonding status
        /// # Returns
        /// (pending_amount, initiated_timestamp, estimated_completion_time, can_attempt_complete)
        fn get_validator_unbonding_status(self: @ContractState) -> (u256, u64, u64, bool) {
            let pending = self.pending_validator_unbonding.read();
            let initiated_time = self.validator_unbond_time.read();

            if pending == 0 {
                return (0, 0, 0, false);
            }

            // Estimate completion based on when it was initiated
            // For Sepolia: 5 minutes = 300 seconds
            // For Mainnet: 7 days = 604800 seconds
            // Using 300 for Sepolia testnet
            let estimated_completion = initiated_time + 300;

            // Can attempt if estimated time has passed
            // (actual validation happens in validator pool contract)
            let can_attempt = get_block_timestamp() >= estimated_completion;

            (pending, initiated_time, estimated_completion, can_attempt)
        }

        /// ====================================
        /// Admin Functions
        /// ====================================

        /// Deposit STRK tokens into the contract
        /// # Arguments
        /// * `strk_amount` - The amount of STRK tokens to deposit
        fn admin_deposit(ref self: ContractState, strk_amount: u256) {
            // Only owner can deposit
            self.ownable.assert_only_owner();

            assert(strk_amount > 0, Errors::INVALID_AMOUNT);

            // Transfer STRK tokens from owner to contract
            self._strk_transfer(get_caller_address(), get_contract_address(), strk_amount);
            self.emit(Deposited { from: get_caller_address(), amount: strk_amount });
        }

        /// Withdraw STRK tokens from the contract
        /// # Arguments
        /// * `strk_amount` - The amount of STRK tokens to withdraw
        fn admin_withdraw(ref self: ContractState, strk_amount: u256) {
            self.ownable.assert_only_owner();
            self.reentrancy_guard.start();

            // Validate withdraw amount
            assert(strk_amount > 0, Errors::INVALID_AMOUNT);

            // First check: Contract must have enough balance at all
            let contract_balance = self._strk_balance_of(get_contract_address());
            assert(contract_balance >= strk_amount, Errors::INSUFFICIENT_STARK);

            // Second check: Calculate minimum reserve (10% of total pooled)
            let min_reserve = (self.total_pooled_STRK.read() * 1000) / 10000;

            // Calculate committed STRK (fees + locked unlocks)
            let committed_strk = self.accumulated_dao_fees.read()
                + self.accumulated_dev_fees.read()
                + self.total_locked_in_unlocks.read();

            // Must keep the larger of min_reserve or committed_strk
            let must_keep = if committed_strk > min_reserve {
                committed_strk
            } else {
                min_reserve
            };

            // Third check: Ensure we don't withdraw into the reserve
            assert(contract_balance >= strk_amount + must_keep, 'Insufficient liquidity');

            // Transfer STRK tokens to owner
            self._strk_transfer(get_contract_address(), get_caller_address(), strk_amount);

            self.emit(Withdrawn { to: get_caller_address(), amount: strk_amount });

            self.reentrancy_guard.end();
        }

        /// Deposit STRK tokens into the contract as rewards
        /// # Arguments
        /// * `strk_amount` - The amount of STRK tokens to deposit
        fn add_rewards(ref self: ContractState, strk_amount: u256) {
            self.ownable.assert_only_owner();

            assert(strk_amount > 0, Errors::INVALID_AMOUNT);

            // Transfer STRK tokens from owner to contract
            self._strk_transfer(get_caller_address(), get_contract_address(), strk_amount);

            // Calculate fees and user rewards
            let dao_fees = (strk_amount * self.dao_fee_basis_points.read().into())
                / Constants::BASIS_POINTS;
            let dev_fees = (strk_amount * self.dev_fee_basis_points.read().into())
                / Constants::BASIS_POINTS;
            // Calculate total fees and user rewards
            let total_fees = dao_fees + dev_fees;
            let user_rewards = strk_amount - total_fees;

            // Update total pooled STRK and accumulated fees
            self.total_pooled_STRK.write(self.total_pooled_STRK.read() + user_rewards);
            self.accumulated_dao_fees.write(self.accumulated_dao_fees.read() + dao_fees);
            self.accumulated_dev_fees.write(self.accumulated_dev_fees.read() + dev_fees);

            self
                .emit(
                    RewardsAdded { total_rewards: strk_amount, user_rewards, dao_fees, dev_fees },
                );
        }

        fn collect_all_fees(ref self: ContractState) {
            self.ownable.assert_only_owner();
            self.reentrancy_guard.start();

            let total_fees = self.accumulated_dao_fees.read() + self.accumulated_dev_fees.read();
            assert(total_fees > 0, Errors::NO_FEES_TO_COLLECT);
            assert(
                self._strk_balance_of(get_contract_address()) >= total_fees,
                Errors::INSUFFICIENT_STARK,
            );

            let dao_fees = self.accumulated_dao_fees.read();
            let dev_fees = self.accumulated_dev_fees.read();

            self.accumulated_dao_fees.write(0_u256);
            self.accumulated_dev_fees.write(0_u256);

            self._strk_transfer(get_contract_address(), get_caller_address(), total_fees);

            self
                .emit(
                    AllFeesCollected {
                        to: get_caller_address(),
                        dao_amount: dao_fees,
                        dev_amount: dev_fees,
                        total_amount: total_fees,
                    },
                );

            self.reentrancy_guard.end();
        }

        /// Collect accumulated DAO fees
        fn collect_dao_fees(ref self: ContractState) {
            self.ownable.assert_only_owner();
            self.reentrancy_guard.start();

            let dao_fees = self.accumulated_dao_fees.read();
            // Ensure dao fees are available to collect
            assert(dao_fees > 0, Errors::NO_FEES_TO_COLLECT);
            assert(
                self._strk_balance_of(get_contract_address()) >= dao_fees,
                Errors::INSUFFICIENT_STARK,
            );

            // Reset accumulated DAO fees
            self.accumulated_dao_fees.write(0_u256);
            // Transfer DAO fees to owner
            self._strk_transfer(get_contract_address(), get_caller_address(), dao_fees);

            self.emit(DaoFeesCollected { to: get_caller_address(), fees: dao_fees });

            self.reentrancy_guard.end();
        }

        /// Collect accumulated developer fees
        fn collect_dev_fees(ref self: ContractState) {
            self.ownable.assert_only_owner();
            self.reentrancy_guard.start();

            // Ensure dev fees are available to collect
            let dev_fees = self.accumulated_dev_fees.read();
            assert(dev_fees > 0, Errors::NO_FEES_TO_COLLECT);
            assert(
                self._strk_balance_of(get_contract_address()) >= dev_fees,
                Errors::INSUFFICIENT_STARK,
            );

            // Reset accumulated developer fees
            self.accumulated_dev_fees.write(0_u256);
            // Transfer developer fees to owner
            self._strk_transfer(get_contract_address(), get_caller_address(), dev_fees);

            self.emit(DevFeesCollected { to: get_caller_address(), fees: dev_fees });

            self.reentrancy_guard.end();
        }

        /// Set the DAO and developer fees
        /// # Arguments
        /// * `dao_fee_bps` - The DAO fee in basis points
        /// * `dev_fee_bps` - The developer fee in basis points
        fn set_fees(ref self: ContractState, dao_fee_bps: u16, dev_fee_bps: u16) {
            self.ownable.assert_only_owner();
            self._set_fees(dao_fee_bps, dev_fee_bps);
        }

        /// Set the minimum stake amount
        /// # Arguments
        /// * `new_amount` - The new minimum stake amount
        fn set_min_stake_amount(ref self: ContractState, new_amount: u256) {
            self.ownable.assert_only_owner();
            self._set_min_stake_amount(new_amount);
        }

        /// Set the unlock period
        /// # Arguments
        /// * `new_period` - The new unlock period in seconds
        fn set_unlock_period(ref self: ContractState, new_period: u64) {
            self.ownable.assert_only_owner();
            self._set_unlock_period(new_period);
        }

        /// Set the claim window
        /// # Arguments
        /// * `new_window` - The new claim window in seconds
        fn set_claim_window(ref self: ContractState, new_window: u64) {
            self.ownable.assert_only_owner();
            self._set_claim_window(new_window);
        }

        /// Pause the contract
        fn pause(ref self: ContractState) {
            self.ownable.assert_only_owner();
            self.pausable.pause();
        }

        /// Unpause the contract
        fn unpause(ref self: ContractState) {
            self.ownable.assert_only_owner();
            self.pausable.unpause();
        }

        fn set_withdrawal_queue_nft(ref self: ContractState, nft_address: ContractAddress) {
            self.ownable.assert_only_owner();
            self.withdrawal_queue_nft.write(nft_address);
        }

        /// Claim rewards from validator
        /// # Access Control
        /// Only the contract owner can call this function
        fn claim_validator_rewards(ref self: ContractState) {
            self.ownable.assert_only_owner();
            self.reentrancy_guard.start();

            let validator_pool = self.validator_pool.read();
            assert(!validator_pool.is_zero(), 'Validator not set');

            // Claim rewards from validator
            let rewards = self._claim_rewards_from_validator();

            assert(rewards > 0, 'No rewards to claim');

            // Calculate fees and user rewards (same logic as add_rewards)
            let dao_fees = (rewards * self.dao_fee_basis_points.read().into())
                / Constants::BASIS_POINTS;
            let dev_fees = (rewards * self.dev_fee_basis_points.read().into())
                / Constants::BASIS_POINTS;
            let total_fees = dao_fees + dev_fees;
            let user_rewards = rewards - total_fees;

            // Update total pooled STRK and accumulated fees
            self.total_pooled_STRK.write(self.total_pooled_STRK.read() + user_rewards);
            self.accumulated_dao_fees.write(self.accumulated_dao_fees.read() + dao_fees);
            self.accumulated_dev_fees.write(self.accumulated_dev_fees.read() + dev_fees);

            self.emit(ValidatorRewardsClaimed { rewards, dao_fees, dev_fees, user_rewards });

            self.reentrancy_guard.end();
        }

        /// Start unbonding from validator
        /// # Arguments
        /// * `amount` - The amount of STRK tokens to unbond
        /// # Access Control
        /// Only the contract owner can call this function
        fn unstake_from_validator(ref self: ContractState, amount: u256) {
            self.ownable.assert_only_owner();
            self.reentrancy_guard.start();

            let validator_pool = self.validator_pool.read();
            assert(!validator_pool.is_zero(), 'Validator not set');
            assert(amount > 0, Errors::INVALID_AMOUNT);

            let delegated = self.total_delegated_to_validator.read();
            assert(delegated >= amount, 'Insufficient delegated amount');

            // Check no pending unbonding
            assert(self.pending_validator_unbonding.read() == 0, 'Unbonding already pending');

            // Start unbonding process
            self._start_unbonding_from_validator(amount);

            // Track unbonding
            self.pending_validator_unbonding.write(amount);

            // Store the time when unbonding was initiated (for informational/UI purposes only)
            let unbond_initiated_time = get_block_timestamp();
            self.validator_unbond_time.write(unbond_initiated_time);

            self
                .emit(
                    ValidatorUnbondingStarted {
                        amount,
                        unbond_time: unbond_initiated_time // When it was started, not when it completes
                    },
                );

            self.reentrancy_guard.end();
        }

        /// Complete unbonding from validator
        /// Can be called after the validator pool's unbonding period has passed
        /// The validator pool contract will revert if the unbonding period is not complete
        /// # Access Control
        /// Only the contract owner can call this function
        fn complete_validator_unstaking(ref self: ContractState) {
            self.ownable.assert_only_owner();
            self.reentrancy_guard.start();

            let pending = self.pending_validator_unbonding.read();
            assert(pending > 0, 'No pending unbonding');

            // REMOVED: Time check - let validator pool handle this
            // let unbond_time = self.validator_unbond_time.read();
            // assert(get_block_timestamp() >= unbond_time, 'Unbonding period not finished');

            // Complete unbonding - STRK returns to contract
            // This will revert if the validator pool's unbonding period is not finished
            let returned_amount = self._complete_unbonding_from_validator();

            // Update tracking
            self
                .total_delegated_to_validator
                .write(self.total_delegated_to_validator.read() - pending);
            self.pending_validator_unbonding.write(0);
            self.validator_unbond_time.write(0);

            self.emit(ValidatorUnbondingCompleted { amount: returned_amount });

            self.reentrancy_guard.end();
        }
    }

    // ====================================
    // Internal Functions
    // ====================================
    #[generate_trait]
    impl Internal of InternalTrait {
        /// Helper to get STRK token dispatcher
        fn _strk_dispatcher(self: @ContractState) -> IERC20Dispatcher {
            IERC20Dispatcher { contract_address: self.strk_token.read() }
        }

        /// Helper to transfer STRK tokens
        /// # Arguments
        /// * `payer` - The address paying the STRK tokens
        /// * `recipient` - The address receiving the STRK tokens
        /// * `amount` - The amount of STRK tokens to transfer
        /// Transfer STRK tokens
        fn _strk_transfer(
            ref self: ContractState,
            payer: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) {
            let token = self._strk_dispatcher();

            // Perform transfer based on payer
            let mut transfer_success: bool = false;
            // If payer is contract address, use direct transfer
            if payer == get_contract_address() {
                transfer_success = token.transfer(recipient, amount);
            } else {
                // Otherwise, use transferFrom
                transfer_success = token.transfer_from(payer, recipient, amount);
            }

            assert(transfer_success, Errors::TRANSFER_FAILED);
        }

        /// Helper to get STRK token balance of an account
        /// # Arguments
        /// * `account` - The address of the account
        /// # Returns
        /// The STRK token balance of the account
        fn _strk_balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            let token = self._strk_dispatcher();
            token.balance_of(account)
        }

        /// Set the DAO and developer fees
        /// # Arguments
        /// * `dao_fee_bps` - The DAO fee in basis points
        /// * `dev_fee_bps` - The developer fee in basis points
        fn _set_fees(ref self: ContractState, dao_fee_bps: u16, dev_fee_bps: u16) {
            assert(dao_fee_bps + dev_fee_bps <= Constants::MAX_TOTAL_FEE, Errors::FEES_TOO_HIGH);

            self.dao_fee_basis_points.write(dao_fee_bps);
            self.dev_fee_basis_points.write(dev_fee_bps);

            self.emit(FeesUpdated { dao_fee_bps, dev_fee_bps });
        }

        /// Set the minimum stake amount
        /// # Arguments
        /// * `new_amount` - The new minimum stake amount
        fn _set_min_stake_amount(ref self: ContractState, new_amount: u256) {
            assert(new_amount > 0, Errors::INVALID_AMOUNT);

            let old_amount = self.min_stake_amount.read();
            self.min_stake_amount.write(new_amount);

            self.emit(MinStakeAmountUpdated { old_amount, new_amount });
        }

        /// Set the unlock period
        /// # Arguments
        /// * `new_period` - The new unlock period in seconds
        fn _set_unlock_period(ref self: ContractState, new_period: u64) {
            // Validate unlock period
            assert(new_period >= Constants::MIN_UNLOCK_PERIOD, Errors::BELOW_MIN);
            assert(new_period <= Constants::MAX_UNLOCK_PERIOD, Errors::ABOVE_MAX);

            let old_period = self.unlock_period.read();
            self.unlock_period.write(new_period);

            self.emit(UnlockPeriodUpdated { old_period, new_period });
        }

        /// Set the claim window
        /// # Arguments
        /// * `new_window` - The new claim window in seconds
        fn _set_claim_window(ref self: ContractState, new_window: u64) {
            // Validate claim window
            assert(new_window >= Constants::MIN_CLAIM_WINDOW, Errors::BELOW_MIN);
            assert(new_window <= Constants::MAX_CLAIM_WINDOW, Errors::ABOVE_MAX);

            let old_window = self.claim_window.read();
            self.claim_window.write(new_window);

            self.emit(ClaimWindowUpdated { old_window, new_window });
        }

        /// Convert STRK amount to spSTRK amount based on current exchange rate
        /// # Arguments
        /// * `strk_amount` - The amount of STRK tokens
        /// # Returns
        /// The equivalent amount of spSTRK tokens
        fn _strk_to_sp_strk(self: @ContractState, strk_amount: u256) -> u256 {
            // If no spSTRK supply or pooled STRK, mint 1:1
            if self.erc20.total_supply() == 0 || self.total_pooled_STRK.read() == 0 {
                strk_amount
            } else {
                // Calculate spSTRK amount based on exchange rate
                (strk_amount * self.erc20.total_supply()) / self.total_pooled_STRK.read()
            }
        }

        /// Convert spSTRK amount to STRK amount based on current exchange rate
        /// # Arguments
        /// * `sp_strk_amount` - The amount of spSTRK tokens
        /// # Returns
        /// The equivalent amount of STRK tokens
        fn _sp_strk_to_strk(self: @ContractState, sp_strk_amount: u256) -> u256 {
            // If no spSTRK supply or pooled STRK, return 0
            if self.erc20.total_supply() == 0 || self.total_pooled_STRK.read() == 0 {
                0_u256
            } else {
                // Calculate STRK amount based on exchange rate
                (sp_strk_amount * self.total_pooled_STRK.read()) / self.erc20.total_supply()
            }
        }

        /// Auto-delegate excess STRK to validator (maintaining 10% buffer)
        fn _auto_delegate_to_validator(ref self: ContractState) {
            let validator_pool = self.validator_pool.read();

            // Skip if no validator set
            if validator_pool.is_zero() {
                return;
            }

            let total_pooled = self.total_pooled_STRK.read();
            let contract_balance = self._strk_balance_of(get_contract_address());

            // Calculate 10% buffer requirement
            let min_buffer = (total_pooled * 1000) / 10000; // 10%

            // Only delegate if we have excess above buffer
            if contract_balance > min_buffer {
                let to_delegate = contract_balance - min_buffer;

                // Only delegate if amount is meaningful (> 0.01 STRK to avoid dust)
                if to_delegate > 10_000_000_000_000_000 { // 0.01 STRK
                    let current_delegated = self.total_delegated_to_validator.read();

                    if current_delegated == 0 {
                        // First time delegation
                        self._enter_delegation_pool(to_delegate);
                    } else {
                        // Add to existing delegation
                        self._add_to_delegation_pool(to_delegate);
                    }

                    // Update tracking
                    self.total_delegated_to_validator.write(current_delegated + to_delegate);

                    self
                        .emit(
                            DelegatedToValidator {
                                amount: to_delegate,
                                total_delegated: current_delegated + to_delegate,
                            },
                        );
                }
            }
        }

        /// Enter delegation pool (first time)
        fn _enter_delegation_pool(ref self: ContractState, amount: u256) {
            let validator_pool = IValidatorPoolDispatcher {
                contract_address: self.validator_pool.read(),
            };

            let contract_address = get_contract_address();
            let amount_u128: u128 = amount.try_into().expect('Amount overflow');

            // Transfer STRK to validator for staking
            let strk_token = self._strk_dispatcher();
            strk_token.approve(self.validator_pool.read(), amount);

            // Enter pool (reward_address = our contract address)
            validator_pool.enter_delegation_pool(contract_address, amount_u128);
        }

        /// Add to existing delegation
        fn _add_to_delegation_pool(ref self: ContractState, amount: u256) {
            let validator_pool = IValidatorPoolDispatcher {
                contract_address: self.validator_pool.read(),
            };

            let contract_address = get_contract_address();
            let amount_u128: u128 = amount.try_into().expect('Amount overflow');

            // Transfer STRK to validator for staking
            let strk_token = self._strk_dispatcher();
            strk_token.approve(self.validator_pool.read(), amount);

            // Add to pool
            validator_pool.add_to_delegation_pool(contract_address, amount_u128);
        }

        /// Start unbonding from validator
        fn _start_unbonding_from_validator(ref self: ContractState, amount: u256) {
            let validator_pool = IValidatorPoolDispatcher {
                contract_address: self.validator_pool.read(),
            };

            let amount_u128: u128 = amount.try_into().expect('Amount overflow');

            // Request to exit delegation pool (starts 7-day unbonding)
            validator_pool.exit_delegation_pool_intent(amount_u128);
        }

        /// Complete unbonding from validator (after 7 days)
        fn _complete_unbonding_from_validator(ref self: ContractState) -> u256 {
            let validator_pool = IValidatorPoolDispatcher {
                contract_address: self.validator_pool.read(),
            };

            let contract_address = get_contract_address();

            // Complete exit - STRK returns to our contract
            let returned: u128 = validator_pool.exit_delegation_pool_action(contract_address);

            returned.into()
        }

        /// Claim rewards from validator
        fn _claim_rewards_from_validator(ref self: ContractState) -> u256 {
            let validator_pool = IValidatorPoolDispatcher {
                contract_address: self.validator_pool.read(),
            };

            let contract_address = get_contract_address();

            // Claim rewards - STRK rewards come to our contract
            let rewards: u128 = validator_pool.claim_rewards(contract_address);

            rewards.into()
        }
    }
}
