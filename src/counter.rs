// Import necessary modules from the NEAR SDK
use near_sdk::{env, near_bindgen};

// Define the smart contract structure
#[near_bindgen]
#[derive(Default, BorshDeserialize, BorshSerialize)]
pub struct Counter {
    value: u32,
}

// Implement methods for the smart contract
#[near_bindgen]
impl Counter {
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
