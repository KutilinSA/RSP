pragma solidity >=0.7.0 <0.9.0;

contract RSP {
    event GameStarted(address initiator, uint bet);
    event SecondPlayerParticipated(address secondPlayer);
    event RevealedChoice(address player, uint choice);
    event GameEnded();
    event GameBroken();
    event GamePaid(GameResult result);

    enum GameState {
        notStarted,
        waitingSecondPlayer,
        revealing,
        ended,
        paid
    }

    enum GameResult {
        draw,
        firstPlayerWon,
        secondPlayerWon
    }

    address payable public firstPlayer;
    address payable public secondPlayer;

    bool private firstPlayerPaid;
    bool private secondPlayerPaid;

    uint public gameBet;

    bytes32 public firstPlayerCommit;
    bytes32 public secondPlayerCommit;

    uint public firstPlayerChoice;
    uint public secondPlayerChoice;

    GameState public gameState;
    GameResult public gameResult;

    constructor() {
        firstPlayer = payable(msg.sender);
        secondPlayer = payable(address(0x0));
        firstPlayerPaid = false;
        secondPlayerPaid = false;
        gameBet = 0;
        firstPlayerCommit = 0;
        secondPlayerCommit = 0;
        firstPlayerChoice = 0;
        secondPlayerChoice = 0;
        gameState = GameState.notStarted;
    }

    function startGame(bytes32 commit) external payable 
        forGameState(GameState.notStarted) onlyFirstPlayer {
        require (commit != "", "Empty commit");
        require (msg.value != 0, "Empty bet");

        gameBet = msg.value;
        firstPlayerCommit = commit;
        gameState = GameState.waitingSecondPlayer;
        emit GameStarted(firstPlayer, gameBet);
    }

    function participate(bytes32 commit) external payable 
        forGameState(GameState.waitingSecondPlayer) needBet notAPlayer {
        
        secondPlayer = payable(msg.sender);
        secondPlayerCommit = commit;
        gameState = GameState.revealing;
        emit SecondPlayerParticipated(msg.sender);
    }

    // Salt по идее должен быть bytes32, но у Remix проблемы с передачей bytes32
    function reveal(uint choice, string calldata salt) external 
        forGameState(GameState.revealing) needValidChoice(choice) anyPlayer {

        bytes32 hash = keccak256(abi.encodePacked(choice, salt));
        if (msg.sender == firstPlayer) {
            require (firstPlayerCommit == hash, "You are trying to lie");
            firstPlayerChoice = choice;
            emit RevealedChoice(firstPlayer, choice);
        } else if (msg.sender == secondPlayer) {
            require (secondPlayerCommit == hash, "You are trying to lie");
            secondPlayerChoice = choice;
            emit RevealedChoice(secondPlayer, choice);
        }

        if (firstPlayerChoice != 0 && secondPlayerChoice != 0) {
            emit GameEnded();
            gameState = GameState.ended;
        }
    }

    // Прерывает игру, возвращая средства. Вдруг на стадии открытия кто-то ушел
    function breakGame() external forGameState(GameState.revealing) anyPlayer {
        gameState = GameState.paid;
        (firstPlayerPaid, ) = firstPlayer.call{value: gameBet}("");
        (secondPlayerPaid, ) = secondPlayer.call{value: gameBet}("");
        emit GameBroken();
    }

    function endGame() external forGameState(GameState.ended) {
        uint gameReusltValue = (3 + secondPlayerChoice - firstPlayerChoice) % 3;
        gameResult = GameResult(gameReusltValue);
        if (gameResult == GameResult.firstPlayerWon) {
            (bool success, ) = firstPlayer.call{value: gameBet * 2}("");
            require (success, "Error transfering");
            gameState = GameState.paid;
            emit GamePaid(gameResult);
        } else if (gameResult == GameResult.secondPlayerWon) {
            (bool success, ) = secondPlayer.call{value: gameBet * 2}("");
            require (success, "Error transfering");
            gameState = GameState.paid;
            emit GamePaid(gameResult);
        } else if (gameResult == GameResult.draw) {
            if (!firstPlayerPaid) {
                (firstPlayerPaid, ) = firstPlayer.call{value: gameBet}("");
            }
            if (!secondPlayerPaid) {
                (secondPlayerPaid, ) = secondPlayer.call{value: gameBet}("");
            }
            require (firstPlayerPaid && secondPlayerPaid, "Error transfering");
            gameState = GameState.paid;
            emit GamePaid(gameResult);
        }
    }

    modifier forGameState(GameState state) {
        require (gameState == state, "Game is not in needed status");
        _;
    }

    modifier onlyFirstPlayer() {
        require (msg.sender == firstPlayer, "You are not a first player");
        _;
    }

    modifier notAPlayer() {
        require (msg.sender != firstPlayer && msg.sender != secondPlayer, "You are alreay a player");
        _;
    }

    modifier anyPlayer() {
        require (msg.sender == firstPlayer || msg.sender == secondPlayer, "You are not a player");
        _;
    }

    modifier needBet() {
        require (msg.value >= gameBet, "Not enough bet");
        _;
    }

    modifier needValidChoice(uint choice) {
        require (choice >= 1 && choice <= 3, "Choice should be in [1;3] range");
        _;
    }

    // TEST ONLY. Коммит надо генерировать из клиента Веб3 или на других ресурсах
    function getCommit(uint choice, string memory salt) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(choice, salt));
    }
}