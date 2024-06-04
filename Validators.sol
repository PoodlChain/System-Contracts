// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Params.sol";
import "./Punish.sol";

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}
contract Validators is Params, Ownable {

    enum Status {
        // validator not exist, default status
        NotExist,
        // validator created
        Created,
        // anyone has staked for the validator
        Staked,
        // validator's staked coins < MinimalStakingCoin
        Unstaked,
        // validator is jailed by system(validator have to repropose)
        Jailed
    }

    enum valType
    {
      Super,
      Master,
      Little
    }

    struct Description {
        string moniker;
        string identity;
        string website;
        string email;
        string details;
    }

    struct Validator {
        address payable feeAddr;
        Status status;
        uint256 coins;
        Description description;
        uint256 hbIncoming;
        uint256 totalJailedHB;
        // Address list of user who has staked for this validator
        address[] stakers;
        valType vType;
    }


    struct StakingInfo {
        uint256 coins;
        // unstakeBlock != 0 means that you are unstaking your stake, so you can't
        // stake or unstake
        uint256 unstakeBlock;
        // index of the staker list in validator
        uint256 index;
    }
    struct TypesData
    {
      uint256 totalCount;
      uint256 perc;
      uint256 minStake;
      uint16 maxLimit;
    }
    mapping(uint256 =>TypesData) public valTypes;
    mapping(address => Validator) validatorInfo;
    // staker => validator => info
    mapping(address => mapping(address => StakingInfo)) staked;
    // current validator set used by chain
    // only changed at block epoch
    address[] public currentValidatorSet;
    // highest validator set(dynamic changed)
    address[] public highestValidatorsSet;
    // total stake of all validators
    uint256 public totalStake;
    // total jailed hb
    uint256 public totalJailedHB;

    // staker => validator => lastRewardTime
    mapping(address => mapping(address => uint)) public stakeTime;
    //validator => LastRewardtime
    mapping( address => uint) public lastRewardTime;
    //validator => lastRewardTime => reflectionPerent
    mapping(address => mapping( uint => uint )) public reflectionPercentSum;


    // System contracts
    Punish punish;

    enum Operations {Distribute, UpdateValidators}
    // Record the operations is done or not.
    mapping(uint256 => mapping(uint8 => bool)) operationsDone;

    event LogCreateValidator(
        address indexed val,
        address indexed fee,
        uint256 time
    );
    event LogEditValidator(
        address indexed val,
        address indexed fee,
        uint256 time
    );
    event LogReactive(address indexed val, uint256 time);
    event LogAddToTopValidators(address indexed val, uint256 time);
    event LogRemoveFromTopValidators(address indexed val, uint256 time);
    event LogUnstake(
        address indexed staker,
        address indexed val,
        uint256 amount,
        uint256 time
    );
    event LogWithdrawStaking(
        address indexed staker,
        address indexed val,
        uint256 amount,
        uint256 time
    );
    event LogWithdrawProfits(
        address indexed val,
        address indexed fee,
        uint256 hb,
        uint256 time
    );
    event LogRemoveValidator(address indexed val, uint256 hb, uint256 time);
    event LogRemoveValidatorIncoming(
        address indexed val,
        uint256 hb,
        uint256 time
    );
    event LogDistributeBlockReward(
        address indexed coinbase,
        uint256 blockReward,
        uint256 time
    );
    event LogUpdateValidator(address[] newSet);
    event LogStake(
        address indexed staker,
        address indexed val,
        uint256 staking,
        uint256 time
    );

    event withdrawStakingRewardEv(address user,address validator,uint reward,uint timeStamp);

    modifier onlyNotRewarded() {
        require(
            operationsDone[block.number][uint8(Operations.Distribute)] == false,
            "Block is already rewarded"
        );
        _;
    }

    modifier onlyNotUpdated() {
        require(
            operationsDone[block.number][uint8(Operations.UpdateValidators)] ==
                false,
            "Validators already updated"
        );
        _;
    }

    //valPerc - set % for all 3 types of nodes
    //minStake - set minimum staking amount for all 3 types of nodes
    //maxLimit - set maximum number of nodes for all 3 types of nodes - sum of all should be 100
    function initialize(address[] calldata vals) external onlyNotInitialized {
        punish = Punish(PunishContractAddr);
        _transferOwnership(0x3A9B513f0465a5E20eaCb873b65b9D68D76c042d);
        for (uint256 i = 0; i < vals.length; i++) {
            require(vals[i] != address(0), "Invalid validator address");
            lastRewardTime[vals[i]] = block.timestamp;

            if (!isActiveValidator(vals[i])) {
                currentValidatorSet.push(vals[i]);
            }
            if (!isTopValidator(vals[i])) {
                highestValidatorsSet.push(vals[i]);
            }
            if (validatorInfo[vals[i]].feeAddr == address(0)) {
                validatorInfo[vals[i]].feeAddr = payable(vals[i]);
            }
            // Important: NotExist validator can't get profits
            if (validatorInfo[vals[i]].status == Status.NotExist) {
                validatorInfo[vals[i]].status = Status.Staked;
                valTypes[0].totalCount += 1;
            }
        }

        uint256[] memory valPerc = new uint256[](3);
        uint256[] memory minStake = new uint256[](3);
        uint16[] memory maxLimit = new uint16[](3);

        valPerc[0] = 10;
        valPerc[1] = 5;
        valPerc[2] = 3;

        minStake[0] = 100000000000000000000;
        minStake[1] = 50000000000000000000;
        minStake[2] = 30000000000000000000;

        maxLimit[0] = 50;
        maxLimit[1] = 40;
        maxLimit[2] = 10;

        _updateValTypesByIndexAndType(valPerc, minStake, maxLimit);
        initialized = true;
    }

    function updateValTypesByIndexAndType(uint256[] memory valPerc, uint256[] memory minStake, uint16[] memory maxLimit) external onlyOwner {
        _updateValTypesByIndexAndType(valPerc, minStake, maxLimit);
    }

    function _updateValTypesByIndexAndType(uint256[] memory valPerc, uint256[] memory minStake, uint16[] memory maxLimit) internal{
        //set validator type informations
        for (uint256 i=0; i<3; i++)
        {
          valTypes[i].perc = valPerc[i];
          valTypes[i].minStake = minStake[i];
          valTypes[i].maxLimit = maxLimit[i];
        }
    }

    // stake for the validator
    function stake(address validator)
        public
        payable
        onlyInitialized
        returns (bool)
    {
        address payable staker = payable(tx.origin);
        uint256 staking = msg.value;

        require(
            validatorInfo[validator].status == Status.Created ||
                validatorInfo[validator].status == Status.Staked,
            "Can't stake to a validator in abnormal status"
        );

        require(
            staked[staker][validator].unstakeBlock == 0,
            "Can't stake when you are unstaking"
        );

        Validator storage valInfo = validatorInfo[validator];
        // The staked coins of validator must >= MinimalStakingCoin
        if(staker == validator){
            require(
                valInfo.coins + (staking) >= MinimalStakingCoin,
                "Staking coins not enough"
            );
        }
        else
        {
            require(staking >= MinimalStakingCoin,
            "Staking coins not enough");
        }
        // stake at first time to this valiadtor
        if (staked[staker][validator].coins == 0) {
            // add staker to validator's record list
            staked[staker][validator].index = valInfo.stakers.length;
            valInfo.stakers.push(staker);
            if(lastRewardTime[validator] == 0)
            {
                lastRewardTime[validator] = block.timestamp;
            }
            stakeTime[staker][validator] = lastRewardTime[validator];
        }
        else
        {
            withdrawStakingReward(validator);
        }

        valInfo.coins = valInfo.coins + (staking);
        if (valInfo.status != Status.Staked) {
            valInfo.status = Status.Staked;
        }
        tryAddValidatorToHighestSet(validator, valInfo.coins);

        // record staker's info
        staked[staker][validator].coins = staked[staker][validator].coins + (
            staking
        );
        totalStake = totalStake + (staking);
        emit LogStake(staker, validator, staking, block.timestamp);
        return true;
    }
    //validatorType - any from 0,1,2
    function createOrEditValidator(
        address payable feeAddr,
        string calldata moniker,
        string calldata identity,
        string calldata website,
        string calldata email,
        string calldata details,
        uint8 validatorType
    ) external payable onlyInitialized returns (bool) {
        require(feeAddr != address(0), "Invalid fee address");
        require(validatorType < 3, "Invalid type");
        require(
            validateDescription(moniker, identity, website, email, details),
            "Invalid description"
        );
        address payable validator = payable(tx.origin);
        bool isCreate = false;
        if (validatorInfo[validator].status == Status.NotExist) {
            validatorInfo[validator].status = Status.Created;
            isCreate = true;
        }
        else  if(msg.value > 0)
        {
            //require(msg.value == 0, "Cannot restake from here");
             return false;
        }

        if (validatorInfo[validator].feeAddr != feeAddr) {
            validatorInfo[validator].feeAddr = feeAddr;
        }

        validatorInfo[validator].description = Description(
            moniker,
            identity,
            website,
            email,
            details
        );

        if (isCreate) {
            uint256 minimumValidatorStaking = valTypes[0].minStake;

            require(valTypes[validatorType].totalCount < valTypes[validatorType].maxLimit,"This type has reached its limit");
            minimumValidatorStaking = valTypes[validatorType].minStake;
            validatorInfo[validator].vType = valType(validatorType);
            valTypes[validatorType].totalCount += 1;
            // for the first time, validator has to stake minimum coins.
            require(msg.value >= minimumValidatorStaking, "Invalid staking amount");
            stake(validator);
            emit LogCreateValidator(validator, feeAddr, block.timestamp);
        } else {
            emit LogEditValidator(validator, feeAddr, block.timestamp);
        }
        return true;
    }

    function tryReactive(address validator)
        external
        onlyProposalContract
        onlyInitialized
        returns (bool)
    {
        // Only update validator status if Unstaked/Jailed
        if (
            validatorInfo[validator].status != Status.Unstaked &&
            validatorInfo[validator].status != Status.Jailed
        ) {
            return true;
        }

        if (validatorInfo[validator].status == Status.Jailed) {
            require(punish.cleanPunishRecord(validator), "clean failed");
        }
        validatorInfo[validator].status = Status.Staked;

        emit LogReactive(validator, block.timestamp);

        return true;
    }

    function unstake(address validator)
        external
        onlyInitialized
        returns (bool)
    {
        address staker = tx.origin;
        require(
            validatorInfo[validator].status != Status.NotExist,
            "Validator not exist"
        );
        require(
            validatorInfo[validator].vType == valType.Little,
            "Super or Master validators and their stakers cannot unstake"
        );

        StakingInfo storage stakingInfo = staked[staker][validator];
        Validator storage valInfo = validatorInfo[validator];
        uint256 unstakeAmount = stakingInfo.coins;

        require(
            stakingInfo.unstakeBlock == 0,
            "You are already in unstaking status"
        );
        require(unstakeAmount > 0, "You don't have any stake");
        // You can't unstake if the validator is the only one top validator and
        // this unstake operation will cause staked coins of validator < MinimalStakingCoin
        require(
            !(highestValidatorsSet.length == 1 &&
                isTopValidator(validator) &&
                (valInfo.coins - unstakeAmount) < MinimalStakingCoin),
            "You can't unstake, validator list will be empty after this operation!"
        );

        // try to remove this staker out of validator stakers list.
        if (stakingInfo.index != valInfo.stakers.length - 1) {
            valInfo.stakers[stakingInfo.index] = valInfo.stakers[valInfo
                .stakers
                .length - 1];
            // update index of the changed staker.
            staked[valInfo.stakers[stakingInfo.index]][validator]
                .index = stakingInfo.index;
        }
        valInfo.stakers.pop();

        valInfo.coins = valInfo.coins - (unstakeAmount);
        stakingInfo.unstakeBlock = block.number;
        stakingInfo.index = 0;
        totalStake = totalStake - (unstakeAmount);

        // try to remove it out of active validator set if validator's coins < MinimalStakingCoin
        if (valInfo.coins < MinimalStakingCoin && validatorInfo[validator].status != Status.Jailed) {
            valInfo.status = Status.Unstaked;
            // it's ok if validator not in highest set
            tryRemoveValidatorInHighestSet(validator);
        }

        withdrawStakingReward(validator);
        stakeTime[staker][validator] = 0 ;

        emit LogUnstake(staker, validator, unstakeAmount, block.timestamp);
        return true;
    }

    function withdrawStakingReward(address validator) public returns(bool)
    {
        require(stakeTime[tx.origin][validator] > 0 , "nothing staked");
        //require(stakeTime[tx.origin][validator] < lastRewardTime[validator], "no reward yet");
        StakingInfo storage stakingInfo = staked[tx.origin][validator];
        uint validPercent = reflectionPercentSum[validator][lastRewardTime[validator]] - reflectionPercentSum[validator][stakeTime[tx.origin][validator]];
        if(validPercent > 0)
        {
            stakeTime[tx.origin][validator] = lastRewardTime[validator];
            uint reward = stakingInfo.coins * validPercent / 100000000000000000000  ;
            payable(tx.origin).transfer(reward);
            emit withdrawStakingRewardEv(tx.origin, validator, reward, block.timestamp);
        }
        return true;
    }

    function withdrawStaking(address validator) external returns (bool) {
        address payable staker = payable(tx.origin);
        StakingInfo storage stakingInfo = staked[staker][validator];
        require(
            validatorInfo[validator].status != Status.NotExist,
            "validator not exist"
        );
        require(
            validatorInfo[validator].vType == valType.Little,
            "Super or Master validators and their stakers cannot unstake"
        );
        require(stakingInfo.unstakeBlock != 0, "You have to unstake first");

        require(stakingInfo.coins > 0, "You don't have any stake");

        uint256 staking = stakingInfo.coins;
        stakingInfo.coins = 0;
        stakingInfo.unstakeBlock = 0;

        // send stake back to staker
        staker.transfer(staking);

        emit LogWithdrawStaking(staker, validator, staking, block.timestamp);
        return true;
    }

    // feeAddr can withdraw profits of it's validator
    function withdrawProfits(address validator) external returns (bool) {
        address payable feeAddr = payable(tx.origin);
        require(
            validatorInfo[validator].status != Status.NotExist,
            "Validator not exist"
        );
        require(
            validatorInfo[validator].feeAddr == feeAddr,
            "You are not the fee receiver of this validator"
        );
        uint256 hbIncoming = validatorInfo[validator].hbIncoming;
        require(hbIncoming > 0, "You don't have any profits");

        // update info
        validatorInfo[validator].hbIncoming = 0;
       // validatorInfo[validator].lastWithdrawProfitsBlock = block.number;

        // send profits to fee address
        if (hbIncoming > 0) {
            feeAddr.transfer(hbIncoming);
        }
        withdrawStakingReward(validator);
        emit LogWithdrawProfits(
            validator,
            feeAddr,
            hbIncoming,
            block.timestamp
        );

        return true;
    }


    // distributeBlockReward distributes block reward to all active validators
    function distributeBlockReward()
        external
        payable
        onlyMiner
        onlyNotRewarded
        onlyInitialized
    {
        operationsDone[block.number][uint8(Operations.Distribute)] = true;
        address val = tx.origin;
        uint256 reward = msg.value;
        uint256 remaining = reward;

        //to charity
        if(charityWallet != address(0))
        {
          uint _charityPart = reward * charityPartPercent / 100000;
          remaining = remaining - _charityPart;
          payable(charityWallet).transfer(_charityPart);
        }

        //to validator
        uint _validatorPart = reward * validatorPartPercent / 100000;
        remaining = remaining - _validatorPart;


        uint lastRewardHold = reflectionPercentSum[val][lastRewardTime[val]];
        lastRewardTime[val] = block.timestamp;
        if(validatorInfo[val].coins > 0)
        {
            reflectionPercentSum[val][lastRewardTime[val]] = lastRewardHold + (remaining * 100000000000000000000 / validatorInfo[val].coins);
        }
        else
        {
            reflectionPercentSum[val][lastRewardTime[val]] = lastRewardHold;
            _validatorPart += remaining;
        }

        // never reach this
        if (validatorInfo[val].status == Status.NotExist) {
            return;
        }

        // Jailed validator can't get profits.
        addProfitsToActiveValidatorsByStakePercentExcept(_validatorPart, address(0));

        emit LogDistributeBlockReward(val, _validatorPart, block.timestamp);
    }

    function updateActiveValidatorSet(address[] memory newSet, uint256 epoch)
        public
        onlyMiner
        onlyNotUpdated
        onlyInitialized
        onlyBlockEpoch(epoch)
    {
        operationsDone[block.number][uint8(Operations.UpdateValidators)] = true;
        require(newSet.length > 0, "Validator set empty!");

        currentValidatorSet = newSet;

        emit LogUpdateValidator(newSet);
    }

    function removeValidator(address val) external onlyPunishContract {
        uint256 hb = validatorInfo[val].hbIncoming;

        tryRemoveValidatorIncoming(val);

        // remove the validator out of active set
        // Note: the jailed validator may in active set if there is only one validator exists
        if (highestValidatorsSet.length > 1) {
            tryJailValidator(val);
            emit LogRemoveValidator(val, hb, block.timestamp);
        }
    }

    function removeValidatorIncoming(address val) external onlyPunishContract {
        tryRemoveValidatorIncoming(val);
    }

    function getValidatorDescription(address val)
        public
        view
        returns (
            string memory,
            string memory,
            string memory,
            string memory,
            string memory
        )
    {
        Validator memory v = validatorInfo[val];

        return (
            v.description.moniker,
            v.description.identity,
            v.description.website,
            v.description.email,
            v.description.details
        );
    }

    function getValidatorInfo(address val)
        public
        view
        returns (
            address payable,
            Status,
            uint256,
            uint256,
            uint256,
            //uint256,
            address[] memory,
            valType
        )
    {
        Validator memory v = validatorInfo[val];

        return (
            v.feeAddr,
            v.status,
            v.coins,
            v.hbIncoming,
            v.totalJailedHB,
          //  v.lastWithdrawProfitsBlock,
            v.stakers,
            v.vType
        );
    }

    function getStakingInfo(address staker, address val)
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return (
            staked[staker][val].coins,
            staked[staker][val].unstakeBlock,
            staked[staker][val].index
        );
    }

    function getActiveValidators() public view returns (address[] memory) {
        return currentValidatorSet;
    }

    function getTotalStakeOfActiveValidators()
        public
        view
        returns (uint256 totalSuper, uint256 totalMaster, uint256 totalLittle, uint256 len)
    {
        return getTotalStakeOfActiveValidatorsExcept(address(0));
    }

    function getTotalStakeOfActiveValidatorsExcept(address val)
        private
        view
        returns (uint256 totalSuper, uint256 totalMaster, uint256 totalLittle, uint256 len)
    {
        for (uint256 i = 0; i < currentValidatorSet.length; i++) {
            if (
                validatorInfo[currentValidatorSet[i]].status != Status.Jailed &&
                val != currentValidatorSet[i]
            ) {
                if(validatorInfo[currentValidatorSet[i]].vType == valType.Super)
                {
                  totalSuper = totalSuper + (validatorInfo[currentValidatorSet[i]].coins);
                }
                else if(validatorInfo[currentValidatorSet[i]].vType == valType.Master)
                {
                  totalMaster = totalMaster + (validatorInfo[currentValidatorSet[i]].coins);
                }
                else
                {
                  totalLittle = totalLittle + (validatorInfo[currentValidatorSet[i]].coins);
                }

                len++;
            }
        }

        return (totalSuper, totalMaster, totalLittle, len);
    }

    function isActiveValidator(address who) public view returns (bool) {
        for (uint256 i = 0; i < currentValidatorSet.length; i++) {
            if (currentValidatorSet[i] == who) {
                return true;
            }
        }

        return false;
    }

    function isTopValidator(address who) public view returns (bool) {
        for (uint256 i = 0; i < highestValidatorsSet.length; i++) {
            if (highestValidatorsSet[i] == who) {
                return true;
            }
        }

        return false;
    }

    function getTopValidators() public view returns (address[] memory) {
        return highestValidatorsSet;
    }

    function validateDescription(
        string memory moniker,
        string memory identity,
        string memory website,
        string memory email,
        string memory details
    ) public pure returns (bool) {
        require(bytes(moniker).length <= 70, "Invalid moniker length");
        require(bytes(identity).length <= 3000, "Invalid identity length");
        require(bytes(website).length <= 140, "Invalid website length");
        require(bytes(email).length <= 140, "Invalid email length");
        require(bytes(details).length <= 280, "Invalid details length");

        return true;
    }

    function tryAddValidatorToHighestSet(address val, uint256 staking)
        internal
    {
        // do nothing if you are already in highestValidatorsSet set
        for (uint256 i = 0; i < highestValidatorsSet.length; i++) {
            if (highestValidatorsSet[i] == val) {
                return;
            }
        }

        if (highestValidatorsSet.length < MaxValidators) {
            highestValidatorsSet.push(val);
            emit LogAddToTopValidators(val, block.timestamp);
            return;
        }

        // find lowest validator index in current validator set
        uint256 lowest = validatorInfo[highestValidatorsSet[0]].coins;
        uint256 lowestIndex = 0;
        for (uint256 i = 1; i < highestValidatorsSet.length; i++) {
            if (validatorInfo[highestValidatorsSet[i]].coins < lowest) {
                lowest = validatorInfo[highestValidatorsSet[i]].coins;
                lowestIndex = i;
            }
        }

        // do nothing if staking amount isn't bigger than current lowest
        if (staking <= lowest) {
            return;
        }

        // replace the lowest validator
        emit LogAddToTopValidators(val, block.timestamp);
        emit LogRemoveFromTopValidators(
            highestValidatorsSet[lowestIndex],
            block.timestamp
        );
        highestValidatorsSet[lowestIndex] = val;
    }

    function tryRemoveValidatorIncoming(address val) private {
        // do nothing if validator not exist(impossible)
        if (
            validatorInfo[val].status == Status.NotExist ||
            currentValidatorSet.length <= 1
        ) {
            return;
        }

        uint256 hb = validatorInfo[val].hbIncoming;
        if (hb > 0) {
            addProfitsToActiveValidatorsByStakePercentExcept(hb, val);
            // for display purpose
            totalJailedHB = totalJailedHB + (hb);
            validatorInfo[val].totalJailedHB = validatorInfo[val]
                .totalJailedHB
                + (hb);

            validatorInfo[val].hbIncoming = 0;
        }

        emit LogRemoveValidatorIncoming(val, hb, block.timestamp);
    }

    // add profits to all validators by stake percent except the punished validator or jailed validator
    function addProfitsToActiveValidatorsByStakePercentExcept(
        uint256 totalReward,
        address punishedVal
    ) private {
        if (totalReward == 0) {
            return;
        }
        uint256 total0;
        uint256 total1;
        uint256 total2;
        uint256 totalRewardStake;
        uint256 rewardValsLen;
        (
            total0, total1, total2,
            rewardValsLen
        ) = getTotalStakeOfActiveValidatorsExcept(punishedVal);
        totalRewardStake = total0 + total1 + total2;
        if (rewardValsLen == 0) {
            return;
        }

        uint256 remain;
        address last;

        // no stake(at genesis period)
        if (totalRewardStake == 0) {
            uint256 per = totalReward / (rewardValsLen);
            remain = totalReward - (per * rewardValsLen);
            for (uint256 i = 0; i < currentValidatorSet.length; i++) {
                address val = currentValidatorSet[i];
                if (
                    validatorInfo[val].status != Status.Jailed &&
                    val != punishedVal
                ) {
                    validatorInfo[val].hbIncoming = validatorInfo[val]
                        .hbIncoming
                        + (per);

                    last = val;
                }
            }

            if (remain > 0 && last != address(0)) {
                validatorInfo[last].hbIncoming = validatorInfo[last]
                    .hbIncoming
                    + (remain);
            }
            return;
        }
        uint256 superReward = totalReward * valTypes[0].perc /100;
        uint256 masterReward = totalReward * valTypes[1].perc /100;
        uint256 littleReward = totalReward - superReward - masterReward;
        uint256 added;
        for (uint256 i = 0; i < currentValidatorSet.length; i++) {
            address val = currentValidatorSet[i];
            if (
                validatorInfo[val].coins > 0 && validatorInfo[val].status != Status.Jailed && val != punishedVal
            ) {
                uint256 reward;
                if(validatorInfo[val].vType == valType.Super)
                {
                  reward = superReward * (validatorInfo[val].coins) / (
                      total0
                  );
                }
                else if(validatorInfo[val].vType == valType.Master)
                  {
                    reward = masterReward * (validatorInfo[val].coins) / (
                        total1
                    );
                  }
                else{
                  reward = littleReward * (validatorInfo[val].coins) / (
                      total2
                  );
                }
                added = added + (reward);
                last = val;
                validatorInfo[val].hbIncoming = validatorInfo[val]
                    .hbIncoming
                    + (reward);
            }
        }

        remain = totalReward - (added);

        if(remain > 0 && charityWallet != address(0))
        {
          payable(charityWallet).transfer(remain);
        }
    }

    function tryJailValidator(address val) private {
        // do nothing if validator not exist
        if (validatorInfo[val].status == Status.NotExist) {
            return;
        }

        // set validator status to jailed
        validatorInfo[val].status = Status.Jailed;

        // try to remove if it's in active validator set
        tryRemoveValidatorInHighestSet(val);
    }

    function tryRemoveValidatorInHighestSet(address val) private {
        for (
            uint256 i = 0;
            // ensure at least one validator exist
            i < highestValidatorsSet.length && highestValidatorsSet.length > 1;
            i++
        ) {
            if (val == highestValidatorsSet[i]) {
                // remove it
                if (i != highestValidatorsSet.length - 1) {
                    highestValidatorsSet[i] = highestValidatorsSet[highestValidatorsSet
                        .length - 1];
                }

                highestValidatorsSet.pop();
                emit LogRemoveFromTopValidators(val, block.timestamp);

                break;
            }
        }
    }

    function viewStakeReward(address _staker, address _validator) public view returns(uint256){
        if(stakeTime[_staker][_validator] > 0){
            uint validPercent = reflectionPercentSum[_validator][lastRewardTime[_validator]] - reflectionPercentSum[_validator][stakeTime[_staker][_validator]];
            if(validPercent > 0)
            {
                StakingInfo memory stakingInfo = staked[_staker][_validator];
                return stakingInfo.coins * validPercent / 100000000000000000000  ;
            }
        }
        return 0;
    }
    function updateGasSettings(uint _validatorPartPercent, uint _charityPartPercent,
        uint _stakerPartPercent, address _charityWallet) external onlyOwner
    {
      require(_validatorPartPercent + charityPartPercent +  _stakerPartPercent  <= 100000, "Total has exceeded by 100%");
      require(_charityWallet != address(0), "Invalid address");
      validatorPartPercent = _validatorPartPercent;
      stakerPartPercent = _stakerPartPercent;
      charityPartPercent = _charityPartPercent;
      charityWallet = _charityWallet;
    }
    function updateParams(uint16 _MaxValidators, uint256 _MinimalStakingCoin) external onlyOwner
    {
      require(_MaxValidators > 0 && _MinimalStakingCoin > 0, 'Incorrect MaxValidators or MinimalStakingCoin');
      MaxValidators = _MaxValidators;
      MinimalStakingCoin = _MinimalStakingCoin;
    }
    function updateValidatorType(uint256 _index, uint256 minStakingAmount) external onlyOwner
    {
      require(_index < 3, 'Type should any from 0,1,2');
      require(minStakingAmount > 0, "Invalid amount");
      valTypes[_index].minStake = minStakingAmount;
    }
}
