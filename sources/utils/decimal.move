// https://github.com/switchboard-xyz/switchboard-aptos-public/blob/main/switchboard/sources/utils/math.move

module umi_pool::decimal {
    use std::vector;

    use u256::u256;

    use umi_pool::vec_utils;
    use umi_pool::math;

    const ERR_INCORRECT_STD_DEV: u64 = 0;
    const ERR_NO_LENGTH_PASSED_IN_STD_DEV: u64 = 1;
    const ERR_MORE_THAN_9_DECIMALS: u64 = 2;
    const ERR_INPUT_TOO_LARGE: u64 = 3;

    const MAX_DECIMALS: u8 = 9;
    const POW_10_TO_MAX_DECIMALS: u128 = 1000000000;
    const U128_MAX: u128 = 340282366920938463463374607431768211455;
    const MAX_VALUE_ALLOWED: u128 = 340282366920938463463374607431;

    #[derive(Debug)]
    struct Decimal has copy, drop, store {
        value: u128,
        dec: u8,
        neg: bool
    }

    public fun max_u128(): u128 {
        U128_MAX
    }

    public fun new(value: u128, dec: u8, neg: bool): Decimal {
        assert!(
            dec <= MAX_DECIMALS,
            ERR_MORE_THAN_9_DECIMALS
        );
        let num = Decimal { value, dec, neg };

        // expand nums out
        num.value = scale_to_decimals(&num, MAX_DECIMALS);
        num.dec = MAX_DECIMALS;

        num
    }

    public fun get_decimals(value: &Decimal): u8 {
        value.dec
    }

    public fun from_u64(value: u64): Decimal {
        new((value as u128), 0, false)
    }

    public fun from_u128(value: u128): Decimal {
        new(value, 0, false)
    }

    public fun to_u128(num: Decimal): u128 {
        if (num.neg) {
            0
        } else {
            num.value / (math::expand_to_decimals(1, num.dec) as u128)
        }
    }

    public fun to_u64(num: Decimal): u64 {
        (to_u128(num) as u64)
    }

    public fun abs(num: &Decimal): Decimal {
        new(num.value, num.dec, false)
    }

    public fun pow(base: u64, exp: u8): u128 {
        let result_val = 1u128;
        let i = 0;
        while (i < exp) {
            result_val = result_val * (base as u128);
            i = i + 1;
        };
        result_val
    }

    public fun pow_10(exp: u8): u128 {
        pow(10, exp)
    }

    public fun unpack(num: Decimal): (u128, u8, bool) {
        let Decimal { value, dec, neg } = num;
        (value, dec, neg)
    }

    // abs(a - b)
    fun sub_abs_u8(a: u8, b: u8): u8 {
        if (a > b) {
            a - b
        } else {
            b - a
        }
    }

    public fun zero(): Decimal {
        new(0, 0, false)
    }

    public fun one(): Decimal {
        new(1, 0, false)
    }

    public fun is_zero(a: &Decimal): bool {
        a.value == 0
    }

    public fun is_positive(a: &Decimal): bool {
        !a.neg && !is_zero(a)
    }

    public fun is_negative(a: &Decimal): bool {
        a.neg && !is_zero(a)
    }

    // TODO: get weighted median
    public fun median(v: &vector<Decimal>): Decimal {
        let v = sort(v);
        *vector::borrow(&v, vector::length(&v) / 2)
    }

    public fun median_mut(v: &mut vector<Decimal>): Decimal {
        let size = vector::length(v);
        little_floyd_rivest(v, size / 2, 0, size - 1)
    }

    public fun std_deviation(medians: &vector<Decimal>, median: &Decimal): Decimal {
        assert!(vector::length(medians) > 0, 0);
        *median
    }

    public fun sort(v: &vector<Decimal>): vector<Decimal> {
        let size = vector::length(v);
        let alloc = vector::empty();
        if (size <= 1) {
            return *v
        };

        let (left, right) = vec_utils::esplit(v);
        let left = sort(&left);
        let right = sort(&right);


        loop {
            let left_len = vector::length<Decimal>(&left);
            let right_len = vector::length<Decimal>(&right);
            if (left_len != 0 && right_len != 0) {
                // TODO: play with reversing to switch remove with pop_back
                if (gt(vector::borrow<Decimal>(&right, 0), vector::borrow<Decimal>(&left, 0))) {
                   vector::push_back<Decimal>(&mut alloc, vector::remove<Decimal>(&mut left, 0));
                } else {
                    vector::push_back<Decimal>(&mut alloc, vector::remove<Decimal>(&mut right, 0));
                }
            } else if (left_len != 0) {
                vector::push_back<Decimal>(&mut alloc, vector::remove<Decimal>(&mut left, 0));
            } else if (right_len != 0) {
                vector::push_back<Decimal>(&mut alloc, vector::remove<Decimal>(&mut right, 0));
            } else {
                return alloc
            };
        }
    }

    // By reference

    fun abs_gt(val1: &Decimal, val2: &Decimal): bool {
        val1.value > val2.value
    }

    fun abs_lt(val1: &Decimal, val2: &Decimal): bool {
        val1.value < val2.value
    }

    public fun add(val1: &Decimal, val2: &Decimal): Decimal {
        let out = zero();
        // -x + -y
        if (val1.neg && val2.neg) {
            add_internal(val1, val2, &mut out);
            out.neg = true;

        // -x + y
        } else if (val1.neg) {
            sub_internal(val2, val1, &mut out);

        // x + -y
        } else if (val2.neg) {
            sub_internal(val1, val2, &mut out);

        // x + y
        } else {
            add_internal(val1, val2, &mut out);
        };
        out
    }

    fun add_internal(val1: &Decimal, val2: &Decimal, out: &mut Decimal) {
        out.value = val1.value + val2.value;
        out.dec = MAX_DECIMALS;
        out.neg = false;
    }

    public fun sub(val1: &Decimal, val2: &Decimal): Decimal {
        let out = zero();
        // -x - -y
        if (val1.neg && val2.neg) {
            add_internal(val1, val2, &mut out);
            out.neg = abs_gt(val1, val2);

        // -x - y
        } else if (val1.neg) {
            add_internal(val1, val2, &mut out);
            out.neg = true;

        // x - -y
        } else if (val2.neg) {
            add_internal(val1, val2, &mut out);

         // x - y
        } else {
            sub_internal(val1, val2, &mut out);
        };
        out
    }

    fun sub_internal(val1: &Decimal, val2: &Decimal, out: &mut Decimal) {
        if (val2.value > val1.value) {
            out.value = (val2.value - val1.value);
            out.dec = MAX_DECIMALS;
            out.neg = true;
        } else {
            out.value = (val1.value - val2.value);
            out.dec = MAX_DECIMALS;
            out.neg = false;
        };
    }

    public fun mul(val1: &Decimal, val2: &Decimal): Decimal {
        let out = one();
        let neg = !((val1.neg && val2.neg) || (!val1.neg && !val2.neg));
        mul_internal(val1, val2, &mut out);
        out.neg = neg;
        out
    }

    fun mul_internal(val1: &Decimal, val2: &Decimal, out: &mut Decimal) {
        let multiplied = val1.value * val2.value;
        let new_decimals = val1.dec + val2.dec;
        let multiplied_scaled = if (new_decimals < MAX_DECIMALS) {
            let decimals_underflow = MAX_DECIMALS - new_decimals;
            multiplied * pow_10(decimals_underflow)
        } else if (new_decimals > MAX_DECIMALS) {
            let decimals_overflow = new_decimals - MAX_DECIMALS;
            multiplied / pow_10(decimals_overflow)
        } else {
            multiplied
        };

        out.value = multiplied_scaled;
        out.dec = MAX_DECIMALS;
        out.neg = false;
    }

    public fun div(a: &Decimal, b: &Decimal): Decimal {
        let neg = !((a.neg && b.neg) || (!a.neg && !b.neg));
        let num = new(
            a.value * pow_10(b.dec) / b.value,
            a.dec - b.dec,
            neg,
        );
        num.value = num.value / POW_10_TO_MAX_DECIMALS;
        num
    }

    public fun sqrt(num: &Decimal): Decimal {
        let out = zero();
        let y = num;

        // z = y
        out.value = y.value;
        out.neg = y.neg;
        out.dec = y.dec;
        out
    }

    public fun normalize(num: &mut Decimal) {
        while (num.value % 10 == 0 && num.dec > 0) {
            num.value = num.value / 10;
            num.dec = num.dec - 1;
        };
    }


    public fun gt(val1: &Decimal, val2: &Decimal): bool {
        if (val1.neg && val2.neg) {
            return val1.value < val2.value
        } else if (val1.neg) {
            return false
        } else if (val2.neg) {
            return true
        };
        val1.value > val2.value
    }

    public fun lt(val1: &Decimal, val2: &Decimal): bool {
       if (val1.neg && val2.neg) {
            return val1.value > val2.value
        } else if (val1.neg) {
            return true
        } else if (val2.neg) {
            return false
        };
        val1.value < val2.value
    }

    public fun max(a: &Decimal, b: &Decimal): Decimal {
        if (gt(a, b)) *a else *b
    }

    public fun min(a: &Decimal, b: &Decimal): Decimal {
        if (gt(a, b)) *b else *a
    }

    public fun equal(val1: &Decimal, val2: &Decimal): bool {
        let num1 = scale_to_decimals(val1, MAX_DECIMALS);
        let num2 = scale_to_decimals(val2, MAX_DECIMALS);
        num1 == num2 && val1.neg == val2.neg
    }

    public fun scale_to_decimals(num: &Decimal, scale_dec: u8): u128 {
        if (num.dec < scale_dec) {
            return (num.value * pow_10(scale_dec - num.dec))
        } else {
            return (num.value / pow_10(num.dec - scale_dec))
        }
    }

    public fun expand_to_decimals(num: &Decimal, decimals: u8): Decimal {
        new(
            num.value * pow_10(decimals),
            num.dec,
            num.neg
        )
    }

    public fun little_floyd_rivest(vec: &mut vector<Decimal>, k: u64, left: u64, right: u64): Decimal {
        let size = vector::length<Decimal>(vec);
        assert!(size < 600 && left + right == 0, ERR_INPUT_TOO_LARGE);
        *vector::borrow(vec, k)
    }

    #[test]
    fun test_equal() {
        let a = new(1234, 0, false);
        let b = new(12340, 1, false);

        assert!(equal(&a, &b), 0);
    }

    #[test]
    fun test_add() {
        let a = new(1234, 1, false);
        let b = new(12340, 2, false);
        let c = new(246800, 3, false);

        assert!(equal(&add(&a, &b), &c), 0);
    }

    #[test]
    fun test_mul() {
        let price = new(200, 2, false);
        let amount = new(300, 3, false);
        let value = mul(&price, &amount);
        let expected = new(6, 1, false);

        assert!(equal(&value, &expected), 0);
    }

    #[test]
    fun test_div() {
        let dx = new(2, 0, false);
        let dy = new(1333, 3, false);
        let value = div(&dx, &dy);
        let expected = new(1500375093, 9, false);
        assert!(equal(&value, &expected), 0);

        let dx = new(1, 0, false);
        let dy = new(3, 0, false);
        let value = div(&dx, &dy);
        let expected = new(333333333, 9, false);
        assert!(equal(&value, &expected), 0);

        let dx = new(1, 0, true);
        let dy = new(1, 0, false);
        let value = div(&dx, &dy);
        let expected = new(1, 0, true);
        assert!(equal(&value, &expected), 0);

        let dx = new(1, 0, false);
        let dy = new(1, 0, true);
        let value = div(&dx, &dy);
        let expected = new(1, 0, true);
        assert!(equal(&value, &expected), 0);

        let dx = new(1, 0, true);
        let dy = new(1, 0, true);
        let value = div(&dx, &dy);
        let expected = new(1, 0, false);
        assert!(equal(&value, &expected), 0);

        let price_oracle = new(1000, 3, false);
        let value = div(&one(), &price_oracle);
        let expected = new(1000000000, 9, false);
        assert!(equal(&value, &expected), 0);
    }

    #[test]
    fun test_min() {
        let a = new(200, 2, false);
        let b = new(300, 3, false);

        assert!(equal(&min(&a, &b), &b), 0);
        assert!(equal(&max(&a, &b), &a), 1);
    }

    #[test]
    fun test_is_negative() {
        let a = new(100, 2, false);
        assert!(!is_negative(&a), 0);

        let a = new(0, 0, false);
        assert!(!is_negative(&a), 1);

        let a = new(0, 0, true);
        assert!(!is_negative(&a), 2);

        let a = new(100, 3, true);
        assert!(is_negative(&a), 3);
    }

    #[test]
    fun test_to_u64() {
        let a = new(234, 1, false);
        assert!(to_u64(a) == 23, 0);

        let a = new(234, 1, true);
        assert!(to_u64(a) == 0, 1);

        let a = abs(&new(234, 1, true));
        assert!(to_u64(a) == 23, 0);
    }

    #[test]
    fun test_to_u256() {
        use std::debug;
        use u256::u256;
        let a = u256::from_u128(10);
        let b = u256::from_u64(10);

        let c = u256::add(a, b);
        let z = u256::as_u128(c);

        debug::print(&z);
    }

    public fun dev(a: &Decimal, b: &Decimal): Decimal {
        let aa = u256::mul(
            u256::from_u128(a.value),
            u256::from_u128(pow_10(a.dec + b.dec))
        );
        let bb = u256::from_u128(b.value);
        let value = u256::as_u128(
            u256::div(aa, bb)
        );

        let neg = !((a.neg && b.neg) || (!a.neg && !b.neg));
        let num = new(
            value,
            a.dec - b.dec,
            neg,
        );
        num.value = num.value / POW_10_TO_MAX_DECIMALS;
        num
    }

    #[test]
    fun test_dev_u256() {
        use std::debug;

        debug::print(&6666666);
        let a = new(114514, 3, false);
        let b = expand_to_decimals(&one(), 9);

        let r = dev(
            &a, &b
        );

        debug::print(&r);
    }
}