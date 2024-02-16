// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.5.16;

import './interfaces/IBlastedFactory.sol';
import './BlastedPair.sol';

contract BlastedFactory is IBlastedFactory {
    bytes32 public constant INIT_CODE_PAIR_HASH = keccak256(abi.encodePacked(type(BlastedPair).creationCode));

    address public gasStation; // gas station reclaims fees, and distribute it back to users
    address public rebaseRecipient;
    address public feeTo;
    address public feeToSetter;
    uint256 public shouldClaimInterval = 7 minutes; // 1 week on main

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor(address _feeToSetter, address _rebaseRecipient, address _gasStation) public {
        feeToSetter = _feeToSetter;
        rebaseRecipient = _rebaseRecipient;
        gasStation = _gasStation;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, 'Blasted: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'Blasted: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'Blasted: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(BlastedPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IBlastedPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setShouldClaimInterval(uint256 _shouldClaimInterval) external {
        require(msg.sender == feeToSetter, 'Blasted: FORBIDDEN');
        shouldClaimInterval = _shouldClaimInterval;
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'Blasted: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setGasStation(address _gasStation) external {
        require(msg.sender == feeToSetter, 'Blasted: FORBIDDEN');
        feeTo = _gasStation;
    }

    function setRebaseRecipient(address _rebaseRecipient) external {
        require(msg.sender == feeToSetter, 'Blasted: FORBIDDEN');
        rebaseRecipient = _rebaseRecipient;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'Blasted: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
}
