use near_sdk::{borsh::{self, BorshDeserialize, BorshSerialize}, Promise};
use std::collections::HashMap;
use near_sdk::{env, near_bindgen};

#[near_bindgen]
#[derive(BorshDeserialize, BorshSerialize)]
pub struct CoinFlip {
    results: HashMap<String, u32>, // Stores player address and their win count
    total_wagered: u128,           // Tracks total NEAR deposited for all flips
}

impl Default for CoinFlip {
  fn default() -> Self {
    Self {
      results: HashMap::new(),
      total_wagered: 0,
    }
  }
}

#[near_bindgen]
impl CoinFlip {
    #[init]
    pub fn new() -> Self {
        Self::default()
    }

    #[payable]
    pub fn flip_coin(&mut self, guess: String) -> String {
        let account_id = env::predecessor_account_id();
        let deposit = env::attached_deposit();

        // Ensure minimum deposit for playing (1 NEAR)
        assert!(deposit >= 1_000_000_000_000_000_000_000, "Attach at least 1 NEAR to play");

        let random_byte = env::random_seed()[0];
        let outcome = if random_byte % 2 == 0 { "Heads".to_string() } else { "Tails".to_string() };

        let win_message = format!("You guessed {}. The coin landed on {}", guess, outcome);
        let lose_message = format!("You guessed {}. The coin landed on {}", guess, outcome);

        if guess == outcome {
            // Calculate payout (double deposit)
            let payout = deposit * 2;
        
            // Update total wagered
            self.total_wagered += deposit as u128;
            Promise::new(account_id).transfer(payout);
            // Transfer payout to player using env::transfer_short
            // env::transfer_short(payout as u128).unwrap(); // Handle potential errors
        
            win_message
        } else {
            // Update total wagered
            self.total_wagered += deposit as u128;
        
            lose_message
        }
    }

    pub fn get_wins(&self, account_id: String) -> u32 {
        let wins = *self.results.get(&account_id).unwrap_or(&0);
        wins
    }

    // Consider adding a view function to get total wagered for transparency
    pub fn get_total_wagered(&self) -> u128 {
        self.total_wagered
    }
}
fn main() {}