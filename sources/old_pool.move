module umi_pool::old_pool {
    use std::signer;
    use std::string;

    use aptos_framework::coin;

    use umi_pool::decimal;
    use umi_pool::decimal::Decimal;
    use umi_pool::asset;
    use umi_pool::asset::Asset;
    use umi_pool::coin_info;
    use umi_pool::coin_info::{CoinInfo};

    #[test_only] use std::debug;

    #[test_only] use umi_pool::math;
    #[test_only] use umi_pool::coin_list;

    const MODULE_ADMIN: address = @umi_pool;
    // const UMI_TREASUREY: address = @umi_treasury;
    const UMI_TREASUREY: address = @umi_pool;
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
    const ERR_FEE_IS_MINUS: u64 = 20;
    const ERR_INPUT_AMOUTN_MUST_BE_POSITIVE: u64 = 30;
    const ERR_OUTPUT_AMOUTN_MUST_BE_POSITIVE: u64 = 31;
    const ERR_INPUT_AMOUNT: u64 = 423;
    const ERR_UNKNOWN_COIN_IN: u64 = 424;


    // quote
    struct Price<phantom X, phantom Y> has key, copy, drop {
        price: Decimal,
    }

    public fun new_price<X, Y>(price: &Decimal): Price<X, Y>
    {
        Price<X, Y> {
            price: *price
        }
    }
    public entry fun get_price<X, Y>(quote: &Price<X, Y>): Decimal
    {
        quote.price
    }

    public entry fun register_price<X, Y>(account: &signer)
    {
        let account_addr = signer::address_of(account);
        if (!exists<Price<X, Y>>(account_addr)) {
            let price = decimal::new(1, 0, true);
            move_to(account, Price<X, Y> { price });
        };
    }

    public entry fun set_price<X, Y>(account: &signer, value: u64, decimals: u8)
    acquires Price
    {
        let price = decimal::new((value as u128), decimals, false);
        let account_addr = signer::address_of(account);
        let price_quote = borrow_global_mut<Price<X, Y>>(account_addr);
        price_quote.price = price;
    }

    #[test(account = @0x1, coin_addr = @0x2)]
    fun test_set_price(account: signer)
    acquires Price {
        use umi_pool::coin_list;

        let addr = signer::address_of(&account);
        aptos_framework::account::create_account_for_test(addr);

        register_price<coin_list::RED, coin_list::BLUE>(&account);
        set_price<coin_list::RED, coin_list::BLUE>(&account, 8901, 2);
    }

    // TODO: drop should be restricted to test only
    #[derive(Debug)]
    struct LiquidityPool<phantom X, phantom Y> has key {
        x_reserve: coin::Coin<X>,
        y_reserve: coin::Coin<Y>,
        x_decimals: u8,
        y_decimals: u8,
        config: PoolConfig,
    }

    #[derive(Debug)]
    struct TradeContext has drop {
        coin_in_pool: Decimal,
        coin_out_pool: Decimal,
        coin_in_swap_amout: Decimal,
        price_oracle: Decimal, // coin_in / coin_out
    }

    #[derive(Debug)]
    struct PoolConfig has key, store, drop {
        fee_rate: Decimal,
        slack_mu: Decimal,
        greedy_alpha: Decimal,
    }

    #[derive(Debug)]
    struct CurveDeal has drop {
        delta_coin_in: Decimal,
        delta_coin_out: Decimal,
        coin_in_fee: Decimal,
        coin_out_fee: Decimal,
        price: Decimal,
    }

    #[derive(Debug)]
    struct TradeDeal<phantom X, phantom Y> has drop {
        input_coin_x: Asset<X>,
        output_coin_y: Asset<Y>,
        coin_x_fee: Asset<X>,
        coin_y_fee: Asset<Y>,
        price: Price<X, Y>,
    }

    fun curve(
        trade_context: &TradeContext,
        pool_config: &PoolConfig,
    ): CurveDeal {
        let fee_rate = pool_config.fee_rate;
        let slack_mu = pool_config.slack_mu;
        let greedy_alpha = pool_config.greedy_alpha;
        let x_before_swap = trade_context.coin_in_pool;
        let y_before_swap = trade_context.coin_out_pool;
        let delta_x_and_fee = trade_context.coin_in_swap_amout;
        let price_oracle = trade_context.price_oracle;
        assert!(decimal::gt(&delta_x_and_fee, &decimal::zero()), ERR_INPUT_AMOUNT);

        let x_fee = decimal::max(
            &decimal::mul(&delta_x_and_fee, &fee_rate),
            &decimal::zero()
        );
        let delta_x = decimal::sub(&delta_x_and_fee, &x_fee);

        let x_after_swap = decimal::add(&x_before_swap, &delta_x);

        let price_pool = decimal::div(&x_before_swap, &y_before_swap);

        let price_min = decimal::min(&price_oracle, &price_pool);
        let price_max = decimal::max(&price_oracle, &price_pool);

        let concentration = decimal::div(&decimal::div(&price_min, &price_max), &greedy_alpha);
        let price_bid = decimal::mul(&price_pool, &concentration);
        let price_ask = decimal::div(&price_pool, &concentration);

        let y_bid = decimal::sub(&y_before_swap, &decimal::div(&delta_x, &price_bid));
        let y_ask = decimal::sub(&y_before_swap, &decimal::div(&delta_x, &price_ask));
        // REMARK: x_before_swap x y_before_swap > MAX_u128
        let y_uni = decimal::mul(
            &decimal::div(&x_before_swap, &x_after_swap),
            &decimal::div(&y_before_swap, &slack_mu),
        );

        let y_after_swap = decimal::max(&decimal::max(&y_bid, &y_ask), &y_uni);

        let delta_y = decimal::sub(&y_after_swap, &y_before_swap);

        let price_deal = decimal::mul(&decimal::new(1, 0, true), &decimal::div(&delta_x, &delta_y));

        let deal = CurveDeal {
            delta_coin_in: delta_x,
            delta_coin_out: delta_y,
            coin_in_fee: x_fee,
            coin_out_fee: decimal::zero(),
            price: price_deal
        };
        deal
    }

    fun execute_deal_direct<X, Y>(deal: &TradeDeal<X, Y>, alice: &signer, treasury: address)
    : (coin::Coin<X>, coin::Coin<Y>)
    acquires LiquidityPool
    {
        let pool = borrow_global_mut<LiquidityPool<X, Y>>(MODULE_ADMIN);

        // Allie deposits coinX.
        {
            let input_amount = asset::to_u64(deal.input_coin_x);
            deposit_x<X, Y>(pool, coin::withdraw<X>(alice, input_amount));
        };

        // Allie withdraws coinY.
        {
            let output_amount = asset::to_u64(deal.output_coin_y);
            withdraw_y<X, Y>(pool, signer::address_of(alice), output_amount);
        };

        // Allie pays coinX fee.
        {
            let amount = asset::to_u64(deal.coin_x_fee);
            if (amount > 0) {
                coin::transfer<X>(alice, treasury, amount);
            }
        };

        // Allie pays coinY fee.
        {
            let amount = asset::to_u64(deal.coin_y_fee);
            if (amount > 0) {
                coin::transfer<Y>(alice, treasury, amount);
            }
        };

        (coin::zero<X>(), coin::zero<Y>())
    }

    fun execute_deal<X, Y>(deal: &TradeDeal<X, Y>, alice: &signer, treasury: address)
    acquires LiquidityPool
    {
        let pool = borrow_global_mut<LiquidityPool<X, Y>>(MODULE_ADMIN);

        // Allie deposits coinX.
        {
            let input_amount = asset::to_u64(deal.input_coin_x);
            deposit_x<X, Y>(pool, coin::withdraw<X>(alice, input_amount));
        };

        // Allie withdraws coinY.
        {
            let output_amount = asset::to_u64(deal.output_coin_y);
            withdraw_y<X, Y>(pool, signer::address_of(alice), output_amount);
        };

        // Allie pays coinX fee.
        {
            let amount = asset::to_u64(deal.coin_x_fee);
            if (amount > 0) {
                coin::transfer<X>(alice, treasury, amount);
            }
        };

        // Allie pays coinY fee.
        {
            let amount = asset::to_u64(deal.coin_y_fee);
            if (amount > 0) {
                coin::transfer<Y>(alice, treasury, amount);
            }
        };
    }

    fun check_coin_store<X>(to: &signer)
    {
        if (!coin::is_account_registered<X>(signer::address_of(to))) {
            coin::register<X>(to);
        };
    }

    public entry fun register<X, Y>(admin: &signer, x_decimals: u8, y_decimals: u8, fee_rate: u64, greedy_alpha: u64, slack_mu: u64)
    acquires LiquidityPool
    {
        let pool_config = PoolConfig {
            fee_rate: decimal::new(0, 0, false),
            greedy_alpha: decimal::new(0, 0, false),
            slack_mu: decimal::new(0, 0, false),
        };
        register_inner<X, Y>(admin, x_decimals, y_decimals, pool_config);
        set_config<X, Y>(admin, fee_rate, greedy_alpha, slack_mu);
    }

    public entry fun set_config<X, Y>(_admin: &signer, fee_rate: u64, greedy_alpha: u64, slack_mu: u64)
    acquires LiquidityPool
    {
        let pool = borrow_global_mut<LiquidityPool<X, Y>>(MODULE_ADMIN);
        let pool_config = PoolConfig {
            fee_rate: decimal::new((fee_rate as u128) , 6, false),
            greedy_alpha: decimal::new((greedy_alpha as u128), 6, false),
            slack_mu: decimal::new((slack_mu as u128), 6, false),
        };
        pool.config = pool_config;
    }

    fun register_inner<X, Y>(admin: &signer, x_decimals: u8, y_decimals: u8, pool_config: PoolConfig)
    {
        let pool = LiquidityPool<X, Y> {
            x_reserve: coin::zero<X>(),
            y_reserve: coin::zero<Y>(),
            x_decimals,
            y_decimals,
            config: pool_config,
        };
        move_to<LiquidityPool<X, Y>>(admin, pool);
    }

    public entry fun add_liquidity<X, Y>(
        from: &signer,
        x_amount: u64,
        y_amount: u64,
    )
    acquires LiquidityPool
    {
        let pool = borrow_global_mut<LiquidityPool<X, Y>>(MODULE_ADMIN);
        deposit_x(pool, coin::withdraw<X>(from, x_amount));
        deposit_y(pool, coin::withdraw<Y>(from, y_amount));
    }

    public entry fun remove_liquidity<X, Y>(
        to: &signer,
        x_amount: u64,
        y_amount: u64,
    )
    acquires LiquidityPool
    {
        let pool = borrow_global_mut<LiquidityPool<X, Y>>(MODULE_ADMIN);
        check_coin_store<X>(to);
        check_coin_store<Y>(to);
        withdraw_x(pool, signer::address_of(to), x_amount);
        withdraw_y(pool, signer::address_of(to), y_amount);
    }

    public entry fun swap_entry<X, Y>(
        alice: &signer,
        amount_in: u64,
        min_amount_out: u64,
        is_x_to_y: bool,
    )
    acquires LiquidityPool, Price
    {
        if (is_x_to_y) {
            swap_x_to_y<X, Y>(alice, amount_in, min_amount_out);
        } else {
            swap_y_to_x<X, Y>(alice, amount_in, min_amount_out);
        };
    }

    // public entry fun swap_direct<X, Y>(
    //     alice: &signer,
    //     coin_in: coin::Coin<X>,
    //     is_x_to_y: bool,
    // ): (coin::Coin<X>, coin::Coin<Y>)
    // acquires LiquidityPool, Price
    // {
    //     let amount_in = coin::value(&coin_in);
    //     if (is_x_to_y) {
    //         swap_x_to_y<X, Y>(alice, amount_in, 0);
    //     } else {
    //         swap_y_to_x<Y, X>(alice, amount_in, 0);
    //     };

    //     (coin::zero<X>(), coin::zero<Y>())
    // }

    public entry fun swap_x_to_y<X, Y>(
        account: &signer,
        amount_in: u64,
        min_amount_out: u64,
    )
    acquires LiquidityPool, Price
    {
        let deal = get_deal_x_to_y<X, Y>(account, amount_in);
        assert!(asset::to_u64(deal.output_coin_y) >= min_amount_out, ERR_INSUFFICIENT_OUTPUT_AMOUNT);
        execute_deal(&deal, account, UMI_TREASUREY);
    }

    public entry fun swap_y_to_x<X, Y>(
        _alice: &signer,
        _amount_in: u64,
        _min_amount_out: u64,
    )
    {
    }

    fun get_deal_x_to_y<X, Y>(
        _account: &signer,
        amount_in: u64,
    ): TradeDeal<X, Y>
    acquires LiquidityPool, Price
    {
        let pool = borrow_global<LiquidityPool<X, Y>>(MODULE_ADMIN);

        let coin_x = coin_info::new<X>(string::utf8(b"X"), string::utf8(b"X"), pool.x_decimals, false);
        let coin_y = coin_info::new<Y>(string::utf8(b"Y"), string::utf8(b"Y"), pool.y_decimals, false);
        let input_asset = asset::new(amount_in, &coin_x);

        let price_oracle = borrow_global<Price<X, Y>>(MODULE_ADMIN);

        let trade_context = TradeContext {
            coin_in_pool: asset::to_decimal(
                asset::from_coin(&pool.x_reserve, &coin_x)
            ),
            coin_out_pool: asset::to_decimal(
                asset::from_coin(&pool.y_reserve, &coin_y)
            ),
            price_oracle: get_price(price_oracle),
            coin_in_swap_amout: asset::to_decimal(input_asset),
        };
        let deal = curve(&trade_context, &pool.config);

        assert!(decimal::is_positive(&deal.delta_coin_in), ERR_INPUT_AMOUTN_MUST_BE_POSITIVE);
        assert!(decimal::is_negative(&deal.delta_coin_out), ERR_OUTPUT_AMOUTN_MUST_BE_POSITIVE);
        assert!(!(decimal::is_negative(&deal.coin_in_fee)), ERR_FEE_IS_MINUS);
        assert!(!(decimal::is_negative(&deal.coin_out_fee)), ERR_FEE_IS_MINUS);

        TradeDeal<X, Y> {
            input_coin_x: asset::from_decimal<X>(&deal.delta_coin_in, &coin_x),
            output_coin_y: asset::from_decimal<Y>(&decimal::abs(&deal.delta_coin_out), &coin_y),
            coin_x_fee: asset::from_decimal<X>(&deal.coin_in_fee, &coin_x),
            coin_y_fee: asset::from_decimal<Y>(&deal.coin_out_fee, &coin_y),
            price: new_price<X, Y>(&deal.price),
        }
    }

    // fun get_deal_y_to_x<X, Y>(
    //     account: &signer,
    //     amount_in: u64,
    //     min_amount_out: u64,
    //     coin_x_decimals: u8,
    //     coin_y_decimals: u8,
    // ): TradeDeal<X, Y>
    // acquires LiquidityPool, Price
    // {
    //     let coin_x = coin_info::new<Y>(string::utf8(b"X"), string::utf8(b"X"), coin_x_decimals, false);
    //     let coin_y = coin_info::new<X>(string::utf8(b"Y"), string::utf8(b"Y"), coin_y_decimals, false);
    //     let input_asset = asset::new(amount_in, &coin_x);

    //     let price = borrow_global<Price<X, Y>>(MODULE_ADMIN);

    //     let deal = get_deal_y_to_x_inner(input_asset, price, &coin_x, &coin_y);
    //     deal
    // }

    fun internal_add_liquidity<X, Y>(
        from: &signer,
        coin_x_amount: Asset<X>,
        coin_y_amount: Asset<Y>,
    )
    acquires LiquidityPool
    {
        let x_amount = asset::to_u64(coin_x_amount);
        let y_amount = asset::to_u64(coin_y_amount);

        let pool = borrow_global_mut<LiquidityPool<X, Y>>(MODULE_ADMIN);
        deposit_x(pool, coin::withdraw<X>(from, x_amount));
        deposit_y(pool, coin::withdraw<Y>(from, y_amount));
    }

    fun internal_remove_liquidity<X, Y>(
        to: address,
        coin_x_amount: Asset<X>,
        coin_y_amount: Asset<Y>,
    )
    acquires LiquidityPool
    {
        let x_amount = asset::to_u64(coin_x_amount);
        let y_amount = asset::to_u64(coin_y_amount);

        let pool = borrow_global_mut<LiquidityPool<X, Y>>(MODULE_ADMIN);
        withdraw_x(pool, to, x_amount);
        withdraw_y(pool, to, y_amount);
    }

    fun deposit_x<X, Y>(pool: &mut LiquidityPool<X, Y>, amount: coin::Coin<X>)
    {
        coin::merge(&mut pool.x_reserve, amount);
    }

    fun deposit_y<X, Y>(pool: &mut LiquidityPool<X, Y>, amount: coin::Coin<Y>)
    {
        coin::merge(&mut pool.y_reserve, amount);
    }

    fun extract_x<X, Y>(pool: &mut LiquidityPool<X, Y>, amount: u64): coin::Coin<X>
    {
        assert!(amount <= coin::value(&pool.x_reserve), ERR_INSUFFICIENT_AMOUNT);
        coin::extract(&mut pool.x_reserve, amount)
    }

    fun extract_y<X, Y>(pool: &mut LiquidityPool<X, Y>, amount: u64): coin::Coin<Y>
    {
        assert!(amount <= coin::value(&pool.y_reserve), ERR_INSUFFICIENT_AMOUNT);
        coin::extract(&mut pool.y_reserve, amount)
    }

    fun withdraw_x<X, Y>(pool: &mut LiquidityPool<X, Y>, to: address, amount: u64)
    {
        // check_coin_store<X>(to);
        let coin_amount = extract_x<X, Y>(pool, amount);
        coin::deposit<X>(to, coin_amount);
    }

    fun withdraw_y<X, Y>(pool: &mut LiquidityPool<X, Y>, to: address, amount: u64)
    {
        // check_coin_store<Y>(to);
        let coin_amount = extract_y<X, Y>(pool, amount);
        coin::deposit<Y>(to, coin_amount);
    }

    fun get_pool_rate<X, Y>(): Decimal
    acquires LiquidityPool
    {
        let pool = borrow_global<LiquidityPool<X, Y>>(MODULE_ADMIN);
        let x_pooled = decimal::from_u64(coin::value(&pool.x_reserve));
        let y_pooled = decimal::from_u64(coin::value(&pool.y_reserve));
        decimal::div(&x_pooled, &y_pooled)
    }

    // fun get_pool_value<X, Y>(price_oracle: &Decimal): Decimal
    // acquires LiquidityPool
    // {
    //     let pool = borrow_global<LiquidityPool<X, Y>>(MODULE_ADMIN);
    //     let x_pooled = asset::from_coin(&pool.coin_x);
    //     let y_pooled = asset::from_coin(&pool.coin_y);
    //     decimal::from_u64(coin::value(&pool.coin_x));
    //     let y_pooled = decimal::from_u64(coin::value(&pool.coin_y));

    //     decimal::add(
    //         &x_pooled,
    //         &decimal::mul(&y_pooled, price_oracle)
    //     )
    // }

    // fun get_treasury_value<X, Y>(price_oracle: &Decimal): Decimal
    // {
    //     let x = coin::balance<X>(UMI_TREASUREY);
    //     let y = coin::balance<Y>(UMI_TREASUREY);
    //     let x_pooled = decimal::from_u64(&coin::value(&x));
    //     let y_pooled = decimal::from_u64(&coin::value(&y));

    //     decimal::add(
    //         &x_pooled,
    //         &decimal::mul(&y_pooled, price_oracle)
    //     )
    // }

    fun get_deal_x_to_y_inner<X, Y>(
        input_asset: Asset<X>,
        price_oracle: &Price<X, Y>,
        coin_x: &CoinInfo<X>,
        coin_y: &CoinInfo<Y>,
    ) : TradeDeal<X, Y>
    acquires LiquidityPool
    {
        let pool = borrow_global<LiquidityPool<X, Y>>(MODULE_ADMIN);

        let trade_context = TradeContext {
            coin_in_pool: asset::to_decimal(
                asset::from_coin(&pool.x_reserve, coin_x)
            ),
            coin_out_pool: asset::to_decimal(
                asset::from_coin(&pool.y_reserve, coin_y)
            ),
            price_oracle: get_price(price_oracle),
            coin_in_swap_amout: asset::to_decimal(input_asset),
        };
        let deal = curve(&trade_context, &pool.config);

        assert!(decimal::is_positive(&deal.delta_coin_in), ERR_INPUT_AMOUTN_MUST_BE_POSITIVE);
        assert!(decimal::is_negative(&deal.delta_coin_out), ERR_OUTPUT_AMOUTN_MUST_BE_POSITIVE);
        assert!(!(decimal::is_negative(&deal.coin_in_fee)), ERR_FEE_IS_MINUS);
        assert!(!(decimal::is_negative(&deal.coin_out_fee)), ERR_FEE_IS_MINUS);

        TradeDeal<X, Y> {
            input_coin_x: asset::from_decimal<X>(&deal.delta_coin_in, coin_x),
            output_coin_y: asset::from_decimal<Y>(&decimal::abs(&deal.delta_coin_out), coin_y),
            coin_x_fee: asset::from_decimal<X>(&deal.coin_in_fee, coin_x),
            coin_y_fee: asset::from_decimal<Y>(&deal.coin_out_fee, coin_y),
            price: new_price<X, Y>(&deal.price),
        }
    }

    public fun get_deal_y_to_x_inner<X, Y>(
        input_asset: Asset<Y>,
        price_oracle: &Price<X, Y>,
        coin_x: &CoinInfo<X>,
        coin_y: &CoinInfo<Y>,
    ) : TradeDeal<Y, X>
    acquires LiquidityPool
    {
        let pool = borrow_global<LiquidityPool<X, Y>>(MODULE_ADMIN);

        let trade_context = TradeContext {
            coin_in_pool: asset::to_decimal(
                asset::from_coin(&pool.y_reserve, coin_y)
            ),
            coin_out_pool: asset::to_decimal(
                asset::from_coin(&pool.x_reserve, coin_x)
            ),
            price_oracle: decimal::div(&decimal::one(), &get_price(price_oracle)),
            coin_in_swap_amout: asset::to_decimal(input_asset),
        };
        let deal = curve(&trade_context, &pool.config);

        assert!(decimal::is_positive(&deal.delta_coin_in), ERR_INPUT_AMOUTN_MUST_BE_POSITIVE);
        assert!(decimal::is_negative(&deal.delta_coin_out), ERR_OUTPUT_AMOUTN_MUST_BE_POSITIVE);
        assert!(!(decimal::is_negative(&deal.coin_in_fee)), ERR_FEE_IS_MINUS);
        assert!(!(decimal::is_negative(&deal.coin_out_fee)), ERR_FEE_IS_MINUS);

        TradeDeal<Y, X> {
            input_coin_x: asset::from_decimal<Y>(&deal.delta_coin_in, coin_y),
            output_coin_y: asset::from_decimal<X>(&decimal::abs(&deal.delta_coin_out), coin_x),
            coin_x_fee: asset::from_decimal<Y>(&deal.coin_in_fee, coin_y),
            coin_y_fee: asset::from_decimal<X>(&deal.coin_out_fee, coin_x),
            price: new_price<Y, X>(&deal.price),
        }
    }

    public fun get_price_x_to_y<X, Y>(
        account: &signer,
        amount_in: u64,
    ): Decimal
    acquires LiquidityPool, Price
    {
        let deal = get_deal_x_to_y<X, Y>(account, amount_in);
        deal.price.price
    }

    // public entry fun get_price_y_to_x<X, Y>(
    //     account: &signer,
    //     amount_in: u64,
    //     min_amount_out: u64,
    //     coin_x_decimals: u8,
    //     coin_y_decimals: u8,
    // ) : Price<X, Y>
    // {
    //     let deal = get_deal_y_to_x<X, Y>(account, amount_in, min_amount_out, coin_x_decimals, coin_y_decimals);
    //     deal.price
    // }

    fun get_price_x_to_y_inner<X, Y>(
        input_asset: Asset<X>,
        price_oracle: &Price<X, Y>,
        coin_x: &CoinInfo<X>,
        coin_y: &CoinInfo<Y>,
    ) : Price<X, Y>
    acquires LiquidityPool
    {
        let deal = get_deal_x_to_y_inner<X, Y>(input_asset, price_oracle, coin_x, coin_y);
        deal.price
    }

    fun get_price_y_to_x_inner<X, Y>(
        input_asset: Asset<Y>,
        price_oracle: &Price<X, Y>,
        coin_x: &CoinInfo<X>,
        coin_y: &CoinInfo<Y>,
    ) : Price<X, Y>
    acquires LiquidityPool
    {
        let deal = get_deal_y_to_x_inner<X, Y>(input_asset, price_oracle, coin_x, coin_y);
        new_price<X, Y>(&decimal::div(&decimal::one(), &get_price(&deal.price)))
    }

    #[test_only]
    struct CapContainer<phantom T> has key {
        mint_cap: coin::MintCapability<T>,
        burn_cap: coin::BurnCapability<T>,
        freeze_cap: coin::FreezeCapability<T>,
    }

    #[test_only]
    fun issue_token<X>(
        admin: &signer,
        to: &signer,
        total_supply: &Asset<X>,
        coin: &CoinInfo<X>,
    )
    {
        let (burn_cap, freeze_cap, mint_cap) = coin_info::initialize<X>(admin, coin);

        let a = coin::mint(asset::to_u64(*total_supply), &mint_cap);
        coin::deposit(signer::address_of(to), a);
        move_to<CapContainer<X>>(admin, CapContainer{ mint_cap, burn_cap, freeze_cap });
    }

    #[test_only]
    fun debug_curve_deal(deal: &CurveDeal)
    {
        debug::print(&deal.delta_coin_in);
        debug::print(&deal.delta_coin_out);
        debug::print(&deal.coin_in_fee);
        debug::print(&deal.coin_out_fee);
        debug::print(&deal.price);
    }


    #[test_only]
    fun debug_trade_deal<X, Y>(deal: &TradeDeal<X, Y>)
    {
        debug::print(&deal.input_coin_x);
        debug::print(&deal.output_coin_y);
        debug::print(&deal.coin_x_fee);
        debug::print(&deal.coin_y_fee);
        debug::print(&deal.price);
    }

    #[test_only]
    fun debug_pool<X, Y>()
    acquires LiquidityPool
    {
        let pool = borrow_global<LiquidityPool<X, Y>>(MODULE_ADMIN);
        debug::print(&coin::value(&pool.x_reserve));
        debug::print(&coin::value(&pool.y_reserve));
    }

    #[test_only]
    fun debug_balance<X, Y>(addr: address)
    {
        debug::print(&coin::balance<X>(addr));
        debug::print(&coin::balance<Y>(addr));
    }

    #[test_only]
    fun tobe_balance<X>(addr: address, expected: &Decimal, coin: &CoinInfo<X>)
    {
        let bal = coin::balance<X>(addr);
        assert!(decimal::equal(
            &asset::to_decimal(asset::new(bal, coin)),
            expected
        ), 0);
    }

    #[test(admin = @umi_pool, token_owner = @0x02)]
    fun test_get_price(admin: signer, token_owner: signer)
    acquires LiquidityPool
    {
        use aptos_framework::aptos_account;
        use aptos_framework::genesis;

        let coin_red = coin_info::new<coin_list::RED>(
            string::utf8(b"redcoin"),
            string::utf8(b"RED"),
            6,
            true,
        );

        let coin_blue = coin_info::new<coin_list::BLUE>(
            string::utf8(b"bluecoin"),
            string::utf8(b"BLUE"),
            8,
            true,
        );

        let total_supply_x = asset::from_u64(math::expand_to_decimals(1, 9), &coin_red);
        let total_supply_y = asset::from_u64(math::expand_to_decimals(1, 9), &coin_blue);
        let debt_x_amount = asset::from_u64(math::expand_to_decimals(2, 6), &coin_red);
        let debt_y_amount = asset::from_u64(math::expand_to_decimals(3, 8), &coin_blue);

        let price_oracle =  new_price<coin_list::RED, coin_list::BLUE>(&decimal::new(1, 0, false));
        let pool_config = PoolConfig {
            fee_rate: decimal::new(3, 3, false),
            slack_mu: decimal::new(2, 0, false),
            greedy_alpha: decimal::new(1, 0, false),
        };

        // initialize Pool and Coin
        {
            genesis::setup();
            aptos_account::create_account(signer::address_of(&admin));
            coin::register<coin_list::RED>(&admin);
            coin::register<coin_list::BLUE>(&admin);
            coin::register<coin_list::RED>(&token_owner);
            coin::register<coin_list::BLUE>(&token_owner);

            issue_token<coin_list::RED>(&admin, &token_owner, &total_supply_x, &coin_red);
            issue_token<coin_list::BLUE>(&admin, &token_owner, &total_supply_y, &coin_blue);

            coin::transfer<coin_list::RED>(&token_owner, signer::address_of(&admin), asset::to_u64(debt_x_amount));
            coin::transfer<coin_list::BLUE>(&token_owner, signer::address_of(&admin), asset::to_u64(debt_y_amount));

            register_inner<coin_list::RED, coin_list::BLUE>(
                &admin,
                coin_info::get_decimals(&coin_red),
                coin_info::get_decimals(&coin_blue),
                pool_config,
            );
        };

        // p < p_*
        {
            let pool_rate = decimal::new(80, 2, false);
            let deposit_x_amount = decimal::from_u64(math::expand_to_decimals(4000, 0));
            let deposit_y_amount = decimal::div(&deposit_x_amount, &pool_rate);
            internal_add_liquidity<coin_list::RED, coin_list::BLUE>(
                &admin,
                asset::from_decimal<coin_list::RED>(&deposit_x_amount, &coin_red),
                asset::from_decimal<coin_list::BLUE>(&deposit_y_amount, &coin_blue),
            );

            // Alice considers to swap coinX to coinY
            let price_ask_y = get_price_x_to_y_inner<coin_list::RED, coin_list::BLUE>(
                asset::from_u64<coin_list::RED>(100, &coin_red),
                &price_oracle,
                &coin_red,
                &coin_blue,
            );
            assert!(decimal::equal(&get_price(&price_ask_y), &decimal::new(100, 2, false)), 501);

            // Alice considers to swap coinY to coinX
            let price_bid_y = get_price_y_to_x_inner<coin_list::RED, coin_list::BLUE>(
                asset::from_u64<coin_list::BLUE>(100, &coin_blue),
                &price_oracle,
                &coin_red,
                &coin_blue,
            );
            assert!(decimal::equal(&get_price(&price_bid_y), &decimal::new(64, 2, false)), 502);

            internal_remove_liquidity<coin_list::RED, coin_list::BLUE>(
                signer::address_of(&admin),
                asset::from_decimal<coin_list::RED>(&deposit_x_amount, &coin_red),
                asset::from_decimal<coin_list::BLUE>(&deposit_y_amount, &coin_blue),
            );
        };

        // p > p_*
        {
            let pool_rate = decimal::new(125, 2, false);
            let deposit_x_amount = decimal::from_u64(math::expand_to_decimals(4000, 0));
            let deposit_y_amount = decimal::div(&deposit_x_amount, &pool_rate);
            internal_add_liquidity<coin_list::RED, coin_list::BLUE>(
                &admin,
                asset::from_decimal<coin_list::RED>(&deposit_x_amount, &coin_red),
                asset::from_decimal<coin_list::BLUE>(&deposit_y_amount, &coin_blue),
            );

            // Alice considers to swap coinX to coinY
            let price_ask_y = get_price_x_to_y_inner<coin_list::RED, coin_list::BLUE>(
                asset::from_u64<coin_list::RED>(100, &coin_red),
                &price_oracle,
                &coin_red,
                &coin_blue,
            );
            assert!(decimal::equal(&get_price(&price_ask_y), &decimal::new(15625, 4, false)), 503);

            // Alice considers to swap coinY to coinX
            let price_bid_y = get_price_y_to_x_inner<coin_list::RED, coin_list::BLUE>(
                asset::from_u64<coin_list::BLUE>(100, &coin_blue),
                &price_oracle,
                &coin_red,
                &coin_blue,
            );
            assert!(decimal::equal(&get_price(&price_bid_y), &decimal::new(100, 2, false)), 504);

            internal_remove_liquidity<coin_list::RED, coin_list::BLUE>(
                signer::address_of(&admin),
                asset::from_decimal<coin_list::RED>(&deposit_x_amount, &coin_red),
                asset::from_decimal<coin_list::BLUE>(&deposit_y_amount, &coin_blue),
            );
        };
    }

    #[test_only]
    fun initialize_pool_apt<X, Y>(admin: &signer, token_owner: &signer, treasury: &signer, coin_x: &CoinInfo<X>, coin_y: &CoinInfo<Y>)
    {
        use aptos_framework::aptos_account;
        use aptos_framework::genesis;

        let total_supply_y = asset::from_u64(math::expand_to_decimals(1, 9), coin_y);
        let debt_y_amount = asset::from_u64(math::expand_to_decimals(3, 8), coin_y);
        let pool_config = PoolConfig {
            fee_rate: decimal::new(3, 3, false),
            slack_mu: decimal::new(2, 0, false),
            greedy_alpha: decimal::new(1, 0, false),
        };

        genesis::setup();
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(treasury));

        check_coin_store<X>(admin);
        check_coin_store<Y>(admin);
        check_coin_store<X>(token_owner);
        check_coin_store<Y>(token_owner);
        check_coin_store<X>(treasury);
        check_coin_store<Y>(treasury);

        issue_token<Y>(admin, token_owner, &total_supply_y, coin_y);

        // coin::transfer<X>(
        //     token_owner,
        //     signer::address_of(admin),
        //     asset::to_u64(debt_x_amount)
        // );
        coin::transfer<Y>(
            token_owner,
            signer::address_of(admin),
            asset::to_u64(debt_y_amount)
        );

        register_inner<X, Y>(
            admin,
            coin_info::get_decimals(coin_x),
            coin_info::get_decimals(coin_y),
            pool_config,
        );
    }

    #[test_only]
    fun initialize_pool<X, Y>(admin: &signer, token_owner: &signer, treasury: &signer, coin_x: &CoinInfo<X>, coin_y: &CoinInfo<Y>)
    {
        use aptos_framework::aptos_account;
        use aptos_framework::genesis;

        let total_supply_x = asset::from_u64(math::expand_to_decimals(1, 9), coin_x);
        let total_supply_y = asset::from_u64(math::expand_to_decimals(1, 9), coin_y);
        let debt_x_amount = asset::from_u64(math::expand_to_decimals(2, 6), coin_x);
        let debt_y_amount = asset::from_u64(math::expand_to_decimals(3, 8), coin_y);
        let pool_config = PoolConfig {
            fee_rate: decimal::new(3, 3, false),
            slack_mu: decimal::new(2, 0, false),
            greedy_alpha: decimal::new(1, 0, false),
        };

        genesis::setup();
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(treasury));

        check_coin_store<X>(admin);
        check_coin_store<Y>(admin);
        check_coin_store<X>(token_owner);
        check_coin_store<Y>(token_owner);
        check_coin_store<X>(treasury);
        check_coin_store<Y>(treasury);

        issue_token<X>(admin, token_owner, &total_supply_x, coin_x);
        issue_token<Y>(admin, token_owner, &total_supply_y, coin_y);

        coin::transfer<X>(
            token_owner,
            signer::address_of(admin),
            asset::to_u64(debt_x_amount)
        );
        coin::transfer<Y>(
            token_owner,
            signer::address_of(admin),
            asset::to_u64(debt_y_amount)
        );

        register_inner<X, Y>(
            admin,
            coin_info::get_decimals(coin_x),
            coin_info::get_decimals(coin_y),
            pool_config,
        );
    }

    #[test_only]
    fun initialize_alice<X, Y>(token_owner: &signer, alice: &signer, coin_x_amount: &Asset<X>, coin_y_amount: &Asset<Y>)
    {
        use aptos_framework::aptos_account;

        aptos_account::create_account(signer::address_of(alice));
        check_coin_store<X>(alice);
        check_coin_store<Y>(alice);
        coin::transfer<X>(token_owner, signer::address_of(alice), asset::to_u64(*coin_x_amount));
        coin::transfer<Y>(token_owner, signer::address_of(alice), asset::to_u64(*coin_y_amount));
    }

    // #[test(admin = @umi_pool, token_owner = @0x02, treasury = @0x21, alice = @0x41)]
    // fun test_alice_swap_x_to_y2(admin: signer, token_owner: signer, treasury: signer, alice: signer)
    // acquires LiquidityPool, Price
    // {

    //     let coin_red = coin_info::new<coin_list::RED>(
    //         string::utf8(b"redcoin"),
    //         string::utf8(b"RED"),
    //         8,
    //         true,
    //     );

    //     let coin_blue = coin_info::new<coin_list::BLUE>(
    //         string::utf8(b"bluecoin"),
    //         string::utf8(b"BLUE"),
    //         6,
    //         true,
    //     );

    //     let price_oracle =  new_price<coin_list::RED, coin_list::BLUE>(&decimal::new(185, 2, false));
    //     register_price<coin_list::RED, coin_list::BLUE>(&admin);
    //     set_price<coin_list::RED, coin_list::BLUE>(
    //         &admin,
    //         decimal::to_u64(get_price(&price_oracle)),
    //         decimal::get_decimals(&get_price(&price_oracle)),
    //     );

    //     // initialize Pool and Coin
    //     initialize_pool(&admin, &token_owner, &treasury, &coin_red, &coin_blue);

    //     // initialize Alice
    //     initialize_alice(
    //         &token_owner,
    //         &alice,
    //         &asset::from_u64<coin_list::RED>(math::expand_to_decimals(100, 0), &coin_red),
    //         &asset::from_u64<coin_list::BLUE>(math::expand_to_decimals(0, 3), &coin_blue),
    //     );

    //     {
    //         let deposit_x_amount = decimal::from_u64(math::expand_to_decimals(2, 6));
    //         let deposit_y_amount = decimal::from_u64(math::expand_to_decimals(10, 6));
    //         internal_add_liquidity<coin_list::RED, coin_list::BLUE>(
    //             &admin,
    //             asset::from_decimal<coin_list::RED>(&deposit_x_amount, &coin_red),
    //             asset::from_decimal<coin_list::BLUE>(&deposit_y_amount, &coin_blue),
    //         );

    //         // Alice considers to swap coinX to coinY
    //         swap_entry<coin_list::RED, coin_list::BLUE>(
    //             &alice,
    //             math::expand_to_decimals(1, coin_info::get_decimals(&coin_red)),
    //             0,
    //             true,
    //          );
    //     };
    // }

    // #[test(admin = @umi_pool, token_owner = @0x02, treasury = @0x21, alice = @0x41)]
    // fun test_alice_swap_x_to_y(admin: signer, token_owner: signer, treasury: signer, alice: signer)
    // acquires LiquidityPool, Price
    // {

    //     let coin_red = coin_info::new<coin_list::RED>(
    //         string::utf8(b"redcoin"),
    //         string::utf8(b"RED"),
    //         8,
    //         true,
    //     );

    //     let coin_blue = coin_info::new<coin_list::BLUE>(
    //         string::utf8(b"bluecoin"),
    //         string::utf8(b"BLUE"),
    //         6,
    //         true,
    //     );

    //     let price_oracle =  new_price<coin_list::RED, coin_list::BLUE>(&decimal::new(185, 6, false));
    //     register_price<coin_list::RED, coin_list::BLUE>(&admin);
    //     set_price<coin_list::RED, coin_list::BLUE>(
    //         &admin,
    //         decimal::to_u64(get_price(&price_oracle)),
    //         decimal::get_decimals(&get_price(&price_oracle)),
    //     );

    //     // initialize Pool and Coin
    //     initialize_pool(&admin, &token_owner, &treasury, &coin_red, &coin_blue);

    //     // initialize Alice
    //     initialize_alice(
    //         &token_owner,
    //         &alice,
    //         &asset::from_u64<coin_list::RED>(math::expand_to_decimals(100, 0), &coin_red),
    //         &asset::from_u64<coin_list::BLUE>(math::expand_to_decimals(0, 3), &coin_blue),
    //     );

    //     {
    //         let deposit_x_amount = decimal::from_u64(math::expand_to_decimals(2000000, 0));
    //         let deposit_y_amount = decimal::from_u64(math::expand_to_decimals(100000000, 0));
    //         internal_add_liquidity<coin_list::RED, coin_list::BLUE>(
    //             &admin,
    //             asset::from_decimal<coin_list::RED>(&deposit_x_amount, &coin_red),
    //             asset::from_decimal<coin_list::BLUE>(&deposit_y_amount, &coin_blue),
    //         );

    //         // Alice considers to swap coinX to coinY
    //         swap_x_to_y<coin_list::RED, coin_list::BLUE>(
    //             &alice,
    //             math::expand_to_decimals(100, coin_info::get_decimals(&coin_red)),
    //             // asset::from_u64<coin_list::RED>(100, &coin_red),
    //             0,
    //          );
    //         // let deal = get_deal_x_to_y_inner<coin_list::RED, coin_list::BLUE>(
    //         //     asset::from_u64<coin_list::RED>(100, &coin_red),
    //         //     &price_oracle,
    //         //     &coin_red,
    //         //     &coin_blue,
    //         // );

    //         // execute_deal(&deal, &alice, signer::address_of(&treasury));

    //         tobe_balance(signer::address_of(&treasury), &decimal::new(3, 1, false), &coin_red);
    //         tobe_balance(signer::address_of(&treasury), &decimal::new(0, 0, false), &coin_blue);
    //         tobe_balance(signer::address_of(&alice), &decimal::new(900, 0, false), &coin_red);
    //         tobe_balance(signer::address_of(&alice), &decimal::new(10997, 1, false), &coin_blue);
    //     };
    // }

    #[test(admin = @umi_pool, token_owner = @0x02, treasury = @0x21, alice = @0x41)]
    fun test_swap_x_to_y(admin: signer, token_owner: signer, treasury: signer, alice: signer)
    acquires LiquidityPool
    {

        let coin_red = coin_info::new<coin_list::RED>(
            string::utf8(b"redcoin"),
            string::utf8(b"RED"),
            6,
            true,
        );

        let coin_blue = coin_info::new<coin_list::BLUE>(
            string::utf8(b"bluecoin"),
            string::utf8(b"BLUE"),
            8,
            true,
        );

        let price_oracle =  new_price<coin_list::RED, coin_list::BLUE>(&decimal::new(1, 0, false));

        // initialize Pool and Coin
        initialize_pool(&admin, &token_owner, &treasury, &coin_red, &coin_blue);

        // initialize Alice
        initialize_alice(
            &token_owner,
            &alice,
            &asset::from_u64<coin_list::RED>(math::expand_to_decimals(1, 3), &coin_red),
            &asset::from_u64<coin_list::BLUE>(math::expand_to_decimals(1, 3), &coin_blue),
        );

        // p < p_*
        {
            let pool_rate = decimal::new(80, 2, false);
            let deposit_x_amount = decimal::from_u64(math::expand_to_decimals(4000, 0));
            let deposit_y_amount = decimal::div(&deposit_x_amount, &pool_rate);
            internal_add_liquidity<coin_list::RED, coin_list::BLUE>(
                &admin,
                asset::from_decimal<coin_list::RED>(&deposit_x_amount, &coin_red),
                asset::from_decimal<coin_list::BLUE>(&deposit_y_amount, &coin_blue),
            );

            tobe_balance(signer::address_of(&treasury), &decimal::new(0, 0, false), &coin_red);
            tobe_balance(signer::address_of(&treasury), &decimal::new(0, 0, false), &coin_blue);
            tobe_balance(signer::address_of(&alice), &decimal::new(1000, 0, false), &coin_red);
            tobe_balance(signer::address_of(&alice), &decimal::new(1000, 0, false), &coin_blue);

            // Alice considers to swap coinX to coinY
            let deal = get_deal_x_to_y_inner<coin_list::RED, coin_list::BLUE>(
                asset::from_u64<coin_list::RED>(100, &coin_red),
                &price_oracle,
                &coin_red,
                &coin_blue,
            );

            execute_deal(&deal, &alice, signer::address_of(&treasury));

            tobe_balance(signer::address_of(&treasury), &decimal::new(3, 1, false), &coin_red);
            tobe_balance(signer::address_of(&treasury), &decimal::new(0, 0, false), &coin_blue);
            tobe_balance(signer::address_of(&alice), &decimal::new(900, 0, false), &coin_red);
            tobe_balance(signer::address_of(&alice), &decimal::new(10997, 1, false), &coin_blue);
        };
    }

    // #[test(admin = @umi_pool, token_owner = @0x02, treasury = @0x21, alice = @0x41)]
    // fun test_swap_x_to_y_2(admin: signer, token_owner: signer, treasury: signer, alice: signer)
    // acquires LiquidityPool
    // {

    //     let coin_red = coin_info::new<coin_list::RED>(
    //         string::utf8(b"redcoin"),
    //         string::utf8(b"RED"),
    //         6,
    //         true,
    //     );

    //     let coin_blue = coin_info::new<coin_list::BLUE>(
    //         string::utf8(b"bluecoin"),
    //         string::utf8(b"BLUE"),
    //         8,
    //         true,
    //     );

    //     let price_oracle = new_price<coin_list::RED, coin_list::BLUE>(&decimal::new(1, 0, false));

    //     // initialize Pool and Coin
    //     initialize_pool(&admin, &token_owner, &treasury, &coin_red, &coin_blue);

    //     // initialize Alice
    //     initialize_alice(
    //         &token_owner,
    //         &alice,
    //         &asset::from_u64<coin_list::RED>(math::expand_to_decimals(1, 3), &coin_red),
    //         &asset::from_u64<coin_list::BLUE>(math::expand_to_decimals(1, 3), &coin_blue),
    //     );

    //     // p > p_*
    //     {
    //         let pool_rate = decimal::new(125, 2, false);
    //         let deposit_x_amount = decimal::from_u64(math::expand_to_decimals(4000, 0));
    //         let deposit_y_amount = decimal::div(&deposit_x_amount, &pool_rate);
    //         internal_add_liquidity<coin_list::RED, coin_list::BLUE>(
    //             &admin,
    //             asset::from_decimal<coin_list::RED>(&deposit_x_amount, &coin_red),
    //             asset::from_decimal<coin_list::BLUE>(&deposit_y_amount, &coin_blue),
    //         );

    //         tobe_balance(signer::address_of(&treasury), &decimal::new(0, 0, false), &coin_red);
    //         tobe_balance(signer::address_of(&treasury), &decimal::new(0, 0, false), &coin_blue);
    //         tobe_balance(signer::address_of(&alice), &decimal::new(1000, 0, false), &coin_red);
    //         tobe_balance(signer::address_of(&alice), &decimal::new(1000, 0, false), &coin_blue);

    //         // Alice considers to swap coinX to coinY
    //         let deal = get_deal_x_to_y_inner<coin_list::RED, coin_list::BLUE>(
    //             asset::from_u64<coin_list::RED>(100, &coin_red),
    //             &price_oracle,
    //             &coin_red,
    //             &coin_blue,
    //         );

    //         execute_deal(&deal, &alice, signer::address_of(&treasury));

    //         tobe_balance(signer::address_of(&treasury), &decimal::new(3, 1, false), &coin_red);
    //         tobe_balance(signer::address_of(&treasury), &decimal::new(0, 0, false), &coin_blue);
    //         tobe_balance(signer::address_of(&alice), &decimal::new(900, 0, false), &coin_red);
    //         tobe_balance(signer::address_of(&alice), &decimal::new(1063808, 3, false), &coin_blue);
    //     };
    // }
}