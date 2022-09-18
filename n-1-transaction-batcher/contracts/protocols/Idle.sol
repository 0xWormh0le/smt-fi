// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";
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
        address usdc = assetToken();
        address idle = token();

        require(protocol != address(0), "IdleProtocol: Protocol not set");
        require(IERC20(usdc).balanceOf(address(this)) >= usdcAmount, "IdleProtocol: Not enough asset to mint token");
        require(IERC20(usdc).approve(protocol, usdcAmount));

        uint minted = IIdleTokenV3_1(protocol).mintIdleToken(usdcAmount, false, address(0));
        require(IERC20(idle).transfer(msg.sender, minted), "IdleProtocol: Failed to send minted idle token to router contract");

        return minted;
    }

    function redeem(uint tokenAmount)
        external
        override
        returns(uint)
    {
        address usdc = assetToken();
        address idle = token();

        require(protocol != address(0), "IdleProtocol: Protocol not set");
        require(IERC20(idle).balanceOf(address(this)) >= tokenAmount, "IdleProtocol: Not enough token to redeem");
        require(IERC20(idle).approve(protocol, tokenAmount));

        uint redeemed = IIdleTokenV3_1(protocol).redeemIdleToken(tokenAmount);
        require(IERC20(usdc).transfer(msg.sender, redeemed), "IdleProtocol: Failed to send redeemed usdc to router contract");

        return redeemed;
    }

    function token()
        public
        override
        view
        returns(address)
    {
        return protocol;
    }

    function assetToken()
        public
        override
        view
        returns(address)
    {
        return IIdleTokenV3_1(protocol).token();
    }
}
