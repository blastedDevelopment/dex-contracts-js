// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.5.16;

import './interfaces/IBlastedPair.sol';
import './BlastedERC20.sol';
import './libraries/Math.sol';
import './libraries/UQ112x112.sol';
import './interfaces/IERC20.sol';
import './interfaces/IBlastedFactory.sol';
import './interfaces/IBlastedCallee.sol';


interface IERC20Rebasing {
  function configure(uint8 mode) external returns (uint256);
  function claim(address recipient, uint256 amount) external returns (uint256);
  function getClaimableAmount(address account) external view returns (uint256);
}

interface IBlast {
    // configure
    function configureContract(address contractAddress, uint8 _yield, uint8 gasMode, address governor) external;
    function configure(uint8 _yield, uint8 gasMode, address governor) external;

    // base configuration options
    function configureClaimableYield() external;
    function configureClaimableYieldOnBehalf(address contractAddress) external;
    function configureAutomaticYield() external;
    function configureAutomaticYieldOnBehalf(address contractAddress) external;
    function configureVoidYield() external;
    function configureVoidYieldOnBehalf(address contractAddress) external;
    function configureClaimableGas() external;
    function configureClaimableGasOnBehalf(address contractAddress) external;
    function configureVoidGas() external;
    function configureVoidGasOnBehalf(address contractAddress) external;
    function configureGovernor(address _governor) external;
    function configureGovernorOnBehalf(address _newGovernor, address contractAddress) external;

    // claim yield
    function claimYield(address contractAddress, address recipientOfYield, uint256 amount) external returns (uint256);
    function claimAllYield(address contractAddress, address recipientOfYield) external returns (uint256);

    // claim gas
    function claimAllGas(address contractAddress, address recipientOfGas) external returns (uint256);
    function claimGasAtMinClaimRate(address contractAddress, address recipientOfGas, uint256 minClaimRateBips) external returns (uint256);
    function claimMaxGas(address contractAddress, address recipientOfGas) external returns (uint256);
    function claimGas(address contractAddress, address recipientOfGas, uint256 gasToClaim, uint256 gasSecondsToConsume) external returns (uint256);

    // read functions
    function readClaimableYield(address contractAddress) external view returns (uint256);
    function readYieldConfiguration(address contractAddress) external view returns (uint8);
    function readGasParams(address contractAddress) external view returns (uint256 etherSeconds, uint256 etherBalance, uint256 lastUpdated, uint8);
}
interface IBlastPoints {
	function configurePointsOperator(address operator) external;
}

contract BlastedPair is IBlastedPair, BlastedERC20 {
    using SafeMath  for uint;
    using UQ112x112 for uint224;
    
    uint256 public nextRebase;
    uint public constant MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    // Oracle data start
    uint256 private reserve0CumulativeLast; 
    uint256 private reserve1CumulativeLast; 

    uint256 public lastObservationPoint;
    uint256 public constant periodSize = 1800;
    Observation[] public observations;

    struct Observation {
        uint256 _blockTimestamp;
        uint256 _reserve0CumulativeLast;
        uint256 _reserve1CumulativeLast;
    }
    // Oracle data end

    address public factory;
    address public token0;
    address public token1;

    uint112 private reserve0;           // uses single storage slot, accessible via getReserves
    uint112 private reserve1;           // uses single storage slot, accessible via getReserves
    uint32  private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    uint public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    
    IBlast public constant BLAST = IBlast(0x4300000000000000000000000000000000000002);
    IERC20Rebasing public constant USDB = IERC20Rebasing(0x4200000000000000000000000000000000000022);
    IERC20Rebasing public constant WETH = IERC20Rebasing(0x4200000000000000000000000000000000000023);
    address BlastPointsAddressTestnet = 0x2fc95838c71e76ec69ff817983BFf17c710F34E0;

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'Blasted: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    // Oracle getters start

    function quote(
        address tokenIn,
        uint256 amountIn,
        uint256 granularity
    ) external view returns (uint256 amountOut) {
        uint256[] memory _prices = sample(tokenIn, amountIn, granularity, 1);
        uint256 priceAverageCumulative;
        uint256 _length = _prices.length;
        for (uint256 i = 0; i < _length; i++) {
            priceAverageCumulative += _prices[i];
        }
        return priceAverageCumulative / granularity;
    }

    function sample(
        address tokenIn,
        uint256 amountIn,
        uint256 points,
        uint256 window
    ) public view returns (uint256[] memory) {
        uint256[] memory _prices = new uint256[](points);

        uint256 length = observations.length - 1;
        uint256 i = length - (points * window);
        uint256 nextIndex = 0;
        uint256 index = 0;

        for (; i < length; i += window) {
            nextIndex = i + window;
            uint256 timeElapsed = observations[nextIndex]._blockTimestamp -
                observations[i]._blockTimestamp;
            uint256 _reserve0 = (observations[nextIndex]._reserve0CumulativeLast -
                observations[i]._reserve0CumulativeLast) / timeElapsed;
            uint256 _reserve1 = (observations[nextIndex]._reserve1CumulativeLast -
                observations[i]._reserve1CumulativeLast) / timeElapsed;
            _prices[index] = _getAmountOut(
                amountIn,
                tokenIn,
                _reserve0,
                _reserve1
            );
            index = index + 1;
        }
        return _prices;
    }
    
        function _getAmountOut(
        uint256 amountIn,
        address tokenIn,
        uint256 _reserve0,
        uint256 _reserve1
    ) internal view returns (uint256) {
            (uint256 reserveA, uint256 reserveB) = tokenIn == token0
                ? (_reserve0, _reserve1)
                : (_reserve1, _reserve0);
            return (amountIn * reserveB) / (reserveA + amountIn);
        
    }

    function lastObservation() public view returns (uint256 _blockTimestamp, uint256 _reserve0CumulativeLast, uint256 _reserve1CumulativeLast) {
        Observation storage lastObs = observations[observations.length - 1];
        return (lastObs._blockTimestamp, lastObs._reserve0CumulativeLast, lastObs._reserve1CumulativeLast);
    }

    function observationLength() external view returns (uint256) {
        return observations.length;
    }

    // Oracle getters end

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Blasted: TRANSFER_FAILED');
    }

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);
    event ClaimedRebasingTokens(address indexed feeTo, uint256 claimedUSDB, uint256 claimedWETH);

    constructor() public {
        factory = msg.sender;
        USDB.configure(2);
        WETH.configure(2);
        uint256 shouldClaimInterval = IBlastedFactory(factory).shouldClaimInterval();
        nextRebase = shouldClaimInterval + block.timestamp;
        address pointController = IBlastedFactory(factory).pointController();
        IBlastPoints(BlastPointsAddressTestnet).configurePointsOperator(pointController);
        address gasStation = IBlastedFactory(factory).gasStation();
        BLAST.configureClaimableGas();
        BLAST.configureGovernor(gasStation); 
        observations.push(Observation(block.timestamp, 0, 0));
    }

    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, 'Blasted: FORBIDDEN'); // sufficient check
        token0 = _token0;
        token1 = _token1;
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= uint112(-1) && balance1 <= uint112(-1), 'Blasted: OVERFLOW');
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);

        // Oracle set data start

        uint256 trueBlockTimestamp = block.timestamp;
        uint256 _lastObservation = observations[observations.length - 1]._blockTimestamp;
        uint256 timeElapsedObservation = periodSize - 1;
        if(trueBlockTimestamp > _lastObservation) {
        timeElapsedObservation = trueBlockTimestamp - _lastObservation;
        }
        if (timeElapsedObservation > 0 && _reserve0 != 0 && _reserve1 != 0) {
            reserve0CumulativeLast += uint256(_reserve0) * timeElapsed;
            reserve1CumulativeLast += uint256(_reserve1) * timeElapsed;
        }

        if (timeElapsedObservation >= periodSize) {
                 observations.push(
                Observation(
                    trueBlockTimestamp,
                    reserve0CumulativeLast,
                    reserve1CumulativeLast
                )
            );
        }

        // Oracle set data end

        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // if fee is on, mint liquidity equivalent to 8/25 of the growth in sqrt(k)
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = IBlastedFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint rootK = Math.sqrt(uint(_reserve0).mul(_reserve1));
                uint rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint numerator = totalSupply.mul(rootK.sub(rootKLast)).mul(8);
                    uint denominator = rootK.mul(17).add(rootKLast.mul(8));
                    uint liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    function _claimRebasingTokens() private {
        address rebaseRecipient = IBlastedFactory(factory).rebaseRecipient();
        uint256 claimableUSDB = USDB.getClaimableAmount(address(this));
        uint256 claimableWETH = WETH.getClaimableAmount(address(this));
        uint256 claimedUSDB = 0;
        uint256 claimedWETH = 0;
        uint256 shouldClaimInterval = IBlastedFactory(factory).shouldClaimInterval();
        nextRebase = shouldClaimInterval + block.timestamp;
        if (claimableUSDB > 0) {
            claimedUSDB = USDB.claim(rebaseRecipient, claimableUSDB);
        }
        if (claimableWETH > 0) {
            claimedWETH = WETH.claim(rebaseRecipient, claimableWETH);
        }
        if (claimedUSDB > 0 || claimedWETH > 0) {
            emit ClaimedRebasingTokens(rebaseRecipient, claimedUSDB, claimedWETH);
        }
    }

    function claimRebasingTokens() external {
        _claimRebasingTokens();
    }

    function _shouldClaim() private view returns (bool) {
        bool isToken0Rebasing = token0 == address(USDB) || token0 == address(WETH);
        bool isToken1Rebasing = token1 == address(USDB) || token1 == address(WETH);
        return (isToken0Rebasing || isToken1Rebasing) && (block.timestamp >= nextRebase);
    }

    function shouldClaim() public view returns (bool) {
        return _shouldClaim();
    }


    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external lock returns (uint liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        uint amount0 = balance0.sub(_reserve0);
        uint amount1 = balance1.sub(_reserve1);

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
           _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);
        }
        require(liquidity > 0, 'Blasted: INSUFFICIENT_LIQUIDITY_MINTED');
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external lock returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        address _token0 = token0;                                // gas savings
        address _token1 = token1;                                // gas savings
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        uint liquidity = balanceOf[address(this)];
        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = liquidity.mul(balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity.mul(balance1) / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, 'Blasted: INSUFFICIENT_LIQUIDITY_BURNED');
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
        if (_shouldClaim()) {
            _claimRebasingTokens();
            uint256 shouldClaimInterval = IBlastedFactory(factory).shouldClaimInterval();
            nextRebase = shouldClaimInterval + block.timestamp;
        }
        require(amount0Out > 0 || amount1Out > 0, 'Blasted: INSUFFICIENT_OUTPUT_AMOUNT');
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'Blasted: INSUFFICIENT_LIQUIDITY');

        uint balance0;
        uint balance1;
        { // scope for _token{0,1}, avoids stack too deep errors
        address _token0 = token0;
        address _token1 = token1;
        require(to != _token0 && to != _token1, 'Blasted: INVALID_TO');
        if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
        if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
        if (data.length > 0) IBlastedCallee(to).blastedCall(msg.sender, amount0Out, amount1Out, data);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'Blasted: INSUFFICIENT_INPUT_AMOUNT');
        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
        uint balance0Adjusted = (balance0.mul(10000).sub(amount0In.mul(25)));
        uint balance1Adjusted = (balance1.mul(10000).sub(amount1In.mul(25)));
        require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(10000**2), 'Blasted: K');
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // force balances to match reserves
    function skim(address to) external lock {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)).sub(reserve0));
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)).sub(reserve1));
    }

    // force reserves to match balances
    function sync() external lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }
}
