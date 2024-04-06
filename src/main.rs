#![allow(non_snake_case)]

struct NumberHelper;

impl NumberHelper {
    fn modNumber(_number: u128, _mod: u32) -> u128 {
        if _mod > 0 {
            _number % (_mod as u128)
        } else {
            _number
        }
    }

    fn modNumbers(_numbers: Vec<u128>, _mod: u32) -> Vec<u128> {
        let mut modNumbers_: Vec<u128> = Vec::new();

        for num in _numbers {
            modNumbers_.push(Self::modNumber(num, _mod));
        }

        modNumbers_
    }
}

fn main() {
    let numbers = vec![1, 2, 3, 4, 5, 6, 7, 8, 9];
    let modulus: u32 = 3;

    let mod_numbers = NumberHelper::modNumbers(numbers, modulus);
    println!("{:?}", mod_numbers);
}
