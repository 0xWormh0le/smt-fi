// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IProtocolContract {

    function setProtocolAddress(address value) external;

    function getTokenAddress() external view returns(address);

    function mint(uint usdcAmount) external returns(uint);

    function redeem(uint tokenAmount) external returns(uint);
}
