// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;



interface InterfaceValidator {
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
      Diamond
    }
    struct Description {
        string moniker;
        string identity;
        string website;
        string email;
        string details;
    }

    function getTopValidators() external view returns(address[] memory);
    function getValidatorInfo(address val)external view returns(address payable, Status, uint256, uint256, uint256, address[] memory, valType);
    function getValidatorDescription(address val) external view returns ( string memory,string memory,string memory,string memory,string memory);
    function totalStake() external view returns(uint256);
    function getStakingInfo(address staker, address validator) external view returns(uint256, uint256, uint256);
    function viewStakeReward(address _staker, address _validator) external view returns(uint256);
    function MinimalStakingCoin() external view returns(uint256);
    function isTopValidator(address who) external view returns (bool);


    //write functions
     function createOrEditValidator(
        address payable feeAddr,
        string calldata moniker,
        string calldata identity,
        string calldata website,
        string calldata email,
        string calldata details,
        uint8 validatorType
    ) external payable  returns (bool);

   function unstake(address validator)
        external
        returns (bool);

    function stake(address validator)
        external payable
        returns (bool);


    function withdrawProfits(address validator) external returns (bool);
    function withdrawStakingReward(address validator) external returns(bool);
}


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

contract ValidatorHelper is Ownable {

    InterfaceValidator public valContract = InterfaceValidator(0x000000000000000000000000000000000000f000);
    uint256 public APY = 12;
    uint256 constant oneyear = 31104000;
    uint256 rewardspersec = APY * 1e12  / oneyear ;
    uint256 public rewardFund;
    mapping(address=>uint256) public totalProfitWithdrawn;
    mapping(address=>uint256) public lastRewardTime;
    mapping(address=>uint256) public pendingRewards;
    uint256 public minDuration = 604800 ; //1 week

    //events
    event Stake(address validator, uint256 amount, uint256 timestamp);
    event Unstake(address validator, uint256 timestamp);
    event WithdrawProfit(address validator, uint256 amount, uint256 timestamp);

    receive() external payable {
        rewardFund += msg.value;
    }

    function createOrEditValidator(
        address payable feeAddr,
        string calldata moniker,
        string calldata identity,
        string calldata website,
        string calldata email,
        string calldata details,
        uint8 validatorType
    ) external payable  returns (bool) {

        valContract.createOrEditValidator{value: msg.value}(feeAddr, moniker, identity, website, email, details, validatorType);
        lastRewardTime[msg.sender] = block.timestamp;
        emit Stake(msg.sender, msg.value, block.timestamp);

        return true;
    }
    function stake(address validator)
        external payable
        returns (bool)
    {

        uint256 vRewards = viewRewards(validator, msg.sender, true);
        if(vRewards > 0)
        {
            if(address(this).balance >= vRewards)
            {
                _withdrawStakingReward(validator,true);
            }
            else {
                pendingRewards[msg.sender] += vRewards;
            }
        }
        valContract.stake{value: msg.value}(validator);

        lastRewardTime[msg.sender] = block.timestamp;

        emit Stake(msg.sender, msg.value, block.timestamp);
        return true;
    }

    function unstake(address validator)
        external
        returns (bool)
    {
        uint256 vRewards = viewRewards(validator, msg.sender, true);
        uint256 hbIncoming;
        if(msg.sender==validator){
          (, , , hbIncoming, , , ) = valContract.getValidatorInfo(validator);
        }
        if(vRewards + hbIncoming > 0)
        {
          _withdrawStakingReward(validator,true);
        }
        valContract.unstake(validator);
        lastRewardTime[msg.sender] = 0;
        emit Unstake(msg.sender, block.timestamp);
        return true;
    }

    function withdrawStakingReward(address validator) public {
       _withdrawStakingReward(validator,false);
       lastRewardTime[msg.sender] = block.timestamp;
    }

    // Internal Function
    function _withdrawStakingReward(address validator, bool isUnstaked) internal {
        uint256 vRewards = viewRewards(validator, msg.sender, isUnstaked);
        require(address(this).balance >= vRewards, "Insufficient reward fund");
        uint256 stakerRewards = valContract.viewStakeReward(msg.sender,validator);
        uint256 hbIncoming;
        if(msg.sender==validator){
          (, , , hbIncoming, , , ) = valContract.getValidatorInfo(validator);
        }

        require(vRewards + hbIncoming + stakerRewards > 0, "Nothing to withdraw");
        if(hbIncoming>0){
         valContract.withdrawProfits(validator);
        }
        else if(stakerRewards > 0)
        {
          valContract.withdrawStakingReward(validator);
        }
        rewardFund -= vRewards;

        totalProfitWithdrawn[msg.sender] += vRewards;
        pendingRewards[msg.sender] = 0;
        payable(msg.sender).transfer(vRewards);

        emit WithdrawProfit( msg.sender,  vRewards,  block.timestamp);
    }



    /**
        admin functions
    */
    function rescueCoins() external onlyOwner{
        rewardFund -= address(this).balance;
        payable(msg.sender).transfer(address(this).balance);
    }
    function changeAPY(uint256 _APY) external onlyOwner{
        require(_APY > 0,'Invalid APY');
        APY = _APY;
        rewardspersec = _APY * 1e12  / oneyear ;
    }
    function changeMinDur(uint256 _dur) external onlyOwner
    {
        minDuration = _dur;
    }

    /**
        View functions
    */
    function viewRewards(address validator, address staker, bool isUnstake) public view returns(uint256 rewardAmount){

        (, InterfaceValidator.Status validatorStatus, , , , , ) = valContract.getValidatorInfo(validator);

        //if no staked Coins
       // uint256 unstakeBlock;

        (uint256 stakedCoins, uint256 unstakeBlock, ) = valContract.getStakingInfo(staker,validator);
        // if validator is jailed, or created, or unstaked, or not staked then he will not get any rewards
        if(stakedCoins==0 || unstakeBlock!=0 || validatorStatus == InterfaceValidator.Status.Jailed || validatorStatus == InterfaceValidator.Status.Created || validatorStatus == InterfaceValidator.Status.Unstaked ){
            return 0;
        }

        // if this smart contract has enough fund and if this validator is not unstaked,
        // then he will receive the rewards.
        // reward is dynamically calculated based on time passed
        if(lastRewardTime[staker] > 0 && address(this).balance > 0 && (lastRewardTime[staker] + minDuration <= block.timestamp || isUnstake)){
            rewardAmount = (rewardspersec * stakedCoins) * (block.timestamp - lastRewardTime[staker])/1e14;
        }
        rewardAmount += pendingRewards[msg.sender];
    }
    function getAllValidatorInfo() external view returns (uint256 totalValidatorCount,uint256 totalStakedCoins,address[] memory,InterfaceValidator.Status[] memory,uint256[] memory,string[] memory,string[] memory, InterfaceValidator.valType[] memory)
    {
        address[] memory highestValidatorsSet = valContract.getTopValidators();
        uint256 totalValidators = highestValidatorsSet.length;
	      uint256 totalunstaked ;
        InterfaceValidator.Status[] memory statusArray = new InterfaceValidator.Status[](totalValidators);
        uint256[] memory coinsArray = new uint256[](totalValidators);
        string[] memory identityArray = new string[](totalValidators);
        string[] memory websiteArray = new string[](totalValidators);
        InterfaceValidator.valType[] memory typeArray = new InterfaceValidator.valType[](totalValidators);

        for(uint8 i=0; i < totalValidators; i++){
        (, InterfaceValidator.Status status, uint256 coins, , , , InterfaceValidator.valType vType ) = valContract.getValidatorInfo(highestValidatorsSet[i]);
        if(coins>0){
            (, string memory identity, string memory website, ,) = valContract.getValidatorDescription(highestValidatorsSet[i]);

            statusArray[i] = status;
            coinsArray[i] = coins;
            identityArray[i] = identity;
            websiteArray[i] = website;
            typeArray[i] = vType;
          }
          else
          {
            totalunstaked += 1;
          }
        }
        return(totalValidators - totalunstaked , valContract.totalStake(), highestValidatorsSet, statusArray, coinsArray, identityArray, websiteArray, typeArray);
    }


    function validatorSpecificInfo1(address validatorAddress, address user) external view returns(string memory identityName, string memory website, string memory otherDetails, uint256 withdrawableRewards, uint256 stakedCoins, uint256 waitingBlocksForUnstake ){

        (, string memory identity, string memory websiteLocal, ,string memory details) = valContract.getValidatorDescription(validatorAddress);


        uint256 unstakeBlock;

        (stakedCoins, unstakeBlock, ) = valContract.getStakingInfo(user,validatorAddress);

        if(unstakeBlock!=0){
            waitingBlocksForUnstake = stakedCoins;
            stakedCoins = 0;
        }
        (, , , withdrawableRewards, , , ) = valContract.getValidatorInfo(validatorAddress);
        withdrawableRewards += valContract.viewStakeReward(user,validatorAddress) + viewRewards(validatorAddress,user, true);

        return(identity, websiteLocal, details, withdrawableRewards, stakedCoins, waitingBlocksForUnstake) ;
    }


    function validatorSpecificInfo2(address validatorAddress, address user) external view returns(uint256 totalStakedCoins, InterfaceValidator.Status status, uint256 selfStakedCoins, uint256 stakers, address, InterfaceValidator.valType vType){
        address[] memory stakersArray;
        (, status, totalStakedCoins, , , stakersArray, vType)  = valContract.getValidatorInfo(validatorAddress);

        (selfStakedCoins, , ) = valContract.getStakingInfo(validatorAddress,validatorAddress);

        return (totalStakedCoins, status, selfStakedCoins, stakersArray.length, user, vType);
    }

    function totalProfitEarned(address validator, address user) public view returns(uint256){
        return totalProfitWithdrawn[validator] + viewRewards(validator,user, false);
    }

    function minimumStakingAmount() external view returns(uint256){
        return valContract.MinimalStakingCoin();
    }

    function checkValidator(address user) external pure returns(bool){
        //this function is for UI compatibility
        return true;
    }
}
