// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

contract GasTracker {
    struct UserData {
        mapping(uint256 => uint256) dailyGas;
    }

    mapping(address => UserData) private userData;
    mapping(uint256 => uint256) public totalGasPerDayUsed;
    uint256 public contractDeployedTime;

    constructor() {
        contractDeployedTime = block.timestamp;
    }

    function updateGasUsage(uint256 startGas) internal {
        uint256 gasSpent = startGas - gasleft();
        uint256 currentDay = getCurrentDay();
        userData[msg.sender].dailyGas[currentDay] += gasSpent;
        totalGasPerDayUsed[currentDay] += gasSpent;
    }

    function exampleFunction() public {
        uint256 startGas = gasleft();

        // Logic here

        updateGasUsage(startGas);
    }

    function getCurrentDay() public view returns (uint256) {
        return (block.timestamp - contractDeployedTime) / 1 days;
    }

    function viewUserGasUsage(address user, uint256 day) public view returns (uint256) {
        return userData[user].dailyGas[day];
    }
}
