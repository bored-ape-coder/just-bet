#![allow(unused_imports)] // Suppress warnings about unused imports

use near_sdk::{env, near_bindgen, Promise};
use near_sdk::serde as near_serde; // Use near_serde for compatibility

// Import necessary attributes
use near_sdk::init;

#[derive(near_serde::Serialize, near_serde::Deserialize)]
#[serde(crate = "near_sdk::serde")]
#[derive(PartialEq)] // Add this line
pub enum CoinFlipResult {
    Heads,
    Tails,
}

#[derive(near_serde::Serialize, near_serde::Deserialize)]
#[serde(crate = "near_sdk::serde")]
#[near_bindgen]
pub struct CoinFlip {
    player: String,
    bet: u128,
    num_flips: u8,
    results: Vec<CoinFlipResult>,
    winnings: u128,
}


#[near_bindgen]
impl CoinFlip {
    #[init]
    pub fn new() -> Self {
        Self {
            player: env::predecessor_account_id(),
            bet: 0,
            num_flips: 0,
            results: vec![],
            winnings: 0,
        }
    }

    #[payable]
    pub fn play_multiple(&mut self, guess: CoinFlipResult, num_flips: u8) -> Promise {
        let attached_deposit = env::attached_deposit();

        if attached_deposit <= 0 {
            env::panic(b"Attach some NEAR tokens to play.");
        }

        let min_bet = 100;
        if attached_deposit < min_bet * num_flips as u128 {
            env::panic(b"Minimum bet is 100 NEAR per flip.");
        }

        if num_flips == 0 || num_flips > 10 {
            env::panic(b"Number of flips must be between 1 and 10.");
        }

        self.bet = attached_deposit;
        self.player = env::predecessor_account_id();
        self.num_flips = num_flips;

        let random_seed = env::random_seed();

        let mut results = Vec::with_capacity(num_flips as usize);
        for _ in 0..num_flips {
            let first_byte = random_seed.get(0).expect("Failed to get first byte");
            // let first_byte = random_seed.as_ref()[0] as u8; // Extract first byte as u8
            let dom_value = first_byte % 2;
            results.push(if dom_value == 0 { CoinFlipResult::Heads } else { CoinFlipResult::Tails });
        }

        let mut winnings = 0;
        for result in &results {
            if *result == CoinFlipResult::Heads {
                winnings += self.bet / num_flips as u128;
            } else if *result == CoinFlipResult::Tails {
                winnings += self.bet / num_flips as u128;
            }
        }

        self.results = results;
        self.winnings = winnings;

        Promise::new(env::current_account_id()).transfer(winnings)
    }

    pub fn get_results(&self) -> Option<&Vec<CoinFlipResult>> {
        Some(&self.results)
    }

    pub fn get_winnings(&self) -> u128 {
        self.winnings
    }
}

fn main() {} // Optional for testing purposes
