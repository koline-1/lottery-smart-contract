const Lottery = artifacts.require("Lottery");
const assertRevert = require('./assertRevert');
const expectEvent = require('./expectEvent');

contract('Lottery', function([deployer, user1, user2]) {
    let lottery;
    let BET_AMOUNT = 5 * 10 ** 15;
    let BET_BLOCK_INTERVAL = 3;
    let BET_AMOUNT_BN = new web3.utils.BN('5000000000000000');

    beforeEach(async () => {
        lottery = await Lottery.new();
    })

    it('getPot should return current pot', async () => {
        let pot = await lottery.getPot();
        assert.equal(pot, 0);
    })

    describe('Bet', function () {
        it('bet should fail if the bet amount is not 0.005 ETH', async () => {
            // Fail Transaction
            // transaction object { chainId, value, from, to, gas(Limit), gasPrice }
            await assertRevert(lottery.bet('0xab', { from: user1, value: 4000000000000000 }));
        })

        it('bet should add the bet to the queue', async () => {
            let receipt = await lottery.bet('0xab', { from: user1, value: BET_AMOUNT });
            // console.log(receipt)

            // bet
            let pot = await lottery.getPot();
            assert.equal(pot, 0);

            // check contract balance is 0.005 ETH
            let contractBalance = await web3.eth.getBalance(lottery.address);
            assert.equal(contractBalance, BET_AMOUNT);

            // check bet info
            let currentBlockNumber = await web3.eth.getBlockNumber();
            let bet = await lottery.getBetInfo(0);
            assert.equal(bet.answerBlockNumber, currentBlockNumber + BET_BLOCK_INTERVAL);
            assert.equal(bet.bettor, user1);
            assert.equal(bet.challenges, '0xab');
            
            // check log
            await expectEvent.inLogs(receipt.logs, 'BET');
        })
    })

    describe('distribute', function () {
        describe('When the answer is checkable', function () {
            it('should give user the pot money when both characters match', async () => {
                // 두 글자 다 맞았을 때
                await lottery.setAnswerForTest('0x24b4012cf88e10e66e2a3f1df2b35fe755358b1308d0539250cf585b92913440', { from: deployer });

                // betAndDistribute 반복
                await lottery.betAndDistribute('0xef', { from: user2, value: BET_AMOUNT }); // 1 -> 4
                await lottery.betAndDistribute('0xef', { from: user2, value: BET_AMOUNT }); // 2 -> 5
                await lottery.betAndDistribute('0x24', { from: user1, value: BET_AMOUNT }); // 3 -> 6   (7번에서 확인 가능)
                await lottery.betAndDistribute('0xef', { from: user2, value: BET_AMOUNT }); // 4 -> 7
                await lottery.betAndDistribute('0xef', { from: user2, value: BET_AMOUNT }); // 5 -> 8
                await lottery.betAndDistribute('0xef', { from: user2, value: BET_AMOUNT }); // 6 -> 9

                // pot 변화량 확인
                let potBefore = await lottery.getPot();     // 0.01 ETH
                let user1BalanceBefore = await web3.eth.getBalance(user1);
                let receipt7 = await lottery.betAndDistribute('0xef', { from: user2, value: BET_AMOUNT }); // 7 -> 10

                let potAfter = await lottery.getPot();      // 0 ETH
                let user1BalanceAfter = await web3.eth.getBalance(user1);   // before + 0.015 ETH

                assert.equal(potBefore.toString(), new web3.utils.BN('10000000000000000').toString());
                assert.equal(potAfter.toString(), new web3.utils.BN('0').toString());

                // user(winner)의 balance 확인
                user1BalanceBefore = new web3.utils.BN(user1BalanceBefore);
                assert.equal(user1BalanceBefore.add(potBefore).add(BET_AMOUNT_BN).toString(), new web3.utils.BN(user1BalanceAfter).toString());
            })

            it('should return user the bet money when a single character matches', async () => {
                // 한 글자 맞았을 때
                await lottery.setAnswerForTest('0x24b4012cf88e10e66e2a3f1df2b35fe755358b1308d0539250cf585b92913440', { from: deployer });

                // betAndDistribute 반복
                await lottery.betAndDistribute('0xef', { from: user2, value: BET_AMOUNT }); // 1 -> 4
                await lottery.betAndDistribute('0xef', { from: user2, value: BET_AMOUNT }); // 2 -> 5
                await lottery.betAndDistribute('0x2a', { from: user1, value: BET_AMOUNT }); // 3 -> 6   (7번에서 확인 가능)
                await lottery.betAndDistribute('0xef', { from: user2, value: BET_AMOUNT }); // 4 -> 7
                await lottery.betAndDistribute('0xef', { from: user2, value: BET_AMOUNT }); // 5 -> 8
                await lottery.betAndDistribute('0xef', { from: user2, value: BET_AMOUNT }); // 6 -> 9

                // pot 변화량 확인
                let potBefore = await lottery.getPot();     // 0.01 ETH
                let user1BalanceBefore = await web3.eth.getBalance(user1);
                await lottery.betAndDistribute('0xef', { from: user2, value: BET_AMOUNT }); // 7 -> 10

                let potAfter = await lottery.getPot();      // == before
                let user1BalanceAfter = await web3.eth.getBalance(user1);   // before + 0.005 ETH

                assert.equal(potBefore.toString(), potAfter.toString());

                // user(winner)의 balance 확인
                user1BalanceBefore = new web3.utils.BN(user1BalanceBefore);
                assert.equal(user1BalanceBefore.add(BET_AMOUNT_BN).toString(), new web3.utils.BN(user1BalanceAfter).toString());
            })

            it('should send the bet money to pot when both characters do not match', async () => {
                // 두 글자 다 틀렸을 때
                await lottery.setAnswerForTest('0x24b4012cf88e10e66e2a3f1df2b35fe755358b1308d0539250cf585b92913440', { from: deployer });

                // betAndDistribute 반복
                await lottery.betAndDistribute('0xef', { from: user2, value: BET_AMOUNT }); // 1 -> 4
                await lottery.betAndDistribute('0xef', { from: user2, value: BET_AMOUNT }); // 2 -> 5
                await lottery.betAndDistribute('0xab', { from: user1, value: BET_AMOUNT }); // 3 -> 6   (7번에서 확인 가능)
                await lottery.betAndDistribute('0xef', { from: user2, value: BET_AMOUNT }); // 4 -> 7
                await lottery.betAndDistribute('0xef', { from: user2, value: BET_AMOUNT }); // 5 -> 8
                await lottery.betAndDistribute('0xef', { from: user2, value: BET_AMOUNT }); // 6 -> 9

                // pot 변화량 확인
                let potBefore = await lottery.getPot();     // 0.015 ETH
                let user1BalanceBefore = await web3.eth.getBalance(user1);
                await lottery.betAndDistribute('0xef', { from: user2, value: BET_AMOUNT }); // 7 -> 10

                let potAfter = await lottery.getPot();      // before + 0.005 ETH
                let user1BalanceAfter = await web3.eth.getBalance(user1);   // == before

                assert.equal(potBefore.add(BET_AMOUNT_BN).toString(), potAfter.toString());

                // user(winner)의 balance 확인
                user1BalanceBefore = new web3.utils.BN(user1BalanceBefore);
                assert.equal(user1BalanceBefore.toString(), new web3.utils.BN(user1BalanceAfter).toString());
            })
        })

        describe('When the answer is not revealed', function () {
            
        })

        describe('When the answer is not reachable', function () {
            
        })
    })

    describe('isMatch', function () {
        let blockHash = '0x24b4012cf88e10e66e2a3f1df2b35fe755358b1308d0539250cf585b92913440';

        // Win (all correct)
        it('should return BettingResult.Win when two characters match', async () => {
            let matchingResult = await lottery.isMatch('0x24', blockHash);
            assert.equal(matchingResult, 1)
        })

        // Draw (one correct)
        it('should return BettingResult.Draw when one characters match', async () => {
            let matchingResult = await lottery.isMatch('0x25', blockHash);
            assert.equal(matchingResult, 2)
        })

        // Fail (all wrong)
        it('should return BettingResult.Fail when both characters do not match', async () => {
            let matchingResult = await lottery.isMatch('0xab', blockHash);
            assert.equal(matchingResult, 0)
        })
    })
});