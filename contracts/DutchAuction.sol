// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract DutchAuction is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public startDate;
    uint256 public endDate;
    uint256 public startPrice;
    uint256 public minimumPrice;
    uint256 public totalTokens; // Amount to be sold
    uint256 public priceDrop; // Price reduction from startPrice at endDate
    uint256 public commitmentsTotal;
    bool private initialised;
    bool public finalised;

    address public auctionToken;
    address public adminAddress;
    mapping(address => uint256) public commitments;

    /* ========== EVENTS ========== */
    event InitDutchAuction(
        address indexed executor,
        uint256 at,
        address adminAddress,
        address token,
        uint256 startDate,
        uint256 endDate,
        uint256 startPrice,
        uint256 minimumPrice,
        uint256 priceDrop
    );
    event AddedCommitment(address indexed addr, uint256 commitment, uint256 price);
    event SetTotalTokens(uint256 indexed totalTokens);
    event Withdraw(address indexed to, uint256 amount);
    event Claim(address indexed to, uint256 amount);
    event FinaliseAuction(bool indexed status);

    modifier onlyAdmin() {
        require(msg.sender == adminAddress, "DutchAuction: only admin");
        _;
    }

    modifier auctionEnded() {
        require(
            _isAuctionSuccessful() || block.timestamp > endDate,
            "DutchAuction: auction not ended"
        );
        _;
    }

    function initDutchAuction(
        address _adminAddress,
        address _token,
        uint256 _startDate,
        uint256 _endDate,
        uint256 _startPrice,
        uint256 _minimumPrice
    ) external {
        require(!initialised, "DutchAuction: already initialised");
        require(_endDate > _startDate, "DutchAuction: invalid end date");
        require(_minimumPrice > 0, "DutchAuction: invalid minimum price");

        auctionToken = _token;
        adminAddress = _adminAddress;

        startDate = _startDate;
        endDate = _endDate;
        startPrice = _startPrice;
        minimumPrice = _minimumPrice;

        uint256 numerator = startPrice - minimumPrice;
        uint256 denominator = endDate - startDate;
        priceDrop = numerator / denominator;

        initialised = true;

        emit InitDutchAuction(
            msg.sender,
            block.number,
            _adminAddress,
            _token,
            startDate,
            _endDate,
            _startPrice,
            _minimumPrice,
            priceDrop
        );
    }

    function setTotalTokens() external onlyAdmin {
        uint256 _totalTokens = IERC20(auctionToken).balanceOf(address(this));
        totalTokens = _totalTokens;

        emit SetTotalTokens(_totalTokens);
    }

    /**
     * @notice Functon to claim user tokens
     */
    function claim() external auctionEnded nonReentrant {
        if (_isAuctionSuccessful()) {
            uint256 _tokensToClaim = _tokensClaimable(msg.sender);

            IERC20(auctionToken).safeTransfer(msg.sender, _tokensToClaim);

            emit Claim(msg.sender, _tokensToClaim);
        } else {
            uint256 _fundsCommitted = commitments[msg.sender];
            commitments[msg.sender] = 0;

            payable(msg.sender).transfer(_fundsCommitted);
        }
    }

    /**
     * @notice Functon to withdraw amount
     * @param _token token address
     * @param _amount amount
     */
    function withdraw(address _token, uint256 _amount) external onlyAdmin {
        require(IERC20(_token).balanceOf(address(this)) >= _amount, "DutchAuction: Invalid amount");
        IERC20(_token).safeTransfer(msg.sender, _amount);

        emit Withdraw(msg.sender, _amount);
    }

    /**
     * @notice Functon to finalize Auction
     */
    function finaliseAuction() external onlyAdmin {
        finalised = true;

        emit FinaliseAuction(true);
    }

    /**
     * @notice Functon to place bid for buy token
     */
    function placeBid() external payable {
        require(!finalised, "DutchAuction: Auction was finalised");
        require(
            block.timestamp >= startDate && block.timestamp <= endDate,
            "DutchAuction: Outside auction hours"
        );

        uint256 _commitment = _calculateCommitment(msg.value);

        uint256 _refund = msg.value - _commitment;
        if (_commitment > 0) {
            _addCommitment(msg.sender, _commitment);
        }
        if (_refund > 0) {
            payable(msg.sender).transfer(_refund);
        }
    }

    /**
     * @notice Returns the current clearing price of the Dutch auction
     */
    function clearingPrice() external view returns (uint256) {
        return _clearingPrice();
    }

    /**
     * @notice Returns how many tokens the user is able to claim
     */
    function tokensClaimable() external view returns (uint256) {
        return _tokensClaimable(msg.sender);
    }

    /**
     * @notice Returns total amount of tokens remaining
     */
    function tokensRemaining() external view returns (uint256) {
        uint256 _totalCommitted = (commitmentsTotal * 1e18) / _clearingPrice();
        if (_totalCommitted >= totalTokens) {
            return 0;
        } else {
            return totalTokens - _totalCommitted;
        }
    }

    /**
     * @notice Commits to an amount during an auction
     */
    function _addCommitment(address _addr, uint256 _commitment) private {
        commitments[_addr] += _commitment;
        commitmentsTotal += _commitment;

        emit AddedCommitment(_addr, _commitment, _currentPrice());
    }

    /**
     * @notice Returns the amount able to be committed during an auction
     * @param _commitment commitment
     */
    function _calculateCommitment(uint256 _commitment) private view returns (uint256) {
        uint256 maxCommitment = (totalTokens * _clearingPrice()) / 1e18;
        if (commitmentsTotal + _commitment > maxCommitment) {
            return maxCommitment - commitmentsTotal;
        }
        return _commitment;
    }

    /**
     * @notice The average price of each token from all commitments.
     */
    function _avgTokenPrice() private view returns (uint256) {
        return (commitmentsTotal * 1e18) / totalTokens;
    }

    /**
     * @notice Returns price during the auction
     */
    function _priceFunction() private view returns (uint256) {
        if (block.timestamp <= startDate) {
            return startPrice;
        }
        if (block.timestamp >= endDate) {
            return minimumPrice;
        }
        return _currentPrice();
    }

    /**
     * @notice Returns price during the auction
     */
    function _currentPrice() private view returns (uint256) {
        uint256 elapsed = block.timestamp - startDate;
        uint256 priceDiff = elapsed * priceDrop;
        return startPrice - priceDiff;
    }

    /**
     * @notice The current clearing price of the Dutch auction
     */
    function _clearingPrice() private view returns (uint256) {
        if (_avgTokenPrice() > _priceFunction()) {
            return _avgTokenPrice();
        }
        return _priceFunction();
    }

    /**
     * @notice How many tokens the user is able to claim
     * @param _user user address
     */
    function _tokensClaimable(address _user) private view returns (uint256) {
        return (commitments[_user] * 1e18) / _clearingPrice();
    }

    /**
     * @notice Successful if tokens sold equals totalTokens
     */
    function _isAuctionSuccessful() private view returns (bool) {
        return _avgTokenPrice() >= _clearingPrice();
    }
}
