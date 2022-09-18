// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IProtocolContract {

    function setProtocolAddress(address value) external;

    /// @dev Get protocol token i.e idle
    function token() external view returns(address);

    /// @dev Get asset token i.e usdc
    function assetToken() external view returns(address);

    /// @dev Mint protocol token in exchange for asset token
    /// @return amount of protocol token minted
    function mint(uint assetAmount) external returns(uint);

    /// @dev Retrieve asset token in exchage for protocol token
    /// @return amount of asset token returned
    function redeem(uint tokenAmount) external returns(uint);
}
