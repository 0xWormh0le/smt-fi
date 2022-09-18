// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "../interface/IIdleTokenV3_1.sol";
import "./BaseProtocol.sol";

contract Idle is BaseProtocol {

    constructor(address _protocol) {
        require(_protocol != address(0), "Invalid protocol");
        setProtocolAddress(_protocol);
    }

    function mint(uint usdcAmount)
        external
        override
        returns(uint)
    {
        require(protocol != address(0), "Protocol not set");
        return IIdleTokenV3_1(protocol).mintIdleToken(usdcAmount, false, address(0));
    }

    function redeem(uint tokenAmount)
        external
        override
        returns(uint)
    {
        require(protocol != address(0), "Protocol not set");
        return IIdleTokenV3_1(protocol).redeemIdleToken(tokenAmount);
    }

    function getTokenAddress()
        public
        override
        view
        returns(address)
    {
        return IIdleTokenV3_1(protocol).token();
    }
}
