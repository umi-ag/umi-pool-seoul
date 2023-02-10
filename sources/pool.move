module umi_pool::pool {
    use std::signer;
    use aptos_std::type_info;
    use aptos_framework::coin;

    use umi_pool::decimal::{Self, Decimal};
    use umi_pool::coin_list::{Self, USDI, mint, mint_to_wallet, check_and_deposit};

    const MODULE_ADMIN: address = @umi_pool;

    const ERROR_NOT_CREATOR: u64 = 2;
    const ERROR_INSUFFICIENT_AMOUNT: u64 = 6;

    struct Pot<phantom X> has key {
        reserve: coin::Coin<X>,
        price: Decimal,
        weight: Decimal,
        min_weight: Decimal,
        fee: Decimal,
        rebate: Decimal,
    }

    public entry fun init_pot<X>(admin: &signer)
    {
        assert!(signer::address_of(admin) == MODULE_ADMIN, ERROR_NOT_CREATOR);
        let pot = Pot<X> {
            reserve: coin::zero<X>(),
            price: decimal::zero(),
            weight: decimal::zero(),
            min_weight: decimal::zero(),
            fee: decimal::zero(),
            rebate: decimal::zero(),
        };
        move_to<Pot<X>>(admin, pot);
    }

    public entry fun set_config_pot<X>(
        admin: &signer,
        weight: u64,
        min_weight: u64,
        fee: u64,
        rebate: u64,
    )
    acquires Pot
    {
        assert!(signer::address_of(admin) == MODULE_ADMIN, ERROR_NOT_CREATOR);
        let pot = borrow_global_mut<Pot<X>>(MODULE_ADMIN);
        pot.weight = decimal::new((weight as u128), 6, false);
        pot.min_weight = decimal::new((min_weight as u128), 6, false);
        pot.fee = decimal::new((fee as u128), 6, false);
        pot.rebate = decimal::new((rebate as u128), 6, false);
    }

    fun deposit<X>(pot: &mut Pot<X>, coin_in: coin::Coin<X>)
    {
        coin::merge(&mut pot.reserve, coin_in);
    }

    fun extract<X>(pot: &mut Pot<X>, amount: u64): coin::Coin<X>
    {
        assert!(amount <= coin::value(&pot.reserve), ERROR_INSUFFICIENT_AMOUNT);
        coin::extract(&mut pot.reserve, amount)
    }

    fun withdraw<X>(pot: &mut Pot<X>, to: address, amount: u64)
    {
        let coin_x = extract<X>(pot, amount);
        coin::deposit<X>(to, coin_x);
    }

    public fun curve(
        delta_x: Decimal,
        reserve_x: &Decimal,
        reserve_y: &Decimal,
        price_x: &Decimal,
        price_y: &Decimal,
        weight_x: Decimal,
        weight_y: Decimal,
        min_weight_x: Decimal,
        fee: Decimal,
        rebate: Decimal,
    ): Decimal
    {
        let adj_price_x = decimal::div(price_x, &weight_x);
        let adj_price_y = decimal::div(price_y, &weight_y);

        let delta_rho_x = decimal::mul(&decimal::div(price_x, &weight_x), &delta_x);
        let rho_x0 = decimal::mul(&adj_price_x, reserve_x);
        let rho_y0 = decimal::mul(&adj_price_y, reserve_y);
        let rho_x1 = decimal::add(&rho_x0, &delta_rho_x);

        let one_sub_fee = decimal::sub(&decimal::one(), &fee);

        let m =  decimal::div(&min_weight_x, &weight_x);

        // sqrt(k/m)
        let sqrt_km = decimal::div(
            &decimal::add(
                &decimal::mul(
                    &one_sub_fee,
                    &rho_x0,
                ),
                &rho_y0,
            ),
            &decimal::add(
                &one_sub_fee,
                &m
            )
        );

        let delta_rho_y = if (decimal::lt(&rho_x1, &rho_y0)) {
            decimal::mul(
                &one_sub_fee,
                &delta_rho_x,
            )
        } else if (decimal::lt(&rho_x1, &sqrt_km)) {
            decimal::mul(
                &decimal::add(&one_sub_fee, &rebate),
                &delta_rho_x,
            )
        } else {
            let k = decimal::mul(&m, &decimal::mul(&sqrt_km, &sqrt_km));
            decimal::sub(
                &rho_y0,
                &decimal::div(
                    &k,
                    &decimal::add(
                        &rho_x0,
                        &decimal::mul(&one_sub_fee, &delta_rho_x)
                    )
                )
            )
        };

        let delta_y = decimal::div(&delta_rho_y, &adj_price_y);

        delta_y
    }

    public fun fetch_price_USDI(): Decimal
    {
        decimal::new(114, 1, false)
    }

    public fun fetch_price_oracle<X>(): Decimal
    {
        decimal::new(114, 1, false)
    }

    public entry fun swap_script<X, Y>(
        sender: &signer,
        amount_in: u64,
    )
    acquires Pot
    {
        if (type_info::type_name<X>() == type_info::type_name<USDI>()) {
            burn_u_to_x<X, Y>(sender, amount_in);
        } else if (type_info::type_name<Y>() == type_info::type_name<USDI>()) {
            mint_x_to_u<X, Y>(sender, amount_in);
        } else {
            swap_x_to_y<X, Y>(sender, amount_in);
        }
    }

    public fun swap_direct<X, Y>(
        coin_in: coin::Coin<X>,
    ) : coin::Coin<Y>
    acquires Pot
    {
        if (type_info::type_name<X>() == type_info::type_name<USDI>()) {
            burn_u_to_x_direct<X, Y>(coin_in)
        } else if (type_info::type_name<Y>() == type_info::type_name<USDI>()) {
            mint_x_to_u_direct<X, Y>(coin_in)
        } else {
            swap_x_to_y_direct<X, Y>(coin_in)
        }
    }

    // Alice swaps X->Y
    public fun swap_x_to_y<X, Y>(
        sender: &signer,
        amount_in: u64,
    )
    acquires Pot
    {
        let (delta_x, delta_y) = swap_x_to_y_inner<X, Y>(amount_in);

        let pot_x_mut = borrow_global_mut<Pot<X>>(MODULE_ADMIN);
        let coin_in = coin::withdraw<X>(sender, decimal::to_u64(delta_x));
        deposit<X>(pot_x_mut, coin_in);

        let pot_y_mut = borrow_global_mut<Pot<Y>>(MODULE_ADMIN);
        let coin_out = extract<Y>(pot_y_mut, decimal::to_u64(delta_y));
        check_and_deposit(sender, coin_out);
    }

    // Alice swaps X->Y
    public fun swap_x_to_y_direct<X, Y>(
        coin_in: coin::Coin<X>,
    ) : coin::Coin<Y>
    acquires Pot
    {
        let amount_in = coin::value(&coin_in);
        let (_delta_x, delta_y) = swap_x_to_y_inner<X, Y>(amount_in);

        let pot_x_mut = borrow_global_mut<Pot<X>>(MODULE_ADMIN);
        deposit<X>(pot_x_mut, coin_in);

        let pot_y_mut = borrow_global_mut<Pot<Y>>(MODULE_ADMIN);
        let coin_out = extract<Y>(pot_y_mut, decimal::to_u64(delta_y));

        coin_out
    }

    // Alice swaps X->Y
    public fun swap_x_to_y_inner<X, Y>(
        amount_in: u64,
    ): (Decimal, Decimal)
    acquires Pot
    {
        let price_x = fetch_price_oracle<X>();
        let price_y = fetch_price_oracle<Y>();

        let fee = decimal::new(3, 3, false);
        let rebate = decimal::new(1, 3, false);
        let delta_x = decimal::from_u64(amount_in);

        let pot_x = borrow_global<Pot<X>>(MODULE_ADMIN);
        let pot_y = borrow_global<Pot<Y>>(MODULE_ADMIN);

        let reserve_x = &decimal::from_u64(coin::value<X>(&pot_x.reserve));
        let reserve_y = &decimal::from_u64(coin::value<Y>(&pot_y.reserve));

        let price_x = &price_x;
        let price_y = &price_y;

        let weight_x = decimal::new(10, 2, false);
        let min_weight_x = decimal::new(1, 2, false);
        let weight_y = decimal::new(20, 2, false);

        let delta_y = curve(
            delta_x,
            reserve_x,
            reserve_y,
            price_x,
            price_y,
            weight_x,
            weight_y,
            min_weight_x,
            fee,
            rebate,
        );

        (delta_x, delta_y)
    }

    // Alice swaps X->U, mint U
    public entry fun mint_x_to_u<X, U>(
        sender: &signer,
        amount_in: u64,
    )
    acquires Pot
    {
        let (_delta_x, delta_u) = mint_x_to_u_inner<X, U>(amount_in);
        let coin_in = coin::withdraw<X>(sender, amount_in);

        let pot = borrow_global_mut<Pot<X>>(MODULE_ADMIN);
        deposit<X>(pot, coin_in);
        mint_to_wallet<U>(sender, decimal::to_u64(delta_u));
    }

    // Alice swaps X->U, mint U
    public entry fun mint_x_to_u_direct<X, U>(
        coin_in: coin::Coin<X>,
    ): coin::Coin<U>
    acquires Pot
    {
        let amount_in = coin::value(&coin_in);
        let (_delta_x, delta_u) = mint_x_to_u_inner<X, U>(amount_in);

        let pot = borrow_global_mut<Pot<X>>(MODULE_ADMIN);
        deposit<X>(pot, coin_in);
        let coin_out = mint<U>(decimal::to_u64(delta_u));
        coin_out
    }

    // Alice swaps X->U, mint U
    public entry fun mint_x_to_u_inner<X, U>(
        amount_in: u64,
    ): (Decimal, Decimal)
    {
        let fee = decimal::new(3, 3, false);
        let price_u = fetch_price_USDI();
        let price_x = fetch_price_oracle<X>();

        let delta_x = decimal::from_u64(amount_in);

        // delta_u = (1-mu) * price_x / price_mint_usdi * delta_x
        let delta_u = decimal::mul(
            &decimal::div(&price_x, &price_u),
            &decimal::mul(
                &decimal::sub(&decimal::one(), &fee),
                &delta_x,
            ),
        );

        (delta_x, delta_u)
    }

    // operation U->X: burn U
    public entry fun burn_u_to_x<U, X>(
        sender: &signer,
        amount_in: u64,
    )
    acquires Pot
    {
        let coin_in = coin::withdraw<U>(sender, amount_in);
        coin_list::burn(coin_in);
        let (_delta_u, delta_x) = burn_u_to_x_inner<U, X>(amount_in);

        let pot = borrow_global_mut<Pot<X>>(MODULE_ADMIN);
        let coin_out = extract<X>(pot, decimal::to_u64(delta_x));
        check_and_deposit(sender, coin_out);
    }

    // operation U->X: burn U
    public entry fun burn_u_to_x_direct<U, X>(
        coin_in: coin::Coin<U>,
    ): coin::Coin<X>
    acquires Pot
    {
        let amount_in = coin::value(&coin_in);
        coin_list::burn(coin_in);
        let (_delta_u, delta_x) = burn_u_to_x_inner<U, X>(amount_in);

        let pot = borrow_global_mut<Pot<X>>(MODULE_ADMIN);
        let coin_out = extract<X>(pot, decimal::to_u64(delta_x));
        coin_out
    }

    // operation U->X: burn U
    public entry fun burn_u_to_x_inner<U, X>(
        amount_in: u64,
    ): (Decimal, Decimal)
    {
        let fee = decimal::new(3, 3, false);
        let price_u = fetch_price_USDI();
        let price_x = fetch_price_oracle<X>();

        let delta_u = decimal::from_u64(amount_in);

        // delta_u = (1-mu) * price_mint_usdi / price_x * delta_x
        let delta_x = decimal::mul(
            &decimal::div(&price_u, &price_x),
            &decimal::mul(
                &decimal::sub(&decimal::one(), &fee),
                &decimal::from_u64(amount_in),
            ),
        );

        (delta_u, delta_x)
    }
}