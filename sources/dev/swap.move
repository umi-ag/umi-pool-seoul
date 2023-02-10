#[test_only]
module umi_pool::dev_swap {
    use std::signer;
    use std::string;
    use std::debug;

    use aptos_framework::coin;

    use umi_pool::math;
    use umi_pool::coin_list;
    use umi_pool::decimal;
    use umi_pool::decimal::Decimal;

    // TODO: drop should be restricted to test only
    #[derive(Debug)]
    struct LiquidityPool<phantom X, phantom Y> has key {
        coin_x: coin::Coin<X>,
        coin_y: coin::Coin<Y>,
    }

    const MODULE_ADMIN: address = @umi_pool;
    const MINIMUM_LIQUIDITY: u128 = 1000;
    const BALANCE_MAX: u128 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF; // 2**112

    const ERR_ONLY_ADMIN: u64 = 0;
    const ERR_ALREADY_INITIALIZED: u64 = 1;
    const ERR_NOT_CREATOR: u64 = 2;
    const ERR_ALREADY_LOCKED: u64 = 3;
    const ERR_INSUFFICIENT_LIQUIDITY_MINTED: u64 = 4;
    const ERR_OVERFLOW: u64 = 5;
    const ERR_INSUFFICIENT_AMOUNT: u64 = 6;
    const ERR_INSUFFICIENT_LIQUIDITY: u64 = 7;
    const ERR_INVALID_AMOUNT: u64 = 8;
    const ERR_TOKENS_NOT_SORTED: u64 = 9;
    const ERR_INSUFFICIENT_LIQUIDITY_BURNED: u64 = 10;
    const ERR_INSUFFICIENT_coin_list_RED_AMOUNT: u64 = 11;
    const ERR_INSUFFICIENT_coin_list_BLUE_AMOUNT: u64 = 12;
    const ERR_INSUFFICIENT_OUTPUT_AMOUNT: u64 = 13;
    const ERR_INSUFFICIENT_INPUT_AMOUNT: u64 = 14;
    const ERR_K: u64 = 15;
    const ERR_X_NOT_REGISTERED: u64 = 16;
    const ERR_Y_NOT_REGISTERED: u64 = 16;


    #[test_only]
    struct CapContainer<phantom T> has key {
        mint_cap: coin::MintCapability<T>,
        burn_cap: coin::BurnCapability<T>,
        freeze_cap: coin::FreezeCapability<T>,
    }

    #[test_only]
    fun issue_token<Coin>(
        admin: &signer,
        to: &signer,
        name: string::String,
        symbol: string::String,
        total_supply: u64,
        decimals: u8,
        monitor_supply: bool,
    ) {
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<Coin>(
            admin,
            name,
            symbol,
            decimals,
            monitor_supply,
        );

        coin::register<Coin>(admin);
        coin::register<Coin>(to);

        let a = coin::mint(total_supply, &mint_cap);
        coin::deposit(signer::address_of(to), a);
        move_to<CapContainer<Coin>>(admin, CapContainer{ mint_cap, burn_cap, freeze_cap });
    }

    #[test(admin = @umi_pool, token_owner = @0x02, alice = @0x10)]
    fun test_transfer_to_alice(
        admin: signer,
        token_owner: signer,
        alice: signer,
    ) {
        use aptos_framework::aptos_account;
        use aptos_framework::genesis;
        genesis::setup();
        aptos_account::create_account(signer::address_of(&admin));
        let total_supply: u64 = (math::expand_to_decimals(1000000, 8) as u64);

        issue_token<coin_list::RED>(
            &admin,
            &token_owner,
            string::utf8(b"redcoin"),
            string::utf8(b"RED"),
            total_supply,
            8,
            true
        );

        let _bal = coin::balance<coin_list::RED>(signer::address_of(&token_owner));

        coin::register<coin_list::RED>(&alice);
        coin::transfer<coin_list::RED>(
            &token_owner,
            signer::address_of(&alice),
            math::expand_to_decimals(1, 6),
        );
        let _bal = coin::balance<coin_list::RED>(signer::address_of(&alice));

        let _bal = coin::balance<coin_list::RED>(signer::address_of(&token_owner));
    }

    fun check_coin_store<X>(to: &signer)
    {
        if (!coin::is_account_registered<X>(signer::address_of(to))) {
            coin::register<X>(to);
        };
    }

    fun register_pool<X, Y>(admin: &signer)
    {
        let pool = LiquidityPool<X, Y> {
            coin_x: coin::zero<X>(),
            coin_y: coin::zero<Y>(),
        };
        move_to<LiquidityPool<X, Y>>(admin, pool);
    }

    fun add_liquidity<X, Y>(
        sender: &signer,
        coin_x_amount: u64,
        coin_y_amount: u64,
    )
    acquires LiquidityPool
    {
        let (a_x, a_y) = (coin_x_amount, coin_y_amount);

        deposit_x<X, Y>(coin::withdraw<X>(sender, a_x));
        deposit_y<X, Y>(coin::withdraw<Y>(sender, a_y));
    }

    fun remove_liquidity<X, Y>(
        to: &signer,
        coin_x_amount: u64,
        coin_y_amount: u64,
    )
    acquires LiquidityPool
    {
        let pool = borrow_global_mut<LiquidityPool<X, Y>>(MODULE_ADMIN);
        withdraw_x(pool, to, coin_x_amount);
        withdraw_y(pool, to, coin_y_amount);
    }

    fun deposit_x<X, Y>(amount: coin::Coin<X>)
    acquires LiquidityPool
    {
        let pool = borrow_global_mut<LiquidityPool<X, Y>>(MODULE_ADMIN);
        coin::merge(&mut pool.coin_x, amount);
    }

    fun deposit_y<X, Y>(amount: coin::Coin<Y>)
    acquires LiquidityPool
    {
        let pool = borrow_global_mut<LiquidityPool<X, Y>>(MODULE_ADMIN);
        coin::merge(&mut pool.coin_y, amount);
    }

    fun extract_x<X, Y>(pool: &mut LiquidityPool<X, Y>, amount: u64): coin::Coin<X>
    {
        assert!(coin::value<X>(&pool.coin_x) > amount, ERR_INSUFFICIENT_AMOUNT);
        coin::extract(&mut pool.coin_x, amount)
    }

    fun extract_y<X, Y>(pool: &mut LiquidityPool<X, Y>, amount: u64): coin::Coin<Y>
    {
        assert!(coin::value<Y>(&pool.coin_y) > amount, ERR_INSUFFICIENT_AMOUNT);
        coin::extract(&mut pool.coin_y, amount)
    }

    fun withdraw_x<X, Y>(pool: &mut LiquidityPool<X, Y>, to: &signer, amount: u64)
    {
        check_coin_store<X>(to);
        let coin_amount = extract_x<X, Y>(pool, amount);
        coin::deposit<X>(signer::address_of(to), coin_amount);
    }

    fun withdraw_y<X, Y>(pool: &mut LiquidityPool<X, Y>, to: &signer, amount: u64)
    {
        check_coin_store<Y>(to);
        let coin_amount = extract_y<X, Y>(pool, amount);
        coin::deposit<Y>(signer::address_of(to), coin_amount);
    }

    fun get_pool_rate<X, Y>(): Decimal
    acquires LiquidityPool
    {
        let pool = borrow_global<LiquidityPool<X, Y>>(MODULE_ADMIN);
        let x_pooled = decimal::from_u64(coin::value(&pool.coin_x));
        let y_pooled = decimal::from_u64(coin::value(&pool.coin_y));
        decimal::div(&x_pooled, &y_pooled)
    }

    #[test(admin = @umi_pool, token_owner = @0x02)]
    fun test_move_pool(admin: signer, token_owner: signer)
    {
        use aptos_framework::aptos_account;
        use aptos_framework::genesis;
        genesis::setup();
        aptos_account::create_account(signer::address_of(&admin));
        let total_supply: u64 = (math::expand_to_decimals(1, 12+6) as u64);

        issue_token<coin_list::RED>( &admin, &token_owner, string::utf8(b"redcoin"), string::utf8(b"RED"), total_supply, 8, true);
        issue_token<coin_list::BLUE>( &admin, &token_owner, string::utf8(b"bluecoin"), string::utf8(b"BLUE"), total_supply, 8, true);

        coin::balance<coin_list::RED>(signer::address_of(&token_owner));
        coin::balance<coin_list::BLUE>(signer::address_of(&token_owner));

        coin::transfer<coin_list::RED>( &token_owner, signer::address_of(&admin), math::expand_to_decimals(1, 6));
        coin::transfer<coin_list::BLUE>( &token_owner, signer::address_of(&admin), math::expand_to_decimals(1, 6));

        let pool = LiquidityPool<coin_list::RED, coin_list::BLUE> {
            coin_x: coin::zero<coin_list::RED>(),
            coin_y: coin::zero<coin_list::BLUE>(),
        };
        move_to<LiquidityPool<coin_list::RED, coin_list::BLUE>>(&admin, pool);
    }

    #[test(admin = @umi_pool, token_owner = @0x02)]
    fun test_add_liqudity(admin: signer, token_owner: signer)
    acquires LiquidityPool
    {
        use aptos_framework::aptos_account;
        use aptos_framework::genesis;
        genesis::setup();
        aptos_account::create_account(signer::address_of(&admin));
        let total_supply: u64 = (math::expand_to_decimals(1, 12+6) as u64);

        issue_token<coin_list::RED>( &admin, &token_owner, string::utf8(b"redcoin"), string::utf8(b"RED"), total_supply, 8, true);
        issue_token<coin_list::BLUE>( &admin, &token_owner, string::utf8(b"bluecoin"), string::utf8(b"BLUE"), total_supply, 8, true);

        let coin_x_amount = math::expand_to_decimals(2, 6);
        let coin_y_amount = math::expand_to_decimals(3, 8);

        coin::transfer<coin_list::RED>( &token_owner, signer::address_of(&admin), coin_x_amount);
        coin::transfer<coin_list::BLUE>( &token_owner, signer::address_of(&admin), coin_y_amount);

        register_pool<coin_list::RED, coin_list::BLUE>(&admin);
        add_liquidity<coin_list::RED, coin_list::BLUE>(&admin, coin_x_amount, coin_y_amount);
        let pool = borrow_global<LiquidityPool<coin_list::RED, coin_list::BLUE>>(MODULE_ADMIN);

        assert!(coin::value(&pool.coin_x) == math::expand_to_decimals(2, 6), 0);
        assert!(coin::value(&pool.coin_y) == math::expand_to_decimals(3, 8), 1);
    }

    #[test(admin = @umi_pool, token_owner = @0x02)]
    fun test_remove_liqudity(admin: signer, token_owner: signer)
    acquires LiquidityPool
    {
        use aptos_framework::aptos_account;
        use aptos_framework::genesis;
        genesis::setup();
        aptos_account::create_account(signer::address_of(&admin));
        let total_supply: u64 = (math::expand_to_decimals(1, 12+6) as u64);

        issue_token<coin_list::RED>( &admin, &token_owner, string::utf8(b"redcoin"), string::utf8(b"RED"), total_supply, 8, true);
        issue_token<coin_list::BLUE>( &admin, &token_owner, string::utf8(b"bluecoin"), string::utf8(b"BLUE"), total_supply, 8, true);

        let debt_x_amount = math::expand_to_decimals(2, 6);
        let debt_y_amount = math::expand_to_decimals(3, 8);
        let deposit_x_amount = math::expand_to_decimals(1, 6);
        let deposit_y_amount = math::expand_to_decimals(2, 6);
        let withdraw_x_amount = math::expand_to_decimals(5, 5);
        let withdraw_y_amount = math::expand_to_decimals(1, 6);

        coin::transfer<coin_list::RED>( &token_owner, signer::address_of(&admin), debt_x_amount);
        coin::transfer<coin_list::BLUE>( &token_owner, signer::address_of(&admin), debt_y_amount);

        register_pool<coin_list::RED, coin_list::BLUE>(&admin);
        add_liquidity<coin_list::RED, coin_list::BLUE>(&admin, deposit_x_amount, deposit_y_amount);
        let pool_rate = get_pool_rate<coin_list::RED, coin_list::BLUE>();
        debug::print(&pool_rate);
        let pool = borrow_global<LiquidityPool<coin_list::RED, coin_list::BLUE>>(signer::address_of(&admin));
        assert!(coin::value(&pool.coin_x) == deposit_x_amount, 0);
        assert!(coin::value(&pool.coin_y) == deposit_y_amount, 1);

        remove_liquidity<coin_list::RED, coin_list::BLUE>(&admin, withdraw_x_amount, withdraw_y_amount);
        let pool_rate = get_pool_rate<coin_list::RED, coin_list::BLUE>();
        debug::print(&pool_rate);
        let pool = borrow_global<LiquidityPool<coin_list::RED, coin_list::BLUE>>(MODULE_ADMIN);

        assert!(coin::value(&pool.coin_x) == deposit_x_amount - withdraw_x_amount, 0);
        assert!(coin::value(&pool.coin_y) == deposit_y_amount - withdraw_y_amount, 1);

        assert!(coin::balance<coin_list::RED>(signer::address_of(&admin)) == debt_x_amount - deposit_x_amount + withdraw_x_amount, 2);
        assert!(coin::balance<coin_list::BLUE>(signer::address_of(&admin)) == debt_y_amount - deposit_y_amount + withdraw_y_amount, 3);
    }
}