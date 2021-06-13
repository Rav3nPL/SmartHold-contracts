// SPDX-License-Identifier: MIT

import "./interfaces.sol";

pragma solidity 0.8.4;

contract SmartHoldERC20 {
    address public immutable owner = msg.sender;
    uint256 public immutable createdAt = block.timestamp;

    address constant ZERO = address(0x0);

    struct Token {
        uint256 lockForDaysDurations;
        int256 minExpectedPrices;
        int256 pricePrecisions;
        address priceFeeds;
        address tokenAddresses;
    }
    Token[] public tokens;

    mapping(address => uint256) public tokenIndex;

    modifier restricted() {
        require(msg.sender == owner, "Access denied!");
        _;
    }

    function configureToken(
        address _tokenAddress,
        uint256 _lockForDays,
        address _feedAddress,
        int256 _minExpectedPrice,
        int256 _pricePrecision
    ) external restricted {
        require(tokenIndex[_tokenAddress] == 0, "Token already configured!");

        require(_lockForDays > 0, "Invalid lockForDays value.");
        require(_minExpectedPrice >= 0, "Invalid minExpectedPrice value.");
        if (
            (_feedAddress == ZERO && _minExpectedPrice != 0) ||
            (_minExpectedPrice == 0 && _feedAddress != ZERO)
        ) {
            require(false, "Invalid price configuration!");
        }

        if (_feedAddress != ZERO) {
            // check feed address interface
            PriceFeedInterface(_feedAddress).latestRoundData();
        }
        Token memory newOne;
        newOne.lockForDaysDurations = _lockForDays;
        newOne.tokenAddresses = _tokenAddress;
        newOne.priceFeeds = _feedAddress;
        newOne.minExpectedPrices = _minExpectedPrice;
        newOne.pricePrecisions = _pricePrecision;
        tokens.push(newOne);
        tokenIndex[_tokenAddress] = tokens.length; // we are missing "0" for reasons
    }

    function increaseMinExpectedPrice(
        address _symbol,
        int256 _newMinExpectedPrice
    ) external restricted {
        require(tokenIndex[_symbol] != 0, "Token not yet configured!");
        Token storage t = tokens[tokenIndex[_symbol] - 1];
        require(
            t.minExpectedPrices < _newMinExpectedPrice,
            "New price value invalid!"
        );
        t.minExpectedPrices = _newMinExpectedPrice;
    }

    function increaseLockForDays(address _symbol, uint256 _newLockForDays)
        external
        restricted
    {
        require(tokenIndex[_symbol] != 0, "Token not yet configured!");
        Token storage t = tokens[tokenIndex[_symbol] - 1];
        require(
            t.lockForDaysDurations < _newLockForDays,
            "New lockForDays value invalid!"
        );
        t.lockForDaysDurations = _newLockForDays;
    }

    function getPrice(address _symbol) public view returns (int256) {
        Token storage t = tokens[tokenIndex[_symbol] - 1];
        if (t.priceFeeds == ZERO) {
            return 0;
        }

        (, int256 price, , , ) =
            PriceFeedInterface(t.priceFeeds).latestRoundData();
        return price / t.pricePrecisions;
    }

    function canWithdraw(address _symbol) public view returns (bool) {
        require(tokenIndex[_symbol] != 0, "Token not yet configured!");
        Token storage t = tokens[tokenIndex[_symbol] - 1];

        uint256 releaseAt = createdAt + (t.lockForDaysDurations * 1 days);

        if (releaseAt < block.timestamp) {
            return true;
        } else if (t.minExpectedPrices == 0) {
            return false;
        } else if (t.minExpectedPrices < getPrice(_symbol)) {
            return true;
        } else return false;
    }

    function checkPriceFeed(address _feedAddress, int256 _precision)
        public
        view
        returns (int256)
    {
        (, int256 price, , , ) =
            PriceFeedInterface(_feedAddress).latestRoundData();
        return price / _precision;
    }

    function getConfiguredTokensCount() public view returns (uint256) {
        return tokens.length;
    }

    function withdraw(address _symbol) external restricted {
        require(canWithdraw(_symbol), "You cannot withdraw yet.");

        if (_symbol == ZERO) {
            payable(owner).transfer(address(this).balance);
        } else {
            IERC20 token = IERC20(_symbol);
            uint256 tokenBalance = token.balanceOf(address(this));
            if (tokenBalance > 0) {
                token.transfer(owner, tokenBalance);
            }
        }
    }

    receive() external payable {
        require(tokenIndex[ZERO] != 0, "ETH not configured");
    }
}
