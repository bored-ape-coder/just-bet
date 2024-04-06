use near_sdk::{env, near_bindgen, borsh::{self, BorshDeserialize, BorshSerialize}};
use near_sdk::collections::Vector;

#[near_bindgen]
#[derive(Default, BorshDeserialize, BorshSerialize)]
pub struct NumberHelper;

#[near_bindgen]
impl NumberHelper {
    pub fn modNumber(&self, _number: u128, _mod: u32) -> u128 {
        if _mod > 0 {
            _number % (_mod as u128)
        } else {
            _number
        }
    }

    pub fn modNumbers(&self, _numbers: Vec<u128>, _mod: u32) -> Vec<u128> {
        _numbers.iter().map(|num| self.modNumber(*num, _mod)).collect()
    }
}
