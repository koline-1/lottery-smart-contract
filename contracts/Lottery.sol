pragma solidity >=0.4.21 <0.6.0;

contract Lottery {
    struct BetInfo {
        uint256 answerBlockNumber;
        address payable bettor;
        byte challenges;
    }

    uint256 private _tail;
    uint256 private _head;
    mapping (uint256 => BetInfo) private _bets;

    address payable public owner;

    uint256 constant internal BLOCK_LIMIT = 256;
    uint256 constant internal BET_BLOCK_INTERVAL = 3;
    uint256 constant internal BET_AMOUNT = 5 * 10 ** 15;

    uint256 private _pot;
    bool private mode = false;      // false: test mode, true: operation mode
    bytes32 private answerForTest;

    enum BlockStatus {Checkable, NotRevealed, BlockLimitPassed}
    enum BettingResult {Fail, Win, Draw}

    event BET(uint256 index, address bettor, uint256 amount, byte challenges, uint256 answerBlockNumber);
    event WIN(uint256 index, address bettor, uint256 amount, byte challenges, byte answer, uint256 answerBlockNumber);
    event FAIL(uint256 index, address bettor, uint256 amount, byte challenges, byte answer, uint256 answerBlockNumber);
    event DRAW(uint256 index, address bettor, uint256 amount, byte challenges, byte answer, uint256 answerBlockNumber);
    event REFUND(uint256 index, address bettor, uint256 amount, byte challenges, uint256 answerBlockNumber);

    constructor() public {
        owner = msg.sender;
    }

    function getPot() public view returns (uint256 value) {
        return _pot;
    }

    function getBetInfo(uint256 index) public view returns (uint256 answerBlockNumber, address bettor, byte challenges) {
        BetInfo memory b = _bets[index];
        answerBlockNumber = b.answerBlockNumber;
        bettor = b.bettor;
        challenges = b.challenges;
    }

    function pushBet(byte challenges) internal returns (bool) {
        BetInfo memory b;
        b.bettor = msg.sender;
        b.answerBlockNumber = block.number + BET_BLOCK_INTERVAL;
        b.challenges = challenges;

        _bets[_tail] = b;
        _tail++;

        return true;
    }

    function popBet(uint256 index) internal returns (bool) {
        delete _bets[index];
        return true;
    }

    /**
     * @dev 베팅과 정답 체크를 한다. 유저는 0.005 ETH를 보내야 하고, 베팅용 1 byte 글자를 보낸다.
     * 큐에 저장된 베팅 정보는 이후 distribute 함수에서 해결된다.
     * @param challenges 유저가 베팅하는 글자
     * @return 함수가 잘 수행되었는지 확인해는 bool 값
     */
    function betAndDistribute(byte challenges) public payable returns (bool result) {
        bet(challenges);
        distribute();
        return true;
    }

    /**
     * @dev 배팅을 한다. 유저는 0.005 ETH를 보내야 하고, 배팅 큐에 1 byte 글자를 보낸다.
     * 큐에 저장된 배팅 정보는 이후 distribute 함수에서 해결한다.
     * @param challenges 유저가 배팅하는 글자
     * @return 제대로 함수가 수행되었는지 결과값
     */
    function bet(byte challenges) public payable returns (bool result) {
        // check ether is sent properly
        require(msg.value == BET_AMOUNT, 'Not enough ETH.');
        
        // push bet to the queue
        require(pushBet(challenges), 'Failed to add bet info.');

        // emit event
        emit BET(_tail - 1, msg.sender, msg.value, challenges, block.number + BET_BLOCK_INTERVAL);

        return true;
    }

    /**
     * @dev 베팅 결과값을 확인 하고 팟머니를 분배한다.
     * 정답 실패 : 팟머니 축척, 정답 맞춤 : 팟머니 획득, 한글자 맞춤 or 정답 확인 불가 : 베팅 금액만 획득
     */
    function distribute() public {
        uint256 cur;
        uint256 transferAmount;

        BetInfo memory b;
        BlockStatus currentBlockStatus;
        BettingResult currentBettingResult;

        for (cur=_head;cur<_tail;cur++) {
            b = _bets[cur];
            currentBlockStatus = getBlockStatus(b.answerBlockNumber);

            // Checkable: block.number > answerBlockNumber && block.number < BLOCK_LIMIT + answerBlockNumber
            if (currentBlockStatus == BlockStatus.Checkable) {
                bytes32 answerBlockHash = getAnswerBlockHash(b.answerBlockNumber);
                currentBettingResult = isMatch(b.challenges, answerBlockHash);

                // Win(all correct): Bettor gets pot money
                if (currentBettingResult == BettingResult.Win) {
                    // transfer pot
                    transferAmount = transferAfterPayingFee(b.bettor, _pot + BET_AMOUNT);

                    // reset pot
                    _pot = 0;

                    // emit WIN
                    emit WIN(cur, b.bettor, transferAmount, b.challenges, answerBlockHash[0], b.answerBlockNumber);
                }

                // Fail(all wrong): Bettor's money goes to pot
                if (currentBettingResult == BettingResult.Fail) {
                    // pot = pot + BET_AMOUNT
                    _pot += BET_AMOUNT;

                    // emit FAIL
                    emit FAIL(cur, b.bettor, 0, b.challenges, answerBlockHash[0], b.answerBlockNumber);
                }

                // Draw(one correct): Bettor gets refunded
                if (currentBettingResult == BettingResult.Draw) {
                    // transfer BET_AMOUNT
                    transferAmount = transferAfterPayingFee(b.bettor, BET_AMOUNT);

                    // emit DRAW
                    emit DRAW(cur, b.bettor, transferAmount, b.challenges, answerBlockHash[0], b.answerBlockNumber);
                }
            }

            // Not Revealed: block.number <= answerBlockNumber
            if (currentBlockStatus == BlockStatus.NotRevealed) {
                break;
            }

            // Block Limit Passed: block.number >= BLOCK_LIMIT + answerBlockNumber
            if (currentBlockStatus == BlockStatus.BlockLimitPassed) {
                // refund
                transferAmount = transferAfterPayingFee(b.bettor, BET_AMOUNT);

                // emit refund
                emit REFUND(cur, b.bettor, transferAmount, b.challenges, b.answerBlockNumber);
            }

            // Check the answer
            popBet(cur);
        }

        _head = cur;
    }

    function transferAfterPayingFee(address payable addr, uint256 amount) internal returns (uint256) {
        // uint256 fee = amount / 100;
        uint256 fee = 0;
        uint256 amountWithoutFee = amount - fee;

        // transfer to addr
        addr.transfer(amountWithoutFee);

        // transfer to owner
        owner.transfer(fee);

        return amountWithoutFee;
    }

    function setAnswerForTest(bytes32 answer) public returns(bool result) {
        require(msg.sender == owner, 'Only owner can set the answer for test mode');
        answerForTest = answer;
        return true;
    }

    function getAnswerBlockHash(uint256 answerBlockNumber) internal view returns (bytes32 answer) {
        return mode ? blockhash(answerBlockNumber) : answerForTest;
    }

    /**
     * @dev 베팅글자와 정답을 확인한다.
     * @param challenges 베팅 글자
     * @param answer 블락해쉬
     * @return 정답결과
     */
    function isMatch(byte challenges, bytes32 answer) public pure returns (BettingResult) {
        // challenges
        byte c1 = challenges;
        byte c2 = challenges;

        // answer
        byte a1 = answer[0];
        byte a2 = answer[0];

        // First Number
        c1 = c1 >> 4;   // 0xab -> 0x0a
        c1 = c1 << 4;   // 0xab -> 0xa0

        a1 = a1 >> 4;
        a1 = a1 << 4;

        // Second Number
        c2 = c2 << 4;   // 0xab -> 0xb0
        c2 = c2 >> 4;   // 0xab -> 0x0b

        a2 = a2 << 4;
        a2 = a2 >> 4;

        if (c1 == a1 && c2 == a2) {
            return BettingResult.Win;
        }

        if (c1 == a1 || c2 == a2) {
            return BettingResult.Draw;
        }

        return BettingResult.Fail;
    }

    function getBlockStatus(uint256 answerBlockNumber) internal view returns (BlockStatus) {
        // Checkable: block.number > answerBlockNumber && block.number < BLOCK_LIMIT + answerBlockNumber
        if (block.number > answerBlockNumber && block.number < BLOCK_LIMIT + answerBlockNumber) {
            return BlockStatus.Checkable;
        }

        // Not Revealed: block.number <= answerBlockNumber
        if (block.number <= answerBlockNumber) {
            return BlockStatus.NotRevealed;
        }

        // Block Limit Passed: block.number >= BLOCK_LIMIT + answerBlockNumber
        if (block.number >= BLOCK_LIMIT + answerBlockNumber) {
            return BlockStatus.BlockLimitPassed;
        }

        return BlockStatus.BlockLimitPassed;
    }
}