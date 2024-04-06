
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract CoinFlip is CommonSolo {
  /*==================================================== Events ==========================================================*/

  event UpdateHouseEdge(
    uint256 multiplier,
    uint64 houseEdge
  );

  /*==================================================== Modifiers ==========================================================*/

  modifier isChoiceInsideLimits(bytes memory _gameData) {
    uint8 choice_ = decodeGameData(_gameData);

    require(choice_ == 0 || choice_ == 1, "Choice isn't allowed");
    _;
  }

  /*==================================================== State Variables ====================================================*/

  /// @notice contains 2 * 0.98 = 2% house edge
  uint256 public winMultiplier = 196e16;
  /// @notice house edge of game
  uint64 public houseEdge = 200;

  /*==================================================== Functions ===========================================================*/

  constructor(IRandomizerRouter _router) CommonSolo(_router) {}

  /// @notice updates win multiplier
  /// @param _winMultiplier winning multipliplier
  function updateWinMultiplier(uint256 _winMultiplier, uint64 _houseEdge) external onlyGovernance {
    require(_winMultiplier >= 1e18, "_multiplier should be greater than or equal to 1e18");
    require(_houseEdge >= 0, "_houseEdge should be greater than or equal to 0");

    winMultiplier = _winMultiplier;
    houseEdge = _houseEdge;
  
    emit UpdateHouseEdge(_winMultiplier, _houseEdge);
  }

  /// @notice function that calculation or return a constant of house edge
  /// @return edge_ calculated house edge of game
  function getHouseEdge(Game memory) public view override returns (uint64 edge_) {
    edge_ = houseEdge;
  }

  /// @notice encodes choice of player
  /// @param _choice players choice 0 or 1
  function encodeGameData(uint8 _choice) public pure returns (bytes memory) {
    return abi.encode(_choice);
  }

  /// @notice decodes game data
  /// @param _gameData encoded cohice
  /// @return choice_ 0 or 1
  function decodeGameData(bytes memory _gameData) public pure returns (uint8) {
    return abi.decode(_gameData, (uint8));
  }

  /// @notice calculates reward according to winning multiplier
  /// @param _wager players wager for a game
  function calcReward(uint256 _wager) public view returns (uint256 reward_) {
    reward_ = (_wager * winMultiplier) / PRECISION;
  }

  /// @notice makes the decision about choice
  /// @param _choice players choice 0 or 1
  /// @param _result modded random number
  function isWon(uint8 _choice, uint256 _result) public pure returns (bool won_) {
    won_ = (_choice == 1) ? (_result == 1) : (_result == 0);
  }

  /// @notice shares the amount which escrowed amount while starting the game by player 
  /// @param _randoms raw random numbers sent by randomizers
  /// @return numbers_ modded numbers according to game
  function getResultNumbers(
    Game memory,
    uint256[] calldata _randoms
  ) internal pure override returns (
    uint256[] memory numbers_
  ) {
    numbers_ = modNumbers(_randoms, 2);
  }
  
  /// @notice game logic contains here, decision mechanism
  /// @param _game request's game
  /// @param _resultNumbers modded numbers according to game
  /// @param _stopGain maximum profit limit
  /// @param _stopLoss maximum loss limit
  /// @return payout_ _payout accumulated payouts by game contract
  /// @return playedGameCount_  played game count by game contract
  /// @return payouts_ profit calculated at every step of the game, wager excluded 
  function play(
    Game memory _game,
    uint256[] memory _resultNumbers,
    uint256 _stopGain,
    uint256 _stopLoss
  ) public view override returns (
    uint256 payout_, 
    uint32 playedGameCount_, 
    uint256[] memory payouts_
  ) {
    payouts_ = new uint[](_game.count);
    playedGameCount_ = _game.count;

    uint8 choice_ = decodeGameData(_game.gameData);
    uint256 reward_ = calcReward(_game.wager);

    for (uint8 i = 0; i < _game.count; ++i) {
      if (isWon(choice_, _resultNumbers[i])) {
        payouts_[i] = reward_ - _game.wager;
        payout_ += reward_;
      }

      if (shouldStop(payout_, (i + 1) * _game.wager, _stopGain, _stopLoss)) {
        playedGameCount_ = i + 1;
        break;
      }
    }
  }

  /// @notice randomizer consumer triggers that function
  /// @notice manages the game variables and shares the escrowed amount
  /// @param _wager amount for a game 
  /// @param _count the selected game count by player
  /// @param _stopGain maximum profit limit
  /// @param _stopLoss maximum loss limit
  /// @param _gameData players decisions according to game
  /// @param _tokens contains input and output token currencies
  function bet(
    uint256 _wager, 
    uint8 _count,
    uint256 _stopGain,
    uint256 _stopLoss,
    bytes memory _gameData,
    address[2] memory _tokens
  ) external isChoiceInsideLimits(_gameData) {
    _create(
      _wager,
      _count,
      _stopGain,
      _stopLoss,
      _gameData,
      _tokens
    );
  }
}

abstract contract CommonSolo is Core {
  /*==================================================== Events =============================================================*/

  event Created(address indexed player, uint256 requestId, uint256 wager, address[2] tokens);

  event Settled(
    address indexed player,
    uint256 requestId,
    uint256 wager,
    bool won,
    uint256 payout,
    uint32 playedGameCount,
    uint256[] numbers,
    uint256[] payouts
  );

  /*==================================================== Modifiers ==========================================================*/

  modifier isGameCountAcceptable(uint256 _gameCount) {
    require(_gameCount > 0, "Game count out-range");
    require(_gameCount <= maxGameCount, "Game count out-range");
    _;
  }

  modifier isGameCreated(uint256 _requestId) {
    require(games[_requestId].player != address(0), "Game is not created");
    _;
  }

  modifier whenNotCompleted(uint256 _requestId) {
    require(!completedGames[_requestId], "Game is completed");
    completedGames[_requestId] = true;
    _;
  }

  /*==================================================== State Variables ====================================================*/

  struct Game {
    uint8 count;
    address player;
    bytes gameData;
    uint256 wager;
    uint256 startTime;
    address[2] tokens;
  }

  struct Options {
    uint256 stopGain;
    uint256 stopLoss;
  }

  /// @notice maximum selectable game count
  uint8 public maxGameCount = 100;
  /// @notice cooldown duration to refund
  uint32 public refundCooldown = 2 hours; // default value
  /// @notice stores all games
  mapping(uint256 => Game) public games;
  /// @notice stores randomizer request ids game pair
  mapping(uint256 => Options) public options;
  mapping(uint256 => bool) public completedGames;

  /*==================================================== Functions ===========================================================*/

  constructor(IRandomizerRouter _router) Core(_router) {}

  /// @notice updates max game count
  /// @param _maxGameCount maximum selectable count
  function updateMaxGameCount(uint8 _maxGameCount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    maxGameCount = _maxGameCount;
  }

  /// @notice function to update refund block count
  /// @param _refundCooldown duration to refund
  function updateRefundCooldown(uint32 _refundCooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
    refundCooldown = _refundCooldown;
  }

  /// @notice checks the profit and loss amount to stop the game when reaches the limits
  /// @param _total total gain accumulated from all games
  /// @param _wager total wager used
  /// @param _stopGain maximum profit limit
  /// @param _stopLoss maximum loss limit
  function shouldStop(
    uint256 _total,
    uint256 _wager,
    uint256 _stopGain,
    uint256 _stopLoss
  ) public pure returns (bool stop_) {
    if (_stopGain != 0 && _total > _wager) {
      stop_ = _total - _wager >= _stopGain; // total gain >= stop gain
    } else if (_stopLoss != 0 && _wager > _total) {
      stop_ = _wager - _total >= _stopLoss; // total loss >= stop loss
    }
  }

  /// @notice if the game is stopped due to the win and loss limit,
  /// @notice this calculates the unused and used bet amount
  /// @param _count the selected game count by player
  /// @param _usedCount played game count by game contract
  /// @param _wager amount for a game
  function calcWager(
    uint256 _count,
    uint256 _usedCount,
    uint256 _wager
  ) public pure returns (uint256 usedWager_, uint256 unusedWager_) {
    usedWager_ = _usedCount * _wager;
    unusedWager_ = (_count * _wager) - usedWager_;
  }

  /// @notice function to refund uncompleted game wagers
  function refundGame(uint256 _requestId) external nonReentrant whenNotCompleted(_requestId) {
    Game memory game = games[_requestId];
    require(game.player == _msgSender(), "Only player");
    require(
      game.startTime + refundCooldown < block.timestamp,
      "Game is not refundable yet"
    );

    delete games[_requestId];

    vaultManager.refund(game.tokens[0], game.wager * game.count, game.player);
  }

  /// @notice shares the amount which escrowed amount while starting the game by player
  /// @param _game player's game
  /// @param _playedGameCount played game count by game contract
  /// @param _payout accumulated payouts by game contract
  function shareEscrow(
    Game memory _game,
    uint256 _playedGameCount,
    uint256 _payout
  ) internal virtual returns (bool) {
    (uint256 usedWager_, uint256 unusedWager_) = calcWager(
      _game.count,
      _playedGameCount,
      _game.wager
    );
    /// @notice sets referral reward if player has referee
    vaultManager.setReferralReward(_game.tokens[0], _game.player, usedWager_, getHouseEdge(_game));
    vaultManager.mintVestedWINR(_game.tokens[0], usedWager_, _game.player);

    /// @notice this call transfers the unused wager to player
    if (unusedWager_ != 0) {
      vaultManager.payback(_game.tokens[0], _game.player, unusedWager_);
    }

    /// @notice calculates the loss of user if its not zero transfers to Vault
    if (_payout == 0) {
      vaultManager.payin(_game.tokens[0], usedWager_);
    } else {
      vaultManager.payout(_game.tokens, _game.player, usedWager_, _payout);
    }

    /// @notice The used wager is the zero point. if the payout is above the wager, player wins
    return _payout > usedWager_;
  }

  /// @notice shares the amount which escrowed amount while starting the game by player
  /// @param _game request's game
  /// @param _randoms raw random numbers sent by randomizers
  /// @return numbers_ modded numbers according to game
  function getResultNumbers(
    Game memory _game,
    uint256[] calldata _randoms
  ) internal virtual returns (uint256[] memory numbers_);

  /// @notice function that calculation or return a constant of house edge
  /// @param _game request's game
  /// @return edge_ calculated house edge of game
  function getHouseEdge(Game memory _game) public view virtual returns (uint64 edge_);

  /// @notice game logic contains here, decision mechanism
  /// @param _game request's game
  /// @param _resultNumbers modded numbers according to game
  /// @param _stopGain maximum profit limit
  /// @param _stopLoss maximum loss limit
  /// @return payout_ _payout accumulated payouts by game contract
  /// @return playedGameCount_  played game count by game contract
  /// @return payouts_ profit calculated at every step of the game, wager excluded
  function play(
    Game memory _game,
    uint256[] memory _resultNumbers,
    uint256 _stopGain,
    uint256 _stopLoss
  )
    public
    view
    virtual
    returns (uint256 payout_, uint32 playedGameCount_, uint256[] memory payouts_);

  /// @notice randomizer consumer triggers that function
  /// @notice manages the game variables and shares the escrowed amount
  /// @param _requestId generated request id by randomizer
  /// @param _randoms raw random numbers sent by randomizers
  function randomizerFulfill(
    uint256 _requestId,
    uint256[] calldata _randoms
  )
    internal
    override
    isGameCreated(_requestId)
    whenNotCompleted(_requestId)
    nonReentrant
  {
    Game memory game_ = games[_requestId];
    Options memory options_ = options[_requestId];
    uint256[] memory resultNumbers_ = getResultNumbers(game_, _randoms);
    (uint256 payout_, uint32 playedGameCount_, uint256[] memory payouts_) = play(
      game_,
      resultNumbers_,
      options_.stopGain,
      options_.stopLoss
    );

    emit Settled(
      game_.player,
      _requestId,
      game_.wager,
      shareEscrow(game_, playedGameCount_, payout_),
      payout_,
      playedGameCount_,
      resultNumbers_,
      payouts_
    );

    delete games[_requestId];
    delete options[_requestId];
  }

  /// @notice randomizer consumer triggers that function
  /// @notice manages the game variables and shares the escrowed amount
  /// @param _wager amount for a game
  /// @param _count the selected game count by player
  /// @param _stopGain maximum profit limit
  /// @param _stopLoss maximum loss limit
  /// @param _gameData players decisions according to game
  /// @param _tokens contains input and output token currencies
  function _create(
    uint256 _wager,
    uint8 _count,
    uint256 _stopGain,
    uint256 _stopLoss,
    bytes memory _gameData,
    address[2] memory _tokens
  )
    internal
    isGameCountAcceptable(_count)
    isWagerAcceptable(_tokens[0], _wager)
    whenNotPaused
    nonReentrant
  {
    address player_ = _msgSender();
    uint256 requestId_ = _requestRandom(_count);

    /// @notice escrows total wager to Vault Manager
    vaultManager.escrow(_tokens[0], player_, _count * _wager);

    games[requestId_] = Game(
      _count,
      player_,
      _gameData,
      _wager,
      block.timestamp,
      _tokens
    );

    if (_stopGain != 0 || _stopLoss != 0) {
      options[requestId_] = Options(_stopGain, _stopLoss);
    }

    emit Created(player_, requestId_, _wager, _tokens);
  }
}

abstract contract Core is Pausable, Access, ReentrancyGuard, NumberHelper, RandomizerConsumer {
  /*==================================================== Events ==========================================================*/

  event VaultManagerChange(address vaultManager);

  /*==================================================== Modifiers ==========================================================*/


  modifier isWagerAcceptable(address _token, uint256 _wager) {
    uint256 dollarValue_ = _computeDollarValue(_token, _wager);
    require(dollarValue_ >= vaultManager.getMinWager(address(this)), "GAME: Wager too low");
    require(dollarValue_ <= vaultManager.getMaxWager(), "GAME: Wager too high");
    _;
  }

  /*==================================================== State Variables ====================================================*/

  /// @notice used to calculate precise decimals
  uint256 public constant PRECISION = 1e18;
  /// @notice Vault manager address
  IVaultManager public vaultManager;

  /*==================================================== Functions ===========================================================*/

  constructor(IRandomizerRouter _router) RandomizerConsumer(_router) {}

  function setVaultManager(IVaultManager _vaultManager) external onlyGovernance {
    vaultManager = _vaultManager;

    emit VaultManagerChange(address(_vaultManager));
  }

  function pause() external onlyTeam {
    _pause();
  }

  function unpause() external onlyTeam {
    _unpause();
  }

  function _computeDollarValue(
    address _token,
    uint256 _wager
  ) public view returns (uint256 _wagerInDollar) {
    _wagerInDollar = ((_wager * vaultManager.getPrice(_token))) / (10 ** IERC20Metadata(_token).decimals());
  }
}

interface IFeeCollector {
  function calcFee(uint256 _amount) external view returns (uint256);
  function onIncreaseFee(address _token) external;
  function onVolumeIncrease(uint256 amount) external;
}

interface IVault {
  function getReserve() external view returns (uint256);

  function getWlpValue() external view returns (uint256);

  function getDollarValue(address _token) external view returns (uint256);

  function payout(
    address[2] memory _tokens,
    address _escrowAddress,
    uint256 _escrowAmount,
    address _recipient,
    uint256 _totalAmount
  ) external;

  function payin(address _inputToken, address _escrowAddress, uint256 _escrowAmount) external;

  function deposit(address _token, address _receiver) external returns (uint256);

  function withdraw(address _token, address _receiver) external;
}

abstract contract Access is AccessControl {
  /*==================================================== Modifiers ==========================================================*/

  modifier onlyGovernance() virtual {
    require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "ACC: Not governance");
    _;
  }

  modifier onlyTeam() virtual {
    require(hasRole(TEAM_ROLE, _msgSender()), "GAME: Not team");
    _;
  }

  /*==================================================== State Variables ====================================================*/

  bytes32 public constant TEAM_ROLE = bytes32(keccak256("TEAM"));

  /*==================================================== Functions ===========================================================*/

  constructor()  {
    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
  }
}

interface ISupraRouter { 
	function generateRequest(string memory _functionSig, uint8 _rngCount, uint256 _numConfirmations, address _clientWalletAddress) external returns(uint256);
    function generateRequest(string memory _functionSig, uint8 _rngCount, uint256 _numConfirmations, uint256 _clientSeed, address _clientWalletAddress) external returns(uint256);
}

interface IRandomizerRouter {
  function request(uint32 count, uint256 _minConfirmations) external returns (uint256);
  function scheduledRequest(uint32 _count, uint256 targetTime) external returns (uint256);
  function response(uint256 _requestId, uint256[] calldata _rngList) external;
}

interface IRandomizerConsumer {
  function randomizerCallback(uint256 _requestId, uint256[] calldata _rngList) external;
}

contract NumberHelper {
  function modNumber(uint256 _number, uint32 _mod) internal pure returns (uint256) {
    return _mod > 0 ? _number % _mod : _number;
  }

  function modNumbers(uint256[] memory _numbers, uint32 _mod) internal pure returns (uint256[] memory) {
    uint256[] memory modNumbers_ = new uint[](_numbers.length);

    for (uint256 i = 0; i < _numbers.length; i++) {
      modNumbers_[i] = modNumber(_numbers[i], _mod);
    }

    return modNumbers_;
  }
}

abstract contract RandomizerConsumer is Access, IRandomizerConsumer {
  /*==================================================== Modifiers ===========================================================*/

  modifier onlyRandomizer() {
    require(hasRole(RANDOMIZER_ROLE, _msgSender()), "RC: Not randomizer");
    _;
  }

  /*==================================================== State Variables ====================================================*/

  /// @notice minimum confirmation blocks
  uint256 public minConfirmations = 3;
  /// @notice router address
  IRandomizerRouter public randomizerRouter;
  /// @notice Randomizer ROLE as Bytes32
  bytes32 public constant RANDOMIZER_ROLE = bytes32(keccak256("RANDOMIZER"));

  /*==================================================== FUNCTIONS ===========================================================*/

  constructor(IRandomizerRouter _randomizerRouter) {
    changeRandomizerRouter(_randomizerRouter);
  }

  /*==================================================== Configuration Functions ====================================================*/

  function changeRandomizerRouter(IRandomizerRouter _randomizerRouter) public onlyGovernance {
    randomizerRouter = _randomizerRouter;
    grantRole(RANDOMIZER_ROLE, address(_randomizerRouter));
  }


  function setMinConfirmations(uint16 _minConfirmations) external onlyGovernance {
    minConfirmations = _minConfirmations;
  }

  /*==================================================== Randomizer Functions ====================================================*/

  function randomizerFulfill(uint256 _requestId, uint256[] calldata _rngList) internal virtual;

  function randomizerCallback(uint256 _requestId, uint256[] calldata _rngList) external onlyRandomizer {
    randomizerFulfill(_requestId, _rngList);
  }

  function _requestRandom(uint8 _count) internal returns (uint256 requestId_) {
    requestId_ = randomizerRouter.request(_count, minConfirmations);
  }

  function _requestScheduledRandom(uint8 _count, uint256 targetTime) internal returns (uint256 requestId_) {
    requestId_ = randomizerRouter.scheduledRequest(_count, targetTime);
  }
}
