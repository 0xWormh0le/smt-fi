pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";
import "./Erc20Mock.sol";
import "../interface/IIdleTokenV3_1.sol";


contract IdleTokenV3Mock is IIdleTokenV3_1, Erc20Mock {
    uint256 private _price;
    address private _token;

    constructor(address token_) Erc20Mock("IdleToken", "IdleToken") {
        _token = token_;
    }

    function tokenPrice() public view override returns (uint256) {
        return _price;
    }

    function token() public view override returns (address) {
        return _token;
    }

    function getAPRs()
        public
        view
        override
        returns (address[] memory, uint256[] memory)
    {}

    function mintIdleToken(
        uint256 _amount,
        bool _skipRebalance,
        address _referral
    ) public virtual override returns (uint256) {
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        _mint(msg.sender, _amount);

        return _amount;
    }

    function redeemIdleToken(uint256 _amount)
        public
        virtual
        override
        returns (uint256)
    {
        _burn(msg.sender, _amount);
        IERC20(_token).transfer(msg.sender, _amount);

        return _amount;
    }

    function redeemInterestBearingTokens(uint256 _amount)
        public
        virtual
        override
    {}

    function rebalance() public virtual override returns (bool) {}
}
