// SPDX-License-Identifier: UNLICENSED

/**
 * Contract is deployed on Goerli Chain For Testing
 *
 * Requirements:
 *
 * Test ERC20 Tokens.
 * Mapping of mainnet to child contract.
 * Using PoS Chain.
 */

/**
 * Key variables:
 *
 * Test Token Contract: 0x655f2166b0709cd575202630952d71e2bb0d61af
 * Root Chain Manager: 0xBbD7cBFA79faee899Eaf900F13C9065bF03B1A74
 * ERC20 Predicate: 0xdD6596F2029e6233DEFfaCa316e6A95217d4Dc34
 */
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interface/IRootChainManager.sol";
import "../utils/Context.sol";

contract InterLayerComm is Context {
    IRootChainManager private manager;

    address public depositManager;
    address public tokenContract;
    address public predicate;

    /**
     * @dev creates an instance of the token contract & deposit manager
     * during deployment
     *
     * {tokenContract_} creates an instance of the token
     * {predicateContract_} creates an instance of the deposit manager
     */
    constructor(
        address _tokenContract,
        address _predicateContract,
        address _predicateProxy
    ) {
        manager = IRootChainManager(_predicateContract);

        tokenContract = _tokenContract;
        depositManager = _predicateContract;
        predicate = _predicateProxy;
    }

    /**
     * @dev approves the token balance of the SC and initiates a deposit to matic.
     *
     * `caller` should be a governor of the contract.
     * For testing ownability is not declared.
     */
    function depositToMatic() public virtual returns (bool) {
        uint256 tokenBalance = IERC20(tokenContract).balanceOf(address(this));
        require(tokenBalance > 0, "Error: insufficient balance");

        _beforeTokenTransfer(address(this), address(this), tokenBalance);

        /**
         * For Test reasons depositing to a ERC20 wallet in ethereum. Not to lost test tokens.
         *
         * Test tokens are rarer.
         */
        IERC20(tokenContract).approve(predicate, tokenBalance);
        manager.depositFor(
            _msgSender(),
            tokenContract,
            abi.encode(tokenBalance)
        );

        return true;
    }

    /**
     * @dev returns the balance of `owner`
     *
     * Added for debugging
     */
    function balanceOf() public view virtual returns (uint256) {
        return IERC20(tokenContract).balanceOf(address(this));
    }

    /**
     * @dev returns the allowance of `predicate` over the `owner`
     *
     * Added for debugging
     */
    function allowance() public view virtual returns (uint256) {
        return IERC20(tokenContract).allowance(address(this), depositManager);
    }

    /**
     * @dev returns the bytes equivalent of the balance of token
     */
    function byteEq() public view virtual returns (bytes memory) {
        uint256 balance = IERC20(tokenContract).balanceOf(address(this));
        return abi.encodePacked(balance);
    }

    function _beforeTokenTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        /**
         * Hook to check conditions before transfer.
         */
    }
}
