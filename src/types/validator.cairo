use starknet::ContractAddress;

/// Information about a validator delegation pool
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct ValidatorInfo {
    /// Address of the validator's delegation pool contract
    pub pool_address: ContractAddress,
    /// Whether this validator is active for new delegations
    pub is_active: bool,
    /// Total STRK delegated to this validator
    pub total_delegated: u256,
    /// Pending exit amount from this validator
    pub pending_exit: u256,
}
