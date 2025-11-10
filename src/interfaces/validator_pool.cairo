use starknet::ContractAddress;

#[starknet::interface]
pub trait IValidatorPool<TContractState> {
    /// Enter the delegation pool for the first time
    /// Call this when your contract has NEVER delegated to this pool before
    fn enter_delegation_pool(
        ref self: TContractState,
        reward_address: ContractAddress,
        amount: u128
    );
    
    /// Add more stake to existing delegation
    /// Call this after enter_delegation_pool() to add more STRK
    fn add_to_delegation_pool(
        ref self: TContractState,
        pool_member: ContractAddress,
        amount: u128
    ) -> u128;
    
    /// Request to exit pool (starts 21-day unbonding on mainnet).  -------> Request unlock
    /// Use this when reserve is depleted and need to unstake from validator
    fn exit_delegation_pool_intent(
        ref self: TContractState,
        amount: u128
    );
    
    /// Complete exit after unbonding period                        ---------> claim unlock
    /// Call this after waiting for the unbonding period to get STRK back
    fn exit_delegation_pool_action(
        ref self: TContractState,
        pool_member: ContractAddress
    ) -> u128;
    
    /// Claim accumulated rewards from the pool                     ---------> add rewards
    /// Can be called as often as needed (daily, weekly, etc.)
    fn claim_rewards(
        ref self: TContractState,
        pool_member: ContractAddress
    ) -> u128;
    
    /// Get information about your delegation (view function)
    /// Useful for monitoring and checking status before operations
    fn get_pool_member_info_v1(
        self: @TContractState,
        pool_member: ContractAddress
    ) -> Option<PoolMemberInfoV1>;
}

/// Pool member information structure
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct PoolMemberInfoV1 {
    pub reward_address: ContractAddress,
    pub amount: u128,
    pub unclaimed_rewards: u128,
    pub commission: u16,
    pub unpool_amount: u128,
    pub unpool_time: Option<Timestamp>,
}

/// Timestamp structure
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct Timestamp {
    pub seconds: u64,
}
