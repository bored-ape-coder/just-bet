use near_sdk::{near_bindgen};
use borsh::BorshSerialize;


#[near_bindgen]
#[derive(BorshSerialize)]
pub struct Counter {
    value: u32,
}

impl Counter {
    // Constructor
    pub fn new(value: u32) -> Self {
        Self { value }
    }

    // Method to increment the counter
    pub fn increment(&mut self) {
        self.value += 1;
    }

    // Method to decrement the counter
    pub fn decrement(&mut self) {
        self.value -= 1;
    }

    // Method to get the current value of the counter
    pub fn get(&self) -> u32 {
        self.value
    }


}
fn main() {}
