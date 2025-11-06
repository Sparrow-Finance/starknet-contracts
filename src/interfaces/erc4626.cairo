use starknet::ContractAddress;

/// ERC4626 Tokenized Vault Standard
/// https://eips.ethereum.org/EIPS/eip-4626
#[starknet::interface]
pub trait IERC4626<TContractState> {
    // ====================================
    // Metadata
    // ====================================
    
    /// Returns the address of the underlying token used for the Vault
    fn asset(self: @TContractState) -> ContractAddress;
    
    // ====================================
    // Deposit/Withdrawal Logic
    // ====================================
    
    /// Returns the total amount of the underlying asset managed by the Vault
    fn total_assets(self: @TContractState) -> u256;
    
    /// Converts asset amount to shares amount
    fn convert_to_shares(self: @TContractState, assets: u256) -> u256;
    
    /// Converts shares amount to asset amount
    fn convert_to_assets(self: @TContractState, shares: u256) -> u256;
    
    /// Maximum amount of assets that can be deposited
    fn max_deposit(self: @TContractState, receiver: ContractAddress) -> u256;
    
    /// Preview how many shares will be minted for assets
    fn preview_deposit(self: @TContractState, assets: u256) -> u256;
    
    /// Deposit assets and receive shares
    /// # Arguments
    /// * `assets` - Amount of underlying asset to deposit
    /// * `receiver` - Address to receive the shares
    /// # Returns
    /// Amount of shares minted
    fn deposit(ref self: TContractState, assets: u256, receiver: ContractAddress) -> u256;
    
    /// Maximum amount of shares that can be minted
    fn max_mint(self: @TContractState, receiver: ContractAddress) -> u256;
    
    /// Preview how many assets are needed to mint shares
    fn preview_mint(self: @TContractState, shares: u256) -> u256;
    
    /// Mint exact amount of shares
    /// # Arguments
    /// * `shares` - Amount of shares to mint
    /// * `receiver` - Address to receive the shares
    /// # Returns
    /// Amount of assets deposited
    fn mint(ref self: TContractState, shares: u256, receiver: ContractAddress) -> u256;
    
    /// Maximum amount of assets that can be withdrawn
    fn max_withdraw(self: @TContractState, owner: ContractAddress) -> u256;
    
    /// Preview how many shares will be burned for assets
    fn preview_withdraw(self: @TContractState, assets: u256) -> u256;
    
    /// Withdraw assets by burning shares
    /// # Arguments
    /// * `assets` - Amount of assets to withdraw
    /// * `receiver` - Address to receive the assets
    /// * `owner` - Address that owns the shares
    /// # Returns
    /// Amount of shares burned
    fn withdraw(
        ref self: TContractState, 
        assets: u256, 
        receiver: ContractAddress, 
        owner: ContractAddress
    ) -> u256;
    
    /// Maximum amount of shares that can be redeemed
    fn max_redeem(self: @TContractState, owner: ContractAddress) -> u256;
    
    /// Preview how many assets will be received for shares
    fn preview_redeem(self: @TContractState, shares: u256) -> u256;
    
    /// Redeem shares for assets
    /// # Arguments
    /// * `shares` - Amount of shares to redeem
    /// * `receiver` - Address to receive the assets
    /// * `owner` - Address that owns the shares
    /// # Returns
    /// Amount of assets withdrawn
    fn redeem(
        ref self: TContractState, 
        shares: u256, 
        receiver: ContractAddress, 
        owner: ContractAddress
    ) -> u256;
}
