pragma solidity ^0.7.0;
//SPDX-License-Identifier: UNLICENSED

interface IERC20 {
    function totalSupply() external view returns (uint);
    function balanceOf(address who) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);
    function transfer(address to, uint value) external returns (bool);
    function approve(address spender, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
    
    function unPauseTransferForever() external;
    function pangolinPair() external returns(address);
}

interface IPNG {
    function addLiquidityAVAX(address token, uint amountTokenDesired, uint amountTokenMin, uint amountAVAXMin, address to, uint deadline) 
    external 
    payable 
    returns (uint amountToken, uint amountAVAX, uint liquidity);
    
    function WAVAX() external pure returns (address);

}

abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor () {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.avaxeum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}


contract OsirisPresale is Context, ReentrancyGuard {
    using SafeMath for uint;
    IERC20 public OSIR;
    address public _burnPool = 0x000000000000000000000000000000000000dEaD;

    IPNG constant pangolin =  IPNG(0xE54Ca86531e17Ef3616d22Ca28b0D458b6C89106);

    uint public tokensBought;
    bool public isStopped = false;
    bool public teamClaimed = false;
    bool public moonMissionStarted = false;
    bool public isRefundEnabled = false;
    bool public presaleStarted = false;
    bool justTrigger = false;
    uint public teamTokens = 75000e9;
    uint constant daoReserve = 100000e9;
    
    address private incentivePool;
    uint256 private amountQueued;

    address payable owner;
    address payable constant team = 0xf8904AB5E0F38bbd0CbAE2Ff5935c0e693dD7012;
    address payable constant marketing = 0xd69e70cedB06634130ed51a7b1942b7a924F7f6E;

    address public pool;
    
    uint256 public avaxSent;
    uint256 constant tokensPerAVAX = 19;
    uint256 public lockedLiquidityAmount;
    uint256 public timeTowithdrawTeamTokens;
    uint256 public timeToWithdrawPool = block.timestamp.add(365 days);
    uint256 public incentivesTimeLocked = 0 days;
    bool public TimelockActive =  false;
    uint256 public refundTime; 
    mapping(address => uint) avaxSpent;
    
     modifier onlyOwner() {
        require(msg.sender == owner, "You are not the owner");
        _;
    }
    
    constructor() {
        owner = msg.sender; 
        refundTime = block.timestamp.add(7 days);
    }
    
    
    receive() external payable {
        
        buyTokens();
    }
    
    function SUPER_DUPER_EMERGENCY_ALLOW_REFUNDS_DO_NOT_FUCKING_CALL_IT_FOR_FUN() external onlyOwner nonReentrant {
        isRefundEnabled = true;
        isStopped = true;
    }
    
    function queueTokenToIncentivesPool(address _incentivePool, uint _amountQueued) external onlyOwner {
        require(block.timestamp >= incentivesTimeLocked, "There cannot be multiple timelocked Incentives");
        require(TimelockActive = false, "Timelock is still active");
        incentivePool = _incentivePool;
        amountQueued = _amountQueued;
        incentivesTimeLocked = block.timestamp.add(3 days);
        TimelockActive = true;
    }
    
    function sendTokenToIncentivesPool() external onlyOwner {
        require(block.timestamp >= incentivesTimeLocked, "Must be passed ");
        require(TimelockActive = true, "Transaction not queued");
        TimelockActive = false;
        OSIR.transfer(incentivePool, amountQueued);
    }
    
    function getRefund() external nonReentrant {
        require(msg.sender == tx.origin);
        require(!justTrigger);
        // Refund should be enabled by the owner OR 7 days passed 
        require(isRefundEnabled || block.timestamp >= refundTime,"Cannot refund");
        address payable user = msg.sender;
        uint256 amount = avaxSpent[user];
        avaxSpent[user] = 0;
        user.transfer(amount);
    }
    
    
    function withdrawPool() external onlyOwner nonReentrant {
        pool = OSIR.pangolinPair();
        IERC20 liquidityTokens = IERC20(pool);
        require(teamClaimed);
        require(block.timestamp >= timeToWithdrawPool, "Cannot withdraw yet");
        uint256 amount = liquidityTokens.balanceOf(address(this)); 
        liquidityTokens.transfer(team, amount);
    }
    
    function withdrawTeamTokens() external onlyOwner nonReentrant {
        require(teamClaimed);
        require(block.timestamp >= timeTowithdrawTeamTokens, "Cannot withdraw yet");
        uint256 tokensToClaim = 5000e9;
        require(teamTokens >= tokensToClaim, "Team Tokens have been claimed");
        teamTokens = teamTokens.sub(tokensToClaim);
        uint256 amount = tokensToClaim; 
        OSIR.transfer(team, amount);
        timeTowithdrawTeamTokens = block.timestamp.add(10 days);
    }

    function setOSIR(IERC20 addr) external onlyOwner nonReentrant {
        require(OSIR == IERC20(address(0)), "You can set the address only once");
        OSIR = addr;
    }
    
    function startPresale() external onlyOwner { 
        presaleStarted = true;
    }
    
     function pausePresale() external onlyOwner { 
        presaleStarted = false;
    }

    function buyTokens() public payable nonReentrant {
        require(msg.sender == tx.origin);
        require(presaleStarted == true, "Presale is paused, do not send AVAX");
        require(OSIR != IERC20(address(0)), "Main contract address not set");
        require(!isStopped, "Presale stopped by contract, do not send AVAX");
        require(msg.value >= 5 ether, "You cannot send less than 5 AVAX");
        require(msg.value <= 200 ether, "You cannot send more than 200 AVAX");
        require(avaxSent < 20000 ether, "Hard cap reached");
        require (msg.value.add(avaxSent) <= 20000 ether, "Hardcap will be reached");
        require(avaxSpent[msg.sender].add(msg.value) <= 200 ether, "You cannot buy more");
        uint256 tokens = msg.value.mul(tokensPerAVAX).div(10**9);
        require(OSIR.balanceOf(address(this)) >= tokens, "Not enough tokens in the contract");
        avaxSpent[msg.sender] = avaxSpent[msg.sender].add(msg.value);
        tokensBought = tokensBought.add(tokens);
        avaxSent = avaxSent.add(msg.value);
        OSIR.transfer(msg.sender, tokens);
    }
   
    function userAvaxSpenttInPresale(address user) external view returns(uint){
        return avaxSpent[user];
    }
    
 
    
    function allocateAndAddLiquidity() external onlyOwner  {
       require(!teamClaimed);
       uint256 amountAVAX = address(this).balance.mul(15).div(100); 
       uint256 amountAVAX2 = address(this).balance.mul(10).div(100);
       teamClaimed = true; //prevent reentrancys 
       team.transfer(amountAVAX);
       marketing.transfer(amountAVAX2);
       
       
       addLiquidity();
    }
    
        
    function addLiquidity() internal {
        uint256 AVAX = address(this).balance;
        uint256 tokensForPangolin = address(this).balance.mul(17).div(10 ** 9); //14 OSIR per AVAX
        uint256 tokensToBurn = OSIR.balanceOf(address(this)).sub(tokensForPangolin).sub(teamTokens)
        .sub(daoReserve);
        
        OSIR.unPauseTransferForever();
        OSIR.approve(address(pangolin), tokensForPangolin);
        pangolin.addLiquidityAVAX
        { value: AVAX }
        (
            address(OSIR),
            tokensForPangolin,
            tokensForPangolin,
            AVAX,
            address(this),
            block.timestamp
        );
       
       if (tokensToBurn > 0){
           OSIR.transfer(_burnPool ,tokensToBurn);
       }
       
       justTrigger = true;
       
        if(!isStopped)
            isStopped = true;
            
   }
    
}


library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}
