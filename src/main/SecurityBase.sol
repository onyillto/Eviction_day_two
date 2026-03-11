// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/Errors.sol";
import "../helpers/Events.sol";

abstract contract SecurityBase {

    //governance address
    address public governance;

    //emergency stop flag
    bool public stopped;

    //reentrancy lock
    uint256 private _lockStatus;

    //reentrancy constants
    uint256 private constant _NOT_LOCKED = 1;
    uint256 private constant _LOCKED = 2;


    // ========================
    // MODIFIERS
    // ========================

    //only governance can call
    modifier onlyGovernance() {
        if (msg.sender != governance) {
            revert Errors.Unauthorized(msg.sender);
        }
        _;
    }

    //block calls when emergency stop is active
    modifier whenNotStopped() {
        if (stopped) {
            revert Errors.Unauthorized(msg.sender);
        }
        _;
    }

    //reentrancy guard
    modifier nonReentrant() {
        if (_lockStatus == _LOCKED) {
            revert Errors.Reentrancy();
        }
        _lockStatus = _LOCKED;
        _;
        _lockStatus = _NOT_LOCKED;
    }

    //only specific address can call
    modifier onlyAddress(address allowed) {
        if (msg.sender != allowed) {
            revert Errors.Unauthorized(msg.sender);
        }
        _;
    }


    // ========================
    // CONSTRUCTOR
    // ========================

    constructor(address _governance) {
        if (_governance == address(0)) {
            revert Errors.ZeroAddress();
        }
        governance = _governance;
        _lockStatus = _NOT_LOCKED;
        stopped = false;
    }


    // ========================
    // GOVERNANCE FUNCTIONS
    // ========================

    //transfer governance to new address
    function updateGovernance(address newGovernance) public virtual onlyGovernance {
        if (newGovernance == address(0)) {
            revert Errors.ZeroAddress();
        }
        emit Events.GovernanceUpdated(governance, newGovernance);
        governance = newGovernance;
    }

    //trigger emergency stop
    function emergencyStop() public virtual onlyGovernance {
        stopped = true;
        emit Events.EmergencyStop(msg.sender, block.timestamp);
    }

    //resume after emergency stop
    function resume() public virtual onlyGovernance {
        stopped = false;
    }

}