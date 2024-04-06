use near_sdk::{
    env, near_bindgen, AccountId, Balance, Promise, PromiseResult, StorageUsage,
};
use near_sdk::collections::UnorderedMap;
use near_sdk::json_types::{U128, ValidAccountId};
use near_sdk::serde::{Deserialize, Serialize};
use borsh::BorshSerialize;

#[near_bindgen]
#[derive(BorshSerialize)]
pub struct Game {
    player: AccountId,
    wager: Balance,
    count: u8,
    tokens: [AccountId; 2], // Replace with actual token IDs if needed
    game_data: Vec<u8>,
    result: Option<GameResult>, // Added to store game result
}

#[near_bindgen]
#[derive(BorshSerialize)]
pub enum GameResult {
    Win(Vec<U128>),
    Lose,
}

#[derive(Serialize, Deserialize)]
pub enum GameAction {
    Bet,
    Refund,
}

#[near_bindgen]
#[derive(Default, BorshDeserialize, BorshSerialize)]
pub struct CoinFlip {
    games: UnorderedMap<u64, Game>,
    win_multiplier: u128,
    house_edge: u64,
}

#[near_bindgen]
impl CoinFlip {
    #[init]
    pub fn new(win_multiplier: u128, house_edge: u64) -> Self {
        assert!(win_multiplier >= 1_000_000_000_000_000_000, "Win multiplier too low");
        assert!(house_edge >= 0, "House edge too low");

        Self {
            games: UnorderedMap::new(b"g".to_vec()),
            win_multiplier,
            house_edge,
        }
    }

    #[payable]
    pub fn play(&mut self, action: GameAction, request_id: Option<u64>, count: Option<u8>, wager: Option<U128>, stop_gain: Option<U128>, stop_loss: Option<U128>, game_data: Option<Vec<u8>>, tokens: Option<[ValidAccountId; 2]>) -> Promise {
        let caller = env::predecessor_account_id();

        match action {
            GameAction::Bet => {
                assert!(count.is_some() && wager.is_some(), "Missing bet parameters");
                let count = count.unwrap();
                let wager = wager.unwrap().0;
                assert!(count > 0, "Count should be greater than zero");

                let game = Game {
                    player: caller.clone(),
                    wager,
                    count,
                    tokens: tokens.unwrap_or(["".to_string(), "".to_string()]), // Handle optional tokens
                    game_data: game_data.unwrap_or_vec!(),
                    result: None, // Initialize result as None
                };

                let request_id = env::random_seed();
                self.games.insert(&request_id, &game);

                // Logic for handling the bet (call backend for user validation and potentially store bet details)
                env::log(format!("User {} placed a bet with request ID {}", caller, request_id).as_bytes());
                Promise::new(caller).transfer(0) // Replace with logic to interact with backend
            }
            GameAction::Refund => {
                let request_id = request_id.unwrap();
                let game_info = self.games.get(&request_id).expect("Game not found");

                assert_eq!(game_info.player, caller, "Only the player can refund the game");

                // Logic for refunding the game (potentially call backend to update user balance)
                env::log(format!("User {} refunded game with request ID {}", caller, request_id).as_bytes());
                self.games.remove(&request_id);
                Promise::new(caller).transfer(game_info.wager) // Replace with logic to interact with backend
            }
        }
    }

    // Function to process game results after backend interaction (ideally called asynchronously)
    pub fn process_game_result(&mut self, request_id: u64, is_win: bool, win_amounts: Option<Vec<U128>>) {
        let mut game = self.games.get(&request_id).expect("Game not found");

        let result = if is_win {
            game.wager *= self.win_multiplier / 1_000_000_000_000_000_000; // Calculate winnings
            if let Some(win_amounts) = win_amounts {
                game.result = Some(GameResult::Win(win_amounts));
            } else {
                panic!("Missing win amounts for winning game");
            }
            Some(GameResult::Win(win_amounts))
        } else {
            game.result = Some(GameResult::Lose);
            None
        };

        // Logic to update user balance and potentially store game history (call backend with game details)
        let user_id = game.player.to_string(); // Assuming conversion to user ID
        let wager = game.wager;
        let winnings = result.map(|r| r.as_ref().unwrap()[0]).unwrap_or(0); // Extract winnings if win

        let backend_response = near_sdk::json_types::to_vec(&backend_update_game(user_id, wager, winnings));
        env::log(backend_response.as_slice());

        self.games.insert(&request_id, &game);
    }

    fn backend_update_game(&self, user_id: String, wager: Balance, winnings: Balance) -> bool {
        // Replace with actual backend interaction logic using a suitable library like reqwest
        // This is a placeholder function that simulates a successful backend call
        env::log(format!("Simulating backend update for user: {}, wager: {}, winnings: {}", user_id, wager, winnings).as_bytes());
        true
    }
}
