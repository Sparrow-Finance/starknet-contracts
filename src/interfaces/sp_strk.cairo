use starknet::ContractAddress;

// Structure to hold unlock request details
#[derive(Copy, Drop, Serde, PartialEq, Debug, starknet::Store)]
pub struct UnlockRequest {
    // Amount of spSTRK shares to unlock
    pub sp_strk_amount: u256,
    // Minimum STRK tokens expected after unlock
    pub strk_amount: u256,
    // Unlock time in UNIX timestamp
    pub unlock_time: u64,
    // Expiry time in UNIX timestamp
    pub expiry_time: u64,
}

#[starknet::interface]
pub trait IspSTRK<TContractState> {
    // ====================================
    // User functions
    // ====================================

    ///  Stake STRK tokens to receive spSTRK shares
    fn stake(ref self: TContractState, strk_amount: u256, min_sp_strk_out: u256) -> u256;
    ///  Request to unlock spSTRK shares for STRK tokens
    fn request_unlock(ref self: TContractState, sp_strk_amount: u256, min_strk_out: u256) -> u256;
    ///  Claim unlocked STRK tokens after the unlock period
    fn claim_unlock(ref self: TContractState, request_index: u256);
    ///  Cancel an existing unlock request
    fn cancel_unlock(ref self: TContractState, request_index: u256);

    fn claim_expired(ref self: TContractState, request_index: u256);

    fn get_unlock_request_count(self: @TContractState, user: ContractAddress) -> u256;

    ///  Get the unlock request details for a user
    fn get_unlock_request(
        self: @TContractState, user: ContractAddress, request_index: u256,
    ) -> (UnlockRequest, u256, bool, bool);
    ///  Get the current exchange rate of STRK to spSTRK
    fn get_exchange_rate(self: @TContractState) -> u256;
    ///  Preview the amount of spSTRK shares received for a given STRK amount
    fn preview_stake(self: @TContractState, strk_amount: u256) -> u256;
    ///  Preview the amount of STRK tokens received for a given spSTRK amount
    fn preview_unlock(self: @TContractState, sp_strk_amount: u256) -> u256;
    ///  Get overall contract statistics
    fn get_stats(self: @TContractState) -> (u256, u256, u256, u256, u256, u256, u16, u16);

    // ====================================
    // Admin functions
    // ====================================

    /// Deposit STRK tokens
    fn deposit(ref self: TContractState, strk_amount: u256);
    /// Withdraw STRK tokens
    fn withdraw(ref self: TContractState, strk_amount: u256);
    /// Add rewards to the staking pool
    fn add_rewards(ref self: TContractState, strk_amount: u256);

    fn collect_all_fees(ref self: TContractState);
    /// Collect accumulated DAO fees
    fn collect_dao_fees(ref self: TContractState);
    /// Collect accumulated developer fees
    fn collect_dev_fees(ref self: TContractState);
    /// Set the fee structure
    fn set_fees(ref self: TContractState, dao_fee_bps: u16, dev_fee_bps: u16);
    /// Set the minimum stake amount
    fn set_min_stake_amount(ref self: TContractState, new_amount: u256);
    /// Set the unlock period
    fn set_unlock_period(ref self: TContractState, new_period: u64);
    /// Set the claim window
    fn set_claim_window(ref self: TContractState, new_window: u64);
    /// Pause the contract
    fn pause(ref self: TContractState);
    /// Unpause the contract
    fn unpause(ref self: TContractState);
}

// Error messages used in the contract
pub mod Errors {
    pub const BELOW_MINIMUM_STAKE: felt252 = 'Below minimum stake';
    pub const LOW_FIRST_DEPOSIT: felt252 = 'First deposit too low';
    pub const FEES_TOO_HIGH: felt252 = 'Fees too high';
    pub const INSUFFICIENT_SHARES: felt252 = 'Insufficient shares';
    pub const INSUFFICIENT_BALANCE: felt252 = 'Insufficient balance';
    pub const INSUFFICIENT_STARK: felt252 = 'Insufficient STRK balance';
    pub const SLIPPAGE_EXCEEDED: felt252 = 'Slippage exceeded';
    pub const TRANSFER_FAILED: felt252 = 'STRK transfer failed';
    pub const INVALID_AMOUNT: felt252 = 'Invalid amount';
    pub const INVALID_STRK_AMOUNT: felt252 = 'Invalid STRK amount';
    pub const BELOW_MIN: felt252 = 'Value below minimum';
    pub const ABOVE_MAX: felt252 = 'Value above maximum';
    pub const NO_SHARES_EXIST: felt252 = 'No shares exist';
    pub const NO_FEES_TO_COLLECT: felt252 = 'No fees to collect';
    pub const REQUEST_PENDING: felt252 = 'Unlock request already pending';
    pub const REQUEST_EXPIRED: felt252 = 'Unlock request expired';
    pub const REQUEST_NOT_EXIST: felt252 = 'Unlock request does not exist';
    pub const REQUEST_NOT_READY: felt252 = 'Unlock request not ready';
    pub const TOO_MANY_REQUESTS: felt252 = 'Too many pending requests';
    pub const INVALID_REQUEST_INDEX: felt252 = 'Invalid request index';
}
