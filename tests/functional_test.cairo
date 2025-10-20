use starknet::{ContractAddress, get_contract_address};
use snforge_std::{
    CheatSpan, load, cheat_caller_address, start_cheat_caller_address, stop_cheat_caller_address,
    start_cheat_block_timestamp, stop_cheat_block_timestamp, declare, DeclareResultTrait,
};
use openzeppelin::token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use openzeppelin::access::ownable::interface::{
    OwnableTwoStepABIDispatcher, OwnableTwoStepABIDispatcherTrait,
};
use openzeppelin::upgrades::interface::{IUpgradeableDispatcher, IUpgradeableDispatcherTrait};

use sp_strk::sp_strk::spSTRK;
use sp_strk::interfaces::sp_strk::{IspSTRK, IspSTRKDispatcher, IspSTRKDispatcherTrait};
use sp_strk::types::init::InitParams;
use sp_strk::mock::upgrade::{INewspSTRKDispatcher, INewspSTRKDispatcherTrait};
use crate::fixtures::{deploy_contract, deploy_mock_token};
use crate::utils::{ether, erc20, serialize, deserialize};

fn init() -> (IspSTRKDispatcher, ERC20ABIDispatcher) {
    let owner = get_contract_address();
    let strk_token = deploy_mock_token(owner);
    let sp_strk = deploy_contract(
        InitParams {
            owner,
            strk_token: strk_token.contract_address,
            dao_fee_basis_points: 500,
            dev_fee_basis_points: 300,
            min_stake_amount: 10000000000000000, //0.01 STRK
            unlock_period: 60, //60 sec
            claim_window: 604800 //7 days
        },
    );

    (sp_strk, strk_token)
}

#[test]
fn test_init() {
    let (spStark, _) = init();

    let token = erc20(spStark.contract_address);

    assert_eq!(token.name(), "Sparrow Staked STRK");
    assert_eq!(token.symbol(), "spSTRK");
    assert_eq!(token.decimals(), 18);
    assert_eq!(token.total_supply(), 0);

    let ownable = OwnableTwoStepABIDispatcher { contract_address: spStark.contract_address };
    assert_eq!(ownable.owner(), get_contract_address());
}

#[test]
#[should_panic(expected: ('Fees too high',))]
fn test_high_fee() {
    let mut state = spSTRK::contract_state_for_testing();
    state.set_fees(500, 600);
}

#[test]
#[should_panic(expected: ('Value below minimum',))]
fn test_low_unlock_period() {
    let mut state = spSTRK::contract_state_for_testing();
    state.set_unlock_period(30);
}

#[test]
#[should_panic(expected: ('Value above maximum',))]
fn test_high_unlock_period() {
    let mut state = spSTRK::contract_state_for_testing();
    state.set_unlock_period(2592001);
}

#[test]
#[should_panic(expected: ('Value below minimum',))]
fn test_low_claim_window() {
    let mut state = spSTRK::contract_state_for_testing();
    state.set_claim_window(3500);
}

#[test]
#[should_panic(expected: ('Value above maximum',))]
fn test_high_claim_window() {
    let mut state = spSTRK::contract_state_for_testing();
    state.set_claim_window(2592001);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_owner() {
    let (sp_stark, _) = init();

    let fake_owner: ContractAddress = 1.try_into().unwrap();
    cheat_caller_address(sp_stark.contract_address, fake_owner, CheatSpan::TargetCalls(1));
    sp_stark.set_fees(200, 200);
}

#[test]
#[should_panic(expected: ('Pausable: paused',))]
fn test_paused() {
    let (sp_stark, _) = init();

    sp_stark.pause();
    sp_stark.stake(100000000000000000, 10000000000000000);
}

#[test]
#[should_panic(expected: ('Below minimum stake',))]
fn test_below_minimum_stake() {
    let (sp_stark, _) = init();

    sp_stark.stake(1000000000000000, 10000000000000000);
}

#[test]
#[should_panic(expected: ('First deposit too low',))]
fn test_low_first_stake() {
    let sp_stark = deploy_contract(
        InitParams {
            owner: get_contract_address(),
            strk_token: deploy_mock_token(get_contract_address()).contract_address,
            dao_fee_basis_points: 500,
            dev_fee_basis_points: 300,
            min_stake_amount: 100000,
            unlock_period: 60, //60 sec
            claim_window: 604800 //7 days
        },
    );

    sp_stark.stake(100000, 100000);
}

#[test]
#[should_panic(expected: ('Slippage exceeded',))]
fn test_slippage_stake() {
    let (sp_stark, _) = init();

    sp_stark.stake(100000000000000000, 1000000000000000000);
}

#[test]
fn test_deposit() {
    let (sp_stark, strk_token) = init();
    let stake_amount = ether(10);

    strk_token.approve(sp_stark.contract_address, stake_amount);
    sp_stark.stake(stake_amount, stake_amount);

    let sp_stark_token = erc20(sp_stark.contract_address);
    assert_eq!(sp_stark_token.balance_of(get_contract_address()), stake_amount);
    assert_eq!(sp_stark_token.total_supply(), stake_amount);
}

#[test]
fn test_multiple_deposit() {
    let (sp_stark, strk_token) = init();

    let (user1, user2): (ContractAddress, ContractAddress) = (1.try_into().unwrap(), 2.try_into().unwrap());
    let (stake_amount_u1, stake_amount_u2) = (ether(10), ether(5));

    //transfer STRK to users
    strk_token.transfer(user1, stake_amount_u1);
    strk_token.transfer(user2, stake_amount_u2);

    //approve and stake for user1
    start_cheat_caller_address(strk_token.contract_address, user1);
    strk_token.approve(sp_stark.contract_address, stake_amount_u1);
    stop_cheat_caller_address(strk_token.contract_address);

    start_cheat_caller_address(sp_stark.contract_address, user1);
    sp_stark.stake(stake_amount_u1, stake_amount_u1);
    stop_cheat_caller_address(sp_stark.contract_address);

    //approve and stake for user2
    start_cheat_caller_address(strk_token.contract_address, user2);
    strk_token.approve(sp_stark.contract_address, stake_amount_u2);
    stop_cheat_caller_address(strk_token.contract_address);

    start_cheat_caller_address(sp_stark.contract_address, user2);
    sp_stark.stake(stake_amount_u2, stake_amount_u2);
    stop_cheat_caller_address(sp_stark.contract_address);

    //check balances and total pooled STRK
    let sp_stark_token = erc20(sp_stark.contract_address);
    assert_eq!(sp_stark_token.balance_of(user1), stake_amount_u1);
    assert_eq!(sp_stark_token.balance_of(user2), stake_amount_u2);
    assert_eq!(sp_stark_token.total_supply(), stake_amount_u1 + stake_amount_u2);

    let total_pooled_STRK = load(sp_stark.contract_address, selector!("total_pooled_STRK"), 2);
    assert_eq!(total_pooled_STRK, serialize(@(stake_amount_u1 + stake_amount_u2)));
}

#[test]
fn test_ratio_change_deposit() {
    let (sp_stark, strk_token) = init();

    let (user1, user2): (ContractAddress, ContractAddress) = (1.try_into().unwrap(), 2.try_into().unwrap());
    let (stake_amount_u1, stake_amount_u2) = (ether(10), ether(10));

    strk_token.transfer(user1, stake_amount_u1);
    strk_token.transfer(user2, stake_amount_u2);

    //approve and stake for user1
    start_cheat_caller_address(strk_token.contract_address, user1);
    strk_token.approve(sp_stark.contract_address, stake_amount_u1);
    stop_cheat_caller_address(strk_token.contract_address);

    start_cheat_caller_address(sp_stark.contract_address, user1);
    sp_stark.stake(stake_amount_u1, stake_amount_u1);
    stop_cheat_caller_address(sp_stark.contract_address);

    // add rewards to the contract to change the spSTRK/STRK ratio
    let rewards = ether(10);
    strk_token.approve(sp_stark.contract_address, rewards);
    sp_stark.add_rewards(rewards);

    let value_after_fees = 9200000000000000000; //10 - (0.5 + 0.3)% 9.2
    let (
        total_pooled_STRK,
        total_supply,
        exchange_rate,
        _,
        accumulated_dao_fees,
        accumulated_dev_fees,
        _,
        _,
    ) =
        sp_stark
        .get_stats();
    assert_eq!(total_pooled_STRK, stake_amount_u1 + value_after_fees);
    assert_eq!(total_supply, stake_amount_u1);
    assert_eq!(accumulated_dao_fees, 500000000000000000); //0.5% of 10 STRK
    assert_eq!(accumulated_dev_fees, 300000000000000000); //0.3% of 10 STRK
    assert_eq!(exchange_rate, 1920000000000000000); // (10 + 9.2) / 10 = 1.92

    let sp_strk_from_strk = sp_stark.preview_stake(ether(1));
    assert_eq!(
        sp_strk_from_strk, 520833333333333333,
    ); // 1 strk = 1 / 1.92 = 0.520833333333333333 spSTRK
    let strk_from_sp_strk = sp_stark.preview_unlock(ether(1));
    assert_eq!(strk_from_sp_strk, 1920000000000000000); // 1 spSTRK = 1.92 STRK

    let user2_expected = 5208333333333333333; //10 * (10 / 19.2)
    //approve and stake for user2
    start_cheat_caller_address(strk_token.contract_address, user2);
    strk_token.approve(sp_stark.contract_address, stake_amount_u2);
    stop_cheat_caller_address(strk_token.contract_address);

    start_cheat_caller_address(sp_stark.contract_address, user2);
    sp_stark.stake(stake_amount_u2, user2_expected);
    stop_cheat_caller_address(sp_stark.contract_address);

    let sp_stark_token = erc20(sp_stark.contract_address);
    assert_eq!(sp_stark_token.balance_of(user1), stake_amount_u1);

    assert_eq!(sp_stark_token.balance_of(user2), user2_expected);
    assert_eq!(sp_stark_token.total_supply(), stake_amount_u1 + user2_expected);
}

#[test]
#[should_panic(expected: ('No shares exist',))]
fn test_unlock_without_shares() {
    let (sp_stark, _) = init();
    sp_stark.request_unlock(ether(1), ether(1));
}

#[test]
#[should_panic(expected: ('Insufficient balance',))]
fn test_unlock_without_sp_stark() {
    let (sp_stark, strk) = init();

    strk.approve(sp_stark.contract_address, ether(1));
    sp_stark.stake(ether(1), ether(1));

    let user: ContractAddress = 1.try_into().unwrap();
    cheat_caller_address(sp_stark.contract_address, user, CheatSpan::TargetCalls(1));
    sp_stark.request_unlock(ether(1), ether(1));
}

#[test]
fn test_simple_unlock() {
    let (sp_stark, strk) = init();
    let sp_strk_token = erc20(sp_stark.contract_address);

    let amount = ether(1);
    let user = get_contract_address();

    strk.approve(sp_stark.contract_address, amount);
    sp_stark.stake(amount, amount);
    assert_eq!(sp_strk_token.balance_of(user), amount);

    sp_stark.request_unlock(amount, amount);
    assert_eq!(sp_strk_token.balance_of(user), 0);

    let (request, _, is_ready, is_expired) = sp_stark.get_unlock_request(user);
    assert_eq!(request.sp_strk_amount, amount);
    assert_eq!(is_ready, false);
    assert_eq!(is_expired, false);
}

#[test]
fn test_unlock_status() {
    let (sp_stark, strk) = init();

    let amount = ether(1);
    let user = get_contract_address();

    strk.approve(sp_stark.contract_address, amount);
    sp_stark.stake(amount, amount);

    let timestamp: u64 = 1000000;
    start_cheat_block_timestamp(sp_stark.contract_address, timestamp);
    sp_stark.request_unlock(amount, amount);

    let unlock_period: u64 = deserialize::<
        u64,
    >(load(sp_stark.contract_address, selector!("unlock_period"), 1).span());
    let claim_window: u64 = deserialize::<
        u64,
    >(load(sp_stark.contract_address, selector!("claim_window"), 1).span());

    //not ready nor expired
    let (request, _, is_ready_1, is_expired_1) = sp_stark.get_unlock_request(user);
    assert_eq!(request.unlock_time, timestamp + unlock_period);
    assert_eq!(request.expiry_time, timestamp + unlock_period + claim_window);
    assert_eq!(is_ready_1, false);
    assert_eq!(is_expired_1, false);
    stop_cheat_block_timestamp(sp_stark.contract_address);

    //should be ready but not expired
    start_cheat_block_timestamp(sp_stark.contract_address, timestamp + unlock_period + 1);
    let (_, _, is_ready_2, is_expired_2) = sp_stark.get_unlock_request(user);
    assert_eq!(is_ready_2, true);
    assert_eq!(is_expired_2, false);
    stop_cheat_block_timestamp(sp_stark.contract_address);

    //should be ready and expired
    start_cheat_block_timestamp(
        sp_stark.contract_address, timestamp + unlock_period + claim_window + 1,
    );
    let (_, _, is_ready_3, is_expired_3) = sp_stark.get_unlock_request(user);
    assert_eq!(is_ready_3, true);
    assert_eq!(is_expired_3, true);
    stop_cheat_block_timestamp(sp_stark.contract_address);
}

#[test]
#[should_panic(expected: ('Unlock request already pending',))]
fn test_unlock_duplicate() {
    let (sp_stark, strk) = init();

    let amount = ether(1);

    strk.approve(sp_stark.contract_address, amount + amount);
    sp_stark.stake(amount + amount, amount + amount);

    sp_stark.request_unlock(amount, amount);
    sp_stark.request_unlock(amount, amount);
}

#[test]
#[should_panic(expected: ('Unlock request does not exist',))]
fn test_claim_unlock_with_no_req() {
    let (sp_stark, _) = init();
    sp_stark.claim_unlock();
}

#[test]
#[should_panic(expected: ('Unlock request not ready',))]
fn test_claim_unlock_when_not_ready() {
    let (sp_stark, strk) = init();

    let amount = ether(1);

    strk.approve(sp_stark.contract_address, amount);
    sp_stark.stake(amount, amount);

    sp_stark.request_unlock(amount, amount);
    sp_stark.claim_unlock();
}

#[test]
#[should_panic(expected: ('Unlock request expired',))]
fn test_claim_unlock_when_expired() {
    let (sp_stark, strk) = init();

    let amount = ether(1);

    strk.approve(sp_stark.contract_address, amount);
    sp_stark.stake(amount, amount);

    sp_stark.request_unlock(amount, amount);

    let unlock_period: u64 = deserialize::<
        u64,
    >(load(sp_stark.contract_address, selector!("unlock_period"), 1).span());
    let claim_window: u64 = deserialize::<
        u64,
    >(load(sp_stark.contract_address, selector!("claim_window"), 1).span());

    start_cheat_block_timestamp(sp_stark.contract_address, unlock_period + claim_window + 1);
    sp_stark.claim_unlock();
    stop_cheat_block_timestamp(sp_stark.contract_address);
}

#[test]
fn test_successful_claim_unlock() {
    let (sp_stark, strk) = init();
    let sp_strk_token = erc20(sp_stark.contract_address);

    let user = get_contract_address();
    let amount = ether(1);

    let initial_balance = strk.balance_of(user);
    strk.approve(sp_stark.contract_address, amount);
    sp_stark.stake(amount, amount);
    assert_eq!(strk.balance_of(user), initial_balance - amount);

    sp_stark.request_unlock(amount, amount);
    assert_eq!(sp_strk_token.balance_of(user), 0);
    //total supply should not change on unlock request
    assert_eq!(sp_strk_token.total_supply(), amount);

    let unlock_period: u64 = deserialize::<
        u64,
    >(load(sp_stark.contract_address, selector!("unlock_period"), 1).span());
    start_cheat_block_timestamp(sp_stark.contract_address, unlock_period + 1);
    sp_stark.claim_unlock();
    stop_cheat_block_timestamp(sp_stark.contract_address);

    assert_eq!(sp_strk_token.balance_of(user), 0);
    assert_eq!(sp_strk_token.total_supply(), 0);

    assert_eq!(strk.balance_of(get_contract_address()), initial_balance);
}

#[test]
#[should_panic(expected: ('Unlock request does not exist',))]
fn test_cancel_unlock_with_no_req() {
    let (sp_stark, _) = init();
    sp_stark.cancel_unlock();
}

#[test]
fn test_successful_cancel_unlock() {
    let (sp_stark, strk) = init();
    let sp_stark_token = erc20(sp_stark.contract_address);

    let amount = ether(1);
    let user = get_contract_address();

    strk.approve(sp_stark.contract_address, amount);
    sp_stark.stake(amount, amount);

    let initial_sp_strk_balance = sp_stark_token.balance_of(user);
    assert_eq!(initial_sp_strk_balance, amount);
    assert_eq!(sp_stark_token.total_supply(), amount);

    sp_stark.request_unlock(amount, amount);
    assert_eq!(sp_stark_token.balance_of(user), 0);
    assert_eq!(sp_stark_token.total_supply(), amount);

    sp_stark.cancel_unlock();
    assert_eq!(sp_stark_token.balance_of(user), initial_sp_strk_balance);
    assert_eq!(sp_stark_token.total_supply(), amount);
}

#[test]
fn test_successful_deposit() {
    let (sp_stark, strk) = init();

    let contract_initial_balance = strk.balance_of(sp_stark.contract_address);

    let amount = ether(1);
    strk.approve(sp_stark.contract_address, amount);
    sp_stark.deposit(amount);

    assert_eq!(strk.balance_of(sp_stark.contract_address), contract_initial_balance + amount);
}

#[test]
#[should_panic(expected: ('Insufficient STRK balance',))]
fn test_withdraw_low_funds() {
    let (sp_stark, _) = init();
    sp_stark.withdraw(ether(1));
}

#[test]
fn test_successful_withdraw() {
    let (sp_stark, strk) = init();

    let amount = ether(1);
    let user = get_contract_address();
    let user_init_balance = strk.balance_of(user);

    strk.approve(sp_stark.contract_address, amount);
    sp_stark.stake(amount, amount);
    assert_eq!(strk.balance_of(user), user_init_balance - amount);
    assert_eq!(strk.balance_of(sp_stark.contract_address), amount);

    sp_stark.withdraw(amount);
    assert_eq!(strk.balance_of(user), user_init_balance);
    assert_eq!(strk.balance_of(sp_stark.contract_address), 0);
}

#[test]
fn test_fee_claiming() {
    let (sp_stark, strk) = init();

    let amount = ether(10);
    let user = get_contract_address();

    strk.approve(sp_stark.contract_address, amount);

    sp_stark.add_rewards(amount);
    let (_, _, _, _, accumulated_dao_fees, accumulated_dev_fees, _, _) = sp_stark.get_stats();

    let balance_before = strk.balance_of(user);

    assert_eq!(accumulated_dao_fees, 500000000000000000); //0.5% of 10 STRK
    assert_eq!(accumulated_dev_fees, 300000000000000000); //0.3% of 10 STRK

    sp_stark.collect_dao_fees();
    assert_eq!(strk.balance_of(user), balance_before + accumulated_dao_fees);

    sp_stark.collect_dev_fees();
    assert_eq!(strk.balance_of(user), balance_before + accumulated_dao_fees + accumulated_dev_fees);

    let (_, _, _, _, accumulated_dao_fees, accumulated_dev_fees, _, _) = sp_stark.get_stats();

    assert_eq!(accumulated_dao_fees, 0);
    assert_eq!(accumulated_dev_fees, 0);
}

#[test]
fn test_upgrade() {
    let (sp_stark, _) = init();
    let upgradeable = IUpgradeableDispatcher { contract_address: sp_stark.contract_address };

    let new_contract_class = declare("NewspSTRK").unwrap().contract_class();
    upgradeable.upgrade(*new_contract_class.class_hash);

    let new_sp_stark = INewspSTRKDispatcher { contract_address: sp_stark.contract_address };
    assert_eq!(new_sp_stark.new_function(), 10);
}
