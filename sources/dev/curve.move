#[test_only]
module umi_pool::dev_curve {
    // use std::signer;
    // use std::error;
    use std::debug;

    use umi_pool::decimal;
    use umi_pool::decimal::Decimal;

    const ERR_CONTRACT_ADDRESS: u64 = 0;
    const ERR_POOL: u64 = 1;
    const ERR_CONCENTRATION: u64 = 2;
    const ERR_INPUT_AMOUNT: u64 = 3;
    const ERR_UNEXPECTED_ERROR: u64 = 9;

    #[derive(Debug)]
    struct TradeContext has drop {
        coin_in_pool: Decimal,
        coin_out_pool: Decimal,
        coin_in_swap_amout: Decimal,
        price_oracle: Decimal, // coin_in / coin_out
    }

    #[derive(Debug)]
    struct PoolConfig has drop {
        fee_rate: Decimal,
        slack_mu: Decimal,
        greedy_alpha: Decimal,
    }

    #[derive(Debug)]
    struct TradeDeal has drop {
        delta_x: Decimal,
        delta_y: Decimal,
        x_fee: Decimal,
        y_fee: Decimal,
        price: Decimal,
    }

    fun curve(
        trade_context: &TradeContext,
        pool_config: &PoolConfig,
    ): TradeDeal {
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
        let constant_k = decimal::mul(&x_before_swap, &y_before_swap);

        let price_pool = decimal::div(&x_before_swap, &y_before_swap);

        let price_min = decimal::min(&price_oracle, &price_pool);
        let price_max = decimal::max(&price_oracle, &price_pool);

        let concentration = decimal::div(&decimal::div(&price_min, &price_max), &greedy_alpha);
        let price_bid = decimal::mul(&price_pool, &concentration);
        let price_ask = decimal::div(&price_pool, &concentration);

        let y_bid = decimal::sub(&y_before_swap, &decimal::div(&delta_x, &price_bid));
        let y_ask = decimal::sub(&y_before_swap, &decimal::div(&delta_x, &price_ask));
        let y_uni = decimal::div(&decimal::div(&constant_k, &slack_mu), &x_after_swap);
        let y_after_swap = decimal::max(&decimal::max(&y_bid, &y_ask), &y_uni);

        let delta_y = decimal::sub(&y_after_swap, &y_before_swap);

        let price_deal = decimal::mul(&decimal::new(1, 0, true), &decimal::div(&delta_x, &delta_y));

        let deal = TradeDeal {
            delta_x,
            delta_y,
            x_fee,
            y_fee: decimal::zero(),
            price: price_deal
        };
        deal
    }

    #[test_only]
    fun to_be_deal(a: &TradeDeal, b: &TradeDeal) {
        assert!(decimal::equal(&a.delta_x, &b.delta_x), 0);
        assert!(decimal::equal(&a.delta_y, &b.delta_y), 1);
        assert!(decimal::equal(&a.x_fee, &b.x_fee), 2);
        assert!(decimal::equal(&a.y_fee, &b.y_fee), 3);
        assert!(decimal::equal(&a.price, &b.price), 4);
    }

    #[test]
    fun test_swap_coin_x_to_coin_y() {
        let price_oracle = decimal::new(1000, 3, false);
        let price_pool = decimal::new(125, 2, false);
        let coin_in_pool = decimal::new(4000, 0, false);
        let pool_config = PoolConfig {
            fee_rate: decimal::new(3, 3, false),
            slack_mu: decimal::new(2, 0, false),
            greedy_alpha: decimal::new(1, 0, false),
        };
        let trade_context = TradeContext {
            coin_in_pool: coin_in_pool,
            coin_out_pool: decimal::div(&coin_in_pool, &price_pool),
            price_oracle,
            coin_in_swap_amout: decimal::new(100, 0, false),
        };
        let deal = curve(&trade_context, &pool_config);

        let expected = TradeDeal {
            delta_x: decimal::new(99700000000, 9, false),
            delta_y: decimal::new(63808000000, 9, true),
            x_fee: decimal::new(300000000, 9, false),
            y_fee: decimal::new(0, 0, false),
            price: decimal::new(1562500000, 9, false),
        };
        to_be_deal(&deal, &expected);
    }

    #[test]
    fun test_swap_coin_x_to_coin_y_big() {
        let price_oracle = decimal::new(1000, 3, false);
        let price_pool = decimal::new(125, 2, false);
        let coin_in_pool = decimal::new(4000, 0, false);
        let pool_config = PoolConfig {
            fee_rate: decimal::new(3, 3, false),
            slack_mu: decimal::new(2, 0, false),
            greedy_alpha: decimal::new(1, 0, false),
        };
        let trade_context = TradeContext {
            coin_in_pool: coin_in_pool,
            coin_out_pool: decimal::div(&coin_in_pool, &price_pool),
            price_oracle,
            coin_in_swap_amout: decimal::new(3900, 0, false),
        };
        let deal = curve(&trade_context, &pool_config);

        let expected = TradeDeal {
            delta_x: decimal::new(3888300000000, 9, false),
            delta_y: decimal::new(2388671830433, 9, true),
            x_fee: decimal::new(11700000000, 9, false),
            y_fee: decimal::new(0, 0, false),
            price: decimal::new(1627808370, 9, false),
        };
        to_be_deal(&deal, &expected);
    }

    #[test]
    fun test_swap_coin_y_to_coin_x() {
        let price_oracle = decimal::new(1000, 3, false);
        let price_pool = decimal::new(8, 1, false);
        let coin_in_pool = decimal::new(4000, 0, false);
        let pool_config = PoolConfig {
            fee_rate: decimal::new(3, 3, false),
            slack_mu: decimal::new(2, 0, false),
            greedy_alpha: decimal::new(1, 0, false),
        };
        let trade_context = TradeContext {
            coin_in_pool: coin_in_pool,
            coin_out_pool: decimal::div(&coin_in_pool, &price_pool),
            price_oracle: decimal::div(&decimal::one(), &price_oracle),
            coin_in_swap_amout: decimal::new(100, 0, false),
        };
        let deal = curve(&trade_context, &pool_config);

        let expected = TradeDeal {
            delta_x: decimal::new(99700000000, 9, false),
            delta_y: decimal::new(99700000000, 9, true),
            x_fee: decimal::new(300000000, 9, false),
            y_fee: decimal::new(0, 9, false),
            price: decimal::new(1000000000, 9, false),
        };
        to_be_deal(&deal, &expected);
    }

    #[test]
    fun test_swap_coin_y_to_coin_x_big() {
        let price_oracle = decimal::new(1000, 3, false);
        let price_pool = decimal::new(8, 1, false);
        let coin_in_pool = decimal::new(4000, 0, false);
        let pool_config = PoolConfig {
            fee_rate: decimal::new(3, 3, false),
            slack_mu: decimal::new(2, 0, false),
            greedy_alpha: decimal::new(1, 0, false),
        };
        let trade_context = TradeContext {
            coin_in_pool: coin_in_pool,
            coin_out_pool: decimal::div(&coin_in_pool, &price_pool),
            price_oracle: decimal::div(&decimal::one(), &price_oracle),
            coin_in_swap_amout: decimal::new(3900, 0, false),
        };
        let deal = curve(&trade_context, &pool_config);

        let expected = TradeDeal {
            delta_x: decimal::new(3888300000000, 9, false),
            delta_y: decimal::new(3732299735051, 9, true),
            x_fee: decimal::new(11700000000, 9, false),
            y_fee: decimal::new(0, 9, false),
            price: decimal::new(1041797357, 9, false),
        };
        to_be_deal(&deal, &expected);
    }

    #[test]
    fun dev_swap() {
        let fee_rate = decimal::new(3, 3, false);
        let slack_mu = decimal::new(2, 0, false);

        let delta_x_and_fee = decimal::new(100, 0, false);
        let x_fee = decimal::mul(&delta_x_and_fee, &fee_rate);
        let delta_x = decimal::sub(&delta_x_and_fee, &x_fee);
        debug::print(&x_fee);
        debug::print(&delta_x);

        let x_befere_swap = decimal::new(4000, 0, false);
        let y_before_swap = decimal::new(3200, 0, false);
        let x_after_swap = decimal::add(&x_befere_swap, &delta_x);
        let constant_k = decimal::mul(&x_befere_swap, &y_before_swap);

        let price_oracle = decimal::new(1, 0, false);
        let price_pool = decimal::div(&x_befere_swap, &y_before_swap);
        debug::print(&price_oracle);
        debug::print(&price_pool);

        let price_min = decimal::min(&price_oracle, &price_pool);
        let price_max = decimal::max(&price_oracle, &price_pool);
        debug::print(&price_min);
        debug::print(&price_max);

        let concentration = decimal::div(&price_min, &price_max);

        let price_bid = decimal::mul(&price_pool, &concentration);
        let price_ask = decimal::div(&price_pool, &concentration);
        debug::print(&price_bid);
        debug::print(&price_ask);


        let y_bid = decimal::sub(&y_before_swap, &decimal::div(&delta_x, &price_bid));
        let y_ask = decimal::sub(&y_before_swap, &decimal::div(&delta_x, &price_ask));
        let y_uni = decimal::div(&decimal::div(&constant_k, &slack_mu), &x_after_swap);
        let y_after_swap = decimal::max(&decimal::max(&y_bid, &y_ask), &y_uni);
        debug::print(&y_bid);
        debug::print(&y_ask);
        debug::print(&y_uni);
        debug::print(&y_after_swap);

        let delta_y_and_fee = decimal::sub(&y_after_swap, &y_before_swap);
        let y_fee = decimal::mul(&delta_y_and_fee, &fee_rate);
        let delta_y = decimal::sub(&delta_y_and_fee, &y_fee);

        debug::print(&y_fee);
        debug::print(&delta_y);
    }
}
