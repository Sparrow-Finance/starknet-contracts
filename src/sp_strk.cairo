#[starknet::contract]
pub mod spSTRK {
    use starknet::{
        ContractAddress, ClassHash, get_caller_address, get_contract_address, get_block_timestamp,
    };
    use core::num::traits::Zero;
    use starknet::storage::{
        Map, StoragePointerWriteAccess, StoragePointerReadAccess, StoragePathEntry,
    };
    use starknet::event::EventEmitter;
    use openzeppelin::token::erc20::{
        ERC20Component, ERC20HooksEmptyImpl, ERC20ABIDispatcher, ERC20ABIDispatcherTrait,
    };
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use openzeppelin::security::pausable::PausableComponent;
    use openzeppelin::security::reentrancyguard::ReentrancyGuardComponent;

    use sp_strk::components::constants::Constants;
    use sp_strk::interfaces::sp_strk::{IspSTRK, UnlockRequest, Errors};
    use sp_strk::interfaces::staking::{IDelegationPoolDispatcher, IDelegationPoolDispatcherTrait};
    use sp_strk::types::init::InitParams;
    use sp_strk::types::validator::ValidatorInfo;

    // ====================================
    // OpenZeppelin components and their implementations
    // ====================================
    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(
        path: ReentrancyGuardComponent, storage: reentrancy_guard, event: ReentrancyGuardEvent,
    );

    // ERC20 Mixin
    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

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
        unlock_requests: Map<ContractAddress, UnlockRequest>,
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
        // Multi-validator delegation system
        validators: Map<u32, ValidatorInfo>,
        // Total number of validators added (never decreases)
        validator_count: u32,
        // Total STRK delegated across all validators
        total_delegated_to_validators: u256,

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

    #[derive(Drop, starknet::Event)]
    struct ValidatorAdded {
        validator_id: u32,
        pool_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct ValidatorStatusChanged {
        validator_id: u32,
        is_active: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct DelegatedToValidator {
        validator_id: u32,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct ValidatorRewardsClaimed {
        validator_id: u32,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct ValidatorExitIntent {
        validator_id: u32,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct ValidatorExitCompleted {
        validator_id: u32,
        amount: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Staked: Staked,
        UnlockRequested: UnlockRequested,
        Unstaked: Unstaked,
        UnlockCancelled: UnlockCancelled,
        Deposited: Deposited,
        Withdrawn: Withdrawn,
        RewardsAdded: RewardsAdded,
        DaoFeesCollected: DaoFeesCollected,
        DevFeesCollected: DevFeesCollected,
        FeesUpdated: FeesUpdated,
        MinStakeAmountUpdated: MinStakeAmountUpdated,
        UnlockPeriodUpdated: UnlockPeriodUpdated,
        ClaimWindowUpdated: ClaimWindowUpdated,
        ValidatorAdded: ValidatorAdded,
        ValidatorStatusChanged: ValidatorStatusChanged,
        DelegatedToValidator: DelegatedToValidator,
        ValidatorRewardsClaimed: ValidatorRewardsClaimed,
        ValidatorExitIntent: ValidatorExitIntent,
        ValidatorExitCompleted: ValidatorExitCompleted,

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

        // Initialize Config params
        self.strk_token.write(params.strk_token);
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

            // Enforce minimum first deposit
            if self.erc20.total_supply() == 0 {
                // The first deposit must be at least 0.000000000001 STRK
                assert(strk_amount >= 1000000, Errors::LOW_FIRST_DEPOSIT);
            } else {
                // Ensure non-zero shares are minted
                assert(sp_strk_amount > 0, Errors::INSUFFICIENT_SHARES);
            }

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
            let pending_request = self.unlock_requests.entry(user).read();
            assert(pending_request.expiry_time == 0, Errors::REQUEST_PENDING);

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
                .entry(user)
                .write(UnlockRequest { sp_strk_amount, min_strk_out, unlock_time, expiry_time });

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
        fn claim_unlock(ref self: ContractState) {
            // Ensure contract is not paused and prevent reentrancy
            self.pausable.assert_not_paused();
            // Start reentrancy guard
            self.reentrancy_guard.start();

            // Get caller address and their unlock request
            let user = get_caller_address();
            let request = self.unlock_requests.entry(user).read();

            // Validate unlock request
            assert(request.expiry_time != 0, Errors::REQUEST_NOT_EXIST);
            // Ensure request has not expired
            assert(request.expiry_time >= get_block_timestamp(), Errors::REQUEST_EXPIRED);
            // Ensure unlock time has passed
            assert(request.unlock_time <= get_block_timestamp(), Errors::REQUEST_NOT_READY);

            // Calculate STRK amount to be received
            let strk_amount = self._sp_strk_to_strk(request.sp_strk_amount);

            // Validate calculated STRK amount
            assert(strk_amount > 0, Errors::INVALID_STRK_AMOUNT);
            // Ensure contract has enough STRK balance
            assert(
                self._strk_balance_of(get_contract_address()) >= strk_amount,
                Errors::INSUFFICIENT_STARK,
            );
            // Enforce slippage protection
            assert(strk_amount >= request.min_strk_out, Errors::SLIPPAGE_EXCEEDED);

            // Clear the unlock request
            self
                .unlock_requests
                .entry(user)
                .write(
                    UnlockRequest {
                        sp_strk_amount: 0_u256,
                        min_strk_out: 0_u256,
                        unlock_time: 0_u64,
                        expiry_time: 0_u64,
                    },
                );
            // Update total pooled STRK
            self.total_pooled_STRK.write(self.total_pooled_STRK.read() - strk_amount);

            // Burn spSTRK tokens and transfer STRK tokens to user
            self.erc20.burn(get_contract_address(), request.sp_strk_amount);
            self._strk_transfer(get_contract_address(), user, strk_amount);

            // Emit Unstaked event
            self.emit(Unstaked { user, strk_amount, sp_strk_amount: request.sp_strk_amount });

            // End reentrancy guard
            self.reentrancy_guard.end();
        }

        /// Cancel a pending unlock request and return spSTRK tokens to the user
        /// # Access Control
        /// The caller must have a valid unlock request
        fn cancel_unlock(ref self: ContractState) {
            // Ensure contract is not paused and prevent reentrancy
            self.pausable.assert_not_paused();
            // Start reentrancy guard
            self.reentrancy_guard.start();

            // Get caller address and their unlock request
            let user = get_caller_address();
            let request = self.unlock_requests.entry(user).read();

            // Ensure a valid unlock request exists
            assert(request.expiry_time != 0, Errors::REQUEST_NOT_EXIST);

            // Clear the unlock request
            self
                .unlock_requests
                .entry(user)
                .write(
                    UnlockRequest {
                        sp_strk_amount: 0_u256,
                        min_strk_out: 0_u256,
                        unlock_time: 0_u64,
                        expiry_time: 0_u64,
                    },
                );

            // Return spSTRK tokens to the user
            self.erc20._transfer(get_contract_address(), user, request.sp_strk_amount);

            // Emit UnlockCancelled event
            self.emit(UnlockCancelled { user, request });

            // End reentrancy guard
            self.reentrancy_guard.end();
        }

        /// Get the unlock request details for a user
        /// # Arguments
        /// * `user` - The address of the user
        /// # Returns
        /// A tuple containing the UnlockRequest, the STRK amount, a boolean indicating if it's
        /// ready to claim, and a boolean indicating if it has expired
        fn get_unlock_request(
            self: @ContractState, user: ContractAddress,
        ) -> (UnlockRequest, u256, bool, bool) {
            // Retrieve the unlock request
            let request = self.unlock_requests.entry(user).read();
            // Ensure a valid unlock request exists
            assert(request.expiry_time != 0, Errors::REQUEST_NOT_EXIST);

            // Calculate STRK amount to be received
            let strk_amount = self._sp_strk_to_strk(request.sp_strk_amount);
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

        /// ====================================
        /// Admin Functions
        /// ====================================


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

        // ====================================
        // Multi-Validator Delegation Functions (V2)
        // ====================================

        /// Add a new validator pool (can never be deleted)
        /// # Arguments
        /// * `pool_address` - Address of the validator's delegation pool contract
        /// # Returns
        /// Validator ID (u32)
        /// # Access Control
        /// Only owner can add validators
        fn add_validator(ref self: ContractState, pool_address: ContractAddress) -> u32 {
            // Only owner can add validators
            self.ownable.assert_only_owner();

            // Validate pool address
            assert(!pool_address.is_zero(), 'Invalid pool address');

            // Check for duplicate pool addresses
            let count = self.validator_count.read();
            let mut i: u32 = 0;
            loop {
                if i >= count {
                    break;
                }
                let existing = self.validators.entry(i).read();
                assert(existing.pool_address != pool_address, 'Pool already added');
                i += 1;
                // Safety: prevent infinite loop
                assert(i <= count, 'Loop overflow');
            };

            // Get next validator ID
            let validator_id = self.validator_count.read();
            
            // Create validator info (starts inactive)
            let validator_info = ValidatorInfo {
                pool_address,
                is_active: false,
                total_delegated: 0,
                pending_exit: 0,
            };

            // Store validator
            self.validators.entry(validator_id).write(validator_info);
            
            // Increment count
            self.validator_count.write(validator_id + 1);

            // Emit event
            self.emit(ValidatorAdded { validator_id, pool_address });

            validator_id
        }

        /// Set validator active/inactive status
        /// # Arguments
        /// * `validator_id` - ID of the validator
        /// * `is_active` - New active status
        /// # Access Control
        /// Only owner can change validator status
        fn set_validator_status(ref self: ContractState, validator_id: u32, is_active: bool) {
            // Only owner can change status
            self.ownable.assert_only_owner();

            // Check validator exists
            let validator_count = self.validator_count.read();
            assert(validator_id < validator_count, 'Validator does not exist');

            // Get and update validator
            let mut validator = self.validators.entry(validator_id).read();
            validator.is_active = is_active;
            self.validators.entry(validator_id).write(validator);

            // Emit event
            self.emit(ValidatorStatusChanged { validator_id, is_active });
        }

        /// Delegate STRK to specific validator
        /// # Arguments
        /// * `validator_id` - ID of the validator to delegate to
        /// * `amount` - Amount of STRK to delegate
        /// # Access Control
        /// Only owner can delegate
        fn delegate_to_validator(ref self: ContractState, validator_id: u32, amount: u256) {
            // Only owner can delegate
            self.ownable.assert_only_owner();
            
            // Reentrancy protection
            self.reentrancy_guard.start();

            // Validate amount
            assert(amount > 0, Errors::INVALID_AMOUNT);

            // Check validator exists
            let validator_count = self.validator_count.read();
            assert(validator_id < validator_count, 'Validator does not exist');

            // Get validator and check if active
            let mut validator = self.validators.entry(validator_id).read();
            assert(validator.is_active, 'Validator is not active');

            // Check contract has enough available STRK
            let contract_balance = self._strk_balance_of(get_contract_address());
            let total_delegated = self.total_delegated_to_validators.read();
            
            // CRITICAL: Check for underflow before subtraction
            assert(contract_balance >= total_delegated, 'Balance corrupted');
            let available = contract_balance - total_delegated;
            assert(amount <= available, 'Insufficient available STRK');

            // Convert u256 to u128
            let amount_u128: u128 = amount.try_into().expect('Amount too large for u128');

            // Get delegation pool dispatcher
            let pool = IDelegationPoolDispatcher { contract_address: validator.pool_address };

            // Approve STRK to delegation pool
            let strk_token = self._strk_dispatcher();
            strk_token.approve(validator.pool_address, amount);

            // Delegate to pool - use add_to_delegation_pool if already a member
            if validator.total_delegated > 0 {
                pool.add_to_delegation_pool(
                    pool_member: get_contract_address(),
                    amount: amount_u128
                );
            } else {
                pool.enter_delegation_pool(
                    reward_address: get_contract_address(),
                    amount: amount_u128
                );
            }

            // Update validator tracking
            let new_validator_delegated = validator.total_delegated + amount;
            assert(new_validator_delegated >= validator.total_delegated, 'Validator overflow');
            validator.total_delegated = new_validator_delegated;
            self.validators.entry(validator_id).write(validator);

            // Update total tracking
            let new_total = total_delegated + amount;
            assert(new_total >= total_delegated, 'Total overflow');
            self.total_delegated_to_validators.write(new_total);

            // Emit event
            self.emit(DelegatedToValidator { validator_id, amount });

            // End reentrancy protection
            self.reentrancy_guard.end();
        }

        /// Claim rewards from specific validator
        /// # Arguments
        /// * `validator_id` - ID of the validator to claim from
        /// # Returns
        /// Amount of rewards claimed
        /// # Access Control
        /// Only owner can claim
        fn claim_validator_rewards(ref self: ContractState, validator_id: u32) -> u256 {
            // Only owner can claim
            self.ownable.assert_only_owner();
            
            // Reentrancy protection
            self.reentrancy_guard.start();

            // Check validator exists
            let validator_count = self.validator_count.read();
            assert(validator_id < validator_count, 'Validator does not exist');

            // Get validator
            let validator = self.validators.entry(validator_id).read();

            // Get delegation pool dispatcher
            let pool = IDelegationPoolDispatcher { contract_address: validator.pool_address };

            // Claim rewards
            let rewards_u128 = pool.claim_rewards(get_contract_address());
            let rewards: u256 = rewards_u128.into();

            // Check if any rewards
            assert(rewards > 0, 'No rewards to claim');

            // Add rewards to total pooled STRK (increases exchange rate!)
            let current_pooled = self.total_pooled_STRK.read();
            let new_pooled = current_pooled + rewards;
            assert(new_pooled >= current_pooled, 'Rewards overflow');
            self.total_pooled_STRK.write(new_pooled);

            // Emit event
            self.emit(ValidatorRewardsClaimed { validator_id, amount: rewards });

            // End reentrancy protection
            self.reentrancy_guard.end();

            rewards
        }

        /// Signal intent to exit from validator (step 1 of 2)
        /// # Arguments
        /// * `validator_id` - ID of the validator to exit from
        /// * `amount` - Amount to exit
        /// # Access Control
        /// Only owner can exit
        fn exit_validator_intent(ref self: ContractState, validator_id: u32, amount: u256) {
            // Only owner can exit
            self.ownable.assert_only_owner();
            
            // Reentrancy protection
            self.reentrancy_guard.start();

            // Validate amount
            assert(amount > 0, Errors::INVALID_AMOUNT);

            // Check validator exists
            let validator_count = self.validator_count.read();
            assert(validator_id < validator_count, 'Validator does not exist');

            // Get validator
            let mut validator = self.validators.entry(validator_id).read();

            // Check available amount (delegated - pending_exit)
            assert(validator.pending_exit <= validator.total_delegated, 'State corrupted');
            let available_to_exit = validator.total_delegated - validator.pending_exit;
            assert(amount <= available_to_exit, 'Insufficient validator amount');

            // Convert u256 to u128
            let amount_u128: u128 = amount.try_into().expect('Amount too large for u128');

            // Get delegation pool dispatcher
            let pool = IDelegationPoolDispatcher { contract_address: validator.pool_address };

            // Signal exit intent to pool
            pool.exit_delegation_pool_intent(amount_u128);

            // Update validator pending exit
            let new_pending = validator.pending_exit + amount;
            assert(new_pending >= validator.pending_exit, 'Pending overflow');
            validator.pending_exit = new_pending;
            self.validators.entry(validator_id).write(validator);

            // Emit event
            self.emit(ValidatorExitIntent { validator_id, amount });
            
            // End reentrancy protection
            self.reentrancy_guard.end();
        }

        /// Complete exit from validator (step 2 of 2)
        /// # Arguments
        /// * `validator_id` - ID of the validator to complete exit from
        /// # Returns
        /// Amount of STRK returned
        /// # Access Control
        /// Only owner can complete exit
        fn exit_validator_action(ref self: ContractState, validator_id: u32) -> u256 {
            // Only owner can complete exit
            self.ownable.assert_only_owner();
            
            // Reentrancy protection
            self.reentrancy_guard.start();

            // Check validator exists
            let validator_count = self.validator_count.read();
            assert(validator_id < validator_count, 'Validator does not exist');

            // Get validator
            let mut validator = self.validators.entry(validator_id).read();

            // Get delegation pool dispatcher
            let pool = IDelegationPoolDispatcher { contract_address: validator.pool_address };

            // Complete exit
            let exited_u128 = pool.exit_delegation_pool_action(get_contract_address());
            let exited: u256 = exited_u128.into();

            // Update validator tracking
            assert(exited <= validator.total_delegated, 'Exit exceeds delegated');
            validator.total_delegated = validator.total_delegated - exited;
            
            assert(exited <= validator.pending_exit, 'Exit exceeds pending');
            validator.pending_exit = validator.pending_exit - exited;
            
            self.validators.entry(validator_id).write(validator);

            // Update total tracking
            let total_delegated = self.total_delegated_to_validators.read();
            assert(exited <= total_delegated, 'Exit exceeds total');
            self.total_delegated_to_validators.write(total_delegated - exited);

            // Emit event
            self.emit(ValidatorExitCompleted { validator_id, amount: exited });

            // End reentrancy protection
            self.reentrancy_guard.end();

            exited
        }

        // ====================================
        // Multi-Validator View Functions
        // ====================================

        /// Get validator information
        /// # Arguments
        /// * `validator_id` - ID of the validator
        /// # Returns
        /// ValidatorInfo struct
        fn get_validator_info(self: @ContractState, validator_id: u32) -> ValidatorInfo {
            let validator_count = self.validator_count.read();
            assert(validator_id < validator_count, 'Validator does not exist');
            self.validators.entry(validator_id).read()
        }

        /// Get total number of validators
        /// # Returns
        /// Total validator count
        fn get_validator_count(self: @ContractState) -> u32 {
            self.validator_count.read()
        }

        /// Get total STRK delegated across all validators
        /// # Returns
        /// Total delegated amount
        fn get_total_delegated_to_validators(self: @ContractState) -> u256 {
            self.total_delegated_to_validators.read()
        }
        
    }

    // ====================================
    // Internal Functions
    // ====================================
    #[generate_trait]
    impl Internal of InternalTrait {
        /// Helper to get STRK token dispatcher
        fn _strk_dispatcher(self: @ContractState) -> ERC20ABIDispatcher {
            ERC20ABIDispatcher { contract_address: self.strk_token.read() }
        }

        /// Helper to transfer STRK tokens
        /// # Arguments
        /// * `payer` - The address paying the STRK tokens
        /// * `recipient` - The address receiving the STRK tokens
        /// * `amount` - The amount of STRK tokens to transfer
        fn _strk_transfer(
            self: @ContractState, payer: ContractAddress, recipient: ContractAddress, amount: u256,
        ) {
            let token = self._strk_dispatcher();

            // Perform transfer based on payer
            let mut transfer_success: bool = false;
            // If payer is contract address, use direct transfer
            if payer == get_contract_address() {
                transfer_success = token.transfer(recipient, amount);
            } else {
                // Otherwise, use transferFrom
                transfer_success = token.transferFrom(payer, recipient, amount);
            }

            // Ensure transfer was successful
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

        /// Stake STRK and mint spSTRK to a specific receiver (for ERC4626)
        /// # Arguments
        /// * `strk_amount` - Amount of STRK to stake
        /// * `receiver` - Address to receive spSTRK
        /// # Returns
        /// Amount of spSTRK minted
        fn stake_with_receiver(ref self: ContractState, strk_amount: u256, receiver: ContractAddress) -> u256 {
            // Ensure contract is not paused
            self.pausable.assert_not_paused();
            
            // Validate stake amount
            assert(strk_amount >= self.min_stake_amount.read(), Errors::BELOW_MINIMUM_STAKE);
            assert(!receiver.is_zero(), Errors::INVALID_AMOUNT);

            // Calculate spSTRK amount to mint
            let sp_strk_amount = self._strk_to_sp_strk(strk_amount);

            // Enforce minimum first deposit
            if self.erc20.total_supply() == 0 {
                assert(strk_amount >= 1000000, Errors::LOW_FIRST_DEPOSIT);
            } else {
                assert(sp_strk_amount > 0, Errors::INSUFFICIENT_SHARES);
            }

            // Get caller address
            let caller = get_caller_address();

            // Transfer STRK tokens from caller to contract
            self._strk_transfer(caller, get_contract_address(), strk_amount);
            
            // Mint spSTRK tokens to receiver
            self.erc20.mint(receiver, sp_strk_amount);

            // Update total pooled STRK
            self.total_pooled_STRK.write(self.total_pooled_STRK.read() + strk_amount);

            // Emit Staked event
            self.emit(Staked { user: receiver, strk_amount, sp_strk_amount });

            sp_strk_amount
        }
    }

    // ====================================
    // ERC4626 Implementation
    // ====================================
    #[abi(embed_v0)]
    impl ERC4626Impl of sp_strk::interfaces::erc4626::IERC4626<ContractState> {
        /// Returns the address of the underlying STRK token
        fn asset(self: @ContractState) -> ContractAddress {
            self.strk_token.read()
        }

        /// Returns total assets under management (total pooled STRK)
        fn total_assets(self: @ContractState) -> u256 {
            self.total_pooled_STRK.read()
        }

        /// Convert STRK assets to spSTRK shares
        fn convert_to_shares(self: @ContractState, assets: u256) -> u256 {
            self._strk_to_sp_strk(assets)
        }

        /// Convert spSTRK shares to STRK assets
        fn convert_to_assets(self: @ContractState, shares: u256) -> u256 {
            self._sp_strk_to_strk(shares)
        }

        /// Maximum deposit allowed (unlimited if not paused)
        fn max_deposit(self: @ContractState, receiver: ContractAddress) -> u256 {
            if self.pausable.is_paused() {
                0_u256
            } else {
                // Return max u256
                0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff_u256
            }
        }

        /// Preview shares to be minted for assets
        fn preview_deposit(self: @ContractState, assets: u256) -> u256 {
            self._strk_to_sp_strk(assets)
        }

        /// Deposit STRK and receive spSTRK (ERC4626 standard)
        /// Maps to stake() function
        fn deposit(ref self: ContractState, assets: u256, receiver: ContractAddress) -> u256 {
            // Call the existing stake function with receiver
            self.stake_with_receiver(assets, receiver)
        }

        /// Maximum mint allowed
        fn max_mint(self: @ContractState, receiver: ContractAddress) -> u256 {
            if self.pausable.is_paused() {
                0_u256
            } else {
                // Return max u256
                0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff_u256
            }
        }

        /// Preview assets needed to mint shares
        fn preview_mint(self: @ContractState, shares: u256) -> u256 {
            self._sp_strk_to_strk(shares)
        }

        /// Mint exact shares by depositing assets
        fn mint(ref self: ContractState, shares: u256, receiver: ContractAddress) -> u256 {
            // Calculate assets needed
            let assets = self._sp_strk_to_strk(shares);
            
            // Call stake with receiver
            self.stake_with_receiver(assets, receiver);
            
            assets
        }

        /// Maximum withdraw (0 - must use unlock flow)
        fn max_withdraw(self: @ContractState, owner: ContractAddress) -> u256 {
            // Instant withdrawal not supported - must use unlock flow
            0_u256
        }

        /// Preview shares to burn for assets
        fn preview_withdraw(self: @ContractState, assets: u256) -> u256 {
            self._strk_to_sp_strk(assets)
        }

        /// Withdraw not supported - use request_unlock/claim_unlock instead
        fn withdraw(
            ref self: ContractState, 
            assets: u256, 
            receiver: ContractAddress, 
            owner: ContractAddress
        ) -> u256 {
            // ERC4626 withdraw not supported
            // Users must use request_unlock() and claim_unlock()
            assert(false, 'Use request_unlock flow');
            0_u256
        }

        /// Maximum redeem (user's balance)
        fn max_redeem(self: @ContractState, owner: ContractAddress) -> u256 {
            self.erc20.balance_of(owner)
        }

        /// Preview assets to receive for shares
        fn preview_redeem(self: @ContractState, shares: u256) -> u256 {
            self._sp_strk_to_strk(shares)
        }

        /// Redeem not supported - use request_unlock/claim_unlock instead
        fn redeem(
            ref self: ContractState, 
            shares: u256, 
            receiver: ContractAddress, 
            owner: ContractAddress
        ) -> u256 {
            // ERC4626 redeem not supported
            // Users must use request_unlock() and claim_unlock()
            assert(false, 'Use request_unlock flow');
            0_u256
        }
    }
}
