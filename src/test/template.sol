pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./interface.sol";

//CONSTANTS
CheatCodes constant cheat = CheatCodes(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
// Attacker Contract 
// Attacker Address
// Vulnerable Contract
// Token contract addresses (i.e USDT token contract, EGD, etc)

/* Simutated Attacker 
- Do set up
- Triggers function that lives on the attacker contract to start the exploit
- Log balances before and after exploit (if needed)
*/
contract Attacker is Test {
    Exploit exploit = new Exploit(); // instantiate the attacker contract

    function setUp() public {
        //Label addresses for better readability in the logs
        // i.e: cheat.label(address(USDT_WBNB_LPPool), "USDT_WBNB_LPPool");

        // fork from block number
        cheat.createSelectFork("bsc", 21_297_409);
        vm.createSelectFork("mainnet", blocknumToForkFrom);
        cheat.roll(21297409);
        console.log("-------------------------------- Start Exploit ----------------------------------");
    }

    function testExploit() public {
        // log balances before the exploit
        emit log_named_decimal_uint("[Start] Attacker USDT balance before exploit", USDT.balanceOf(address(this)), 18)
        
        // call the attack function on the attacker contract
        exploit.bbb();   

        console.log("-------------------------------- End Exploit ----------------------------------");  
        // log balances after the exploit
        emit log_named_decimal_uint("[End] Attacker USDT balance after exploit", USDT.balanceOf(address(this)), 18);
    }
    // Signatures for any function that gets called by the attacker code
    // function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) public {}
}

// attacker contract
contract Exploit is Test{    
    // needed variables
    // address public _token0;
    // address public _token1;

    function bbb() public {
        // exploit code goes here
        // derived based on the vulnerability analysis
        // understand the attack's logic and implement a straightforward flow here
    }

    /* Any functions that get involved/called during bbb() should be listed here 
    function token0() public view returns (address) {
        return _token0;
    }

    function token1() public view returns (address) {
        return _token1;
    }
    */
    
}


/* INTERFACES
// i.e: Victim interfaces that include functions that will be called by the attacker contract
interface MEVBot {
    function pancakeCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}

i.e: Interfaces that contain functions that will be triggered during the exploit, but not on attacker contract code
interface IDexRouter {
    function uniswapV3SwapTo(
        uint256 receiver,
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata pools
    ) external payable returns (uint256 returnAmount);
}

interface IDRLVault {
    function swapToWETH(
        uint256 _amount
    ) external returns (uint256 _amountOut);
}
 */



