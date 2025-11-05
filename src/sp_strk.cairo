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
        // Validator delegation pool address
        delegation_pool: ContractAddress,
        // Total STRK delegated to pool
        total_delegated_to_pool: u256,
        // Pending exit amount from delegation pool
        pending_delegation_exit: u256,

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
    struct DelegationPoolSet {
        old_address: ContractAddress,
        new_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct DelegatedToPool {
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct DelegationRewardsClaimed {
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct DelegationExitIntent {
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct DelegationExitCompleted {
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
        DelegationPoolSet: DelegationPoolSet,
        DelegatedToPool: DelegatedToPool,
        DelegationRewardsClaimed: DelegationRewardsClaimed,
        DelegationExitIntent: DelegationExitIntent,
        DelegationExitCompleted: DelegationExitCompleted,

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

        /// Deposit STRK tokens into the contract
        /// # Arguments
        /// * `strk_amount` - The amount of STRK tokens to deposit
        fn deposit(ref self: ContractState, strk_amount: u256) {
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
        fn withdraw(ref self: ContractState, strk_amount: u256) {
            self.ownable.assert_only_owner();
            self.reentrancy_guard.start();

            // Validate withdraw amount
            assert(strk_amount > 0, Errors::INVALID_AMOUNT);
            // Ensure contract has enough STRK balance
            assert(
                self._strk_balance_of(get_contract_address()) >= strk_amount,
                Errors::INSUFFICIENT_STARK,
            );

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
        // Validator Delegation Functions (V2)
        // ====================================

        /// Set the validator delegation pool address
        /// # Arguments
        /// * `pool_address` - Address of the validator's delegation pool contract
        /// # Access Control
        /// Only owner can set delegation pool
        /// # Example
        /// set_delegation_pool(0x123...abc) - Sets pool to validator's pool contract
        fn set_delegation_pool(ref self: ContractState, pool_address: ContractAddress) {
            // Only owner can set delegation pool
            self.ownable.assert_only_owner();

            // Get old address for event
            let old_address = self.delegation_pool.read();
            
            // Update delegation pool address
            self.delegation_pool.write(pool_address);

            // Emit event
            self.emit(DelegationPoolSet { old_address, new_address: pool_address });
        }

        /// Delegate STRK to validator pool
        /// # Arguments
        /// * `amount` - Amount of STRK to delegate (u256)
        /// # Access Control
        /// Only owner can delegate
        /// # Requirements
        /// - Delegation pool must be set first
        /// - Contract must have enough STRK balance
        /// - Amount must be greater than 0
        fn delegate_to_pool(ref self: ContractState, amount: u256) {
            // Only owner can delegate
            self.ownable.assert_only_owner();
            
            // Reentrancy protection
            self.reentrancy_guard.start();

            // Validate amount
            assert(amount > 0, Errors::INVALID_AMOUNT);
            
            // Check delegation pool is set
            let pool_address = self.delegation_pool.read();
            assert(!pool_address.is_zero(), 'Delegation pool not set');
            
            // Check contract has enough STRK
            let contract_balance = self._strk_balance_of(get_contract_address());
            assert(contract_balance >= amount, Errors::INSUFFICIENT_STARK);

            // Convert u256 to u128 for pool interface
            let amount_u128: u128 = amount.try_into().expect('Amount too large for u128');

            // Get delegation pool dispatcher
            let pool = IDelegationPoolDispatcher { contract_address: pool_address };

            // Approve STRK to delegation pool
            let strk_token = self._strk_dispatcher();
            strk_token.approve(pool_address, amount);

            // Delegate to pool (spSTRK contract receives rewards)
            pool.enter_delegation_pool(
                reward_address: get_contract_address(),
                amount: amount_u128
            );

            // Update tracking
            let current_delegated = self.total_delegated_to_pool.read();
            let new_delegated = current_delegated + amount;
            assert(new_delegated >= current_delegated, 'Delegation overflow');
            self.total_delegated_to_pool.write(new_delegated);

            // Emit event
            self.emit(DelegatedToPool { amount });

            // End reentrancy protection
            self.reentrancy_guard.end();
        }

        /// Claim delegation rewards from pool
        /// # Returns
        /// Amount of rewards claimed (u256)
        /// # Access Control
        /// Only owner can claim delegation rewards
        /// # Requirements
        /// - Delegation pool must be set
        /// # Effect
        /// - Rewards are added to total_pooled_STRK (increases exchange rate!)
        fn claim_delegation_rewards(ref self: ContractState) -> u256 {
            // Only owner can claim
            self.ownable.assert_only_owner();
            
            // Reentrancy protection
            self.reentrancy_guard.start();

            // Check delegation pool is set
            let pool_address = self.delegation_pool.read();
            assert(!pool_address.is_zero(), 'Delegation pool not set');

            // Get delegation pool dispatcher
            let pool = IDelegationPoolDispatcher { contract_address: pool_address };

            // Claim rewards (spSTRK contract is the pool member)
            let rewards_u128 = pool.claim_rewards(get_contract_address());
            let rewards: u256 = rewards_u128.into();

            // Add rewards to total pooled STRK (increases exchange rate!)
            let current_pooled = self.total_pooled_STRK.read();
            let new_pooled = current_pooled + rewards;
            assert(new_pooled >= current_pooled, 'Rewards overflow');
            self.total_pooled_STRK.write(new_pooled);

            // Emit event
            self.emit(DelegationRewardsClaimed { amount: rewards });

            // End reentrancy protection
            self.reentrancy_guard.end();

            rewards
        }

        /// Signal intent to exit delegation pool (step 1 of 2)
        /// # Arguments
        /// * `amount` - Amount to exit from pool (u256)
        /// # Access Control
        /// Only owner can exit delegation
        /// # Requirements
        /// - Delegation pool must be set
        /// - Amount must be greater than 0
        /// # Note
        /// After calling this, must wait for unlock period before calling exit_delegation_action
        fn exit_delegation_intent(ref self: ContractState, amount: u256) {
            // Only owner can exit
            self.ownable.assert_only_owner();

            // Validate amount
            assert(amount > 0, Errors::INVALID_AMOUNT);

            // Check delegation pool is set
            let pool_address = self.delegation_pool.read();
            assert(!pool_address.is_zero(), 'Delegation pool not set');

            // Check we have enough delegated
            let current_delegated = self.total_delegated_to_pool.read();
            assert(amount <= current_delegated, 'Insufficient delegated amount');

            // Convert u256 to u128
            let amount_u128: u128 = amount.try_into().expect('Amount too large for u128');

            // Get delegation pool dispatcher
            let pool = IDelegationPoolDispatcher { contract_address: pool_address };

            // Signal exit intent to pool
            pool.exit_delegation_pool_intent(amount_u128);

            // Track pending exit
            let current_pending = self.pending_delegation_exit.read();
            let new_pending = current_pending + amount;
            assert(new_pending >= current_pending, 'Pending exit overflow');
            self.pending_delegation_exit.write(new_pending);

            // Emit event (note: pool handles the unlock time internally)
            self.emit(DelegationExitIntent { amount });
        }

        /// Complete exit from delegation pool (step 2 of 2)
        /// # Returns
        /// Amount of STRK returned (u256)
        /// # Access Control
        /// Only owner can complete exit
        /// # Requirements
        /// - Delegation pool must be set
        /// - Must have called exit_delegation_intent first
        /// - Unlock period must have passed
        /// # Effect
        /// - STRK is returned to spSTRK contract
        /// - Tracking variables are updated
        fn exit_delegation_action(ref self: ContractState) -> u256 {
            // Only owner can complete exit
            self.ownable.assert_only_owner();
            
            // Reentrancy protection
            self.reentrancy_guard.start();

            // Check delegation pool is set
            let pool_address = self.delegation_pool.read();
            assert(!pool_address.is_zero(), 'Delegation pool not set');

            // Get delegation pool dispatcher
            let pool = IDelegationPoolDispatcher { contract_address: pool_address };

            // Complete exit (spSTRK contract is the pool member)
            let exited_u128 = pool.exit_delegation_pool_action(get_contract_address());
            let exited: u256 = exited_u128.into();

            // Update tracking - decrease delegated amount
            let current_delegated = self.total_delegated_to_pool.read();
            assert(exited <= current_delegated, 'Exit exceeds delegated amount');
            self.total_delegated_to_pool.write(current_delegated - exited);

            // Update tracking - decrease pending exit
            let current_pending = self.pending_delegation_exit.read();
            assert(exited <= current_pending, 'Exit exceeds pending amount');
            self.pending_delegation_exit.write(current_pending - exited);

            // Emit event
            self.emit(DelegationExitCompleted { amount: exited });

            // End reentrancy protection
            self.reentrancy_guard.end();

            exited
        }

        // ====================================
        // Delegation View Functions
        // ====================================

        /// Get delegation pool address
        /// # Returns
        /// Address of validator delegation pool
        fn get_delegation_pool(self: @ContractState) -> ContractAddress {
            self.delegation_pool.read()
        }

        /// Get total STRK delegated to pool
        /// # Returns
        /// Total amount delegated
        fn get_total_delegated_to_pool(self: @ContractState) -> u256 {
            self.total_delegated_to_pool.read()
        }

        /// Get pending delegation exit amount
        /// # Returns
        /// Amount pending exit
        fn get_pending_delegation_exit(self: @ContractState) -> u256 {
            self.pending_delegation_exit.read()
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
    }
}
