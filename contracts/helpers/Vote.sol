// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import "../interfaces/helpers/IVote.sol";
import "../base/BaseUpgradable.sol";
import "../interfaces/ITokenVesting.sol";
import "../interfaces/IJavStakeX.sol";
import "../interfaces/IJavFreezer.sol";

contract Vote is IVote, BaseUpgradable {
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(bool => uint256)) public proposalWeight;
    mapping(address => mapping(uint256 => bool)) public votedProposal;
    mapping(address => mapping(uint256 => bool)) public votedDirection;
    uint256 public proposalIndex;

    address public vestingAddress;
    address public stakingAddress;
    address public freezerAddress;
    uint256 public stakingFactor; //1e2
    uint256 public vestingFactor; //1e2
    mapping(uint256 => uint256) public freezerFactor; //1e2

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier onlyActiveProposal(uint256 _id) {
        require(!proposals[_id].isExecuted, AlreadyExecuted());
        _;
    }

    function initialize(
        address _adminAddress,
        address _vestingAddress,
        address _stakingAddress,
        address _freezerAddress,
        uint256 _stakingFactor,
        uint256 _vestingFactor,
        uint256[] memory _freezerIdsFactor,
        uint256[] memory _freezerFactors
    ) external initializer {
        require(_freezerIdsFactor.length == _freezerFactors.length, InvalidInputLength());
        vestingAddress = _vestingAddress;
        stakingAddress = _stakingAddress;
        freezerAddress = _freezerAddress;

        stakingFactor = _stakingFactor;
        vestingFactor = _vestingFactor;

        for (uint256 i = 0; i < _freezerIdsFactor.length; ++i) {
            freezerFactor[_freezerIdsFactor[i]] = _freezerFactors[i];
        }

        __Base_init();
        adminAddress = _adminAddress;
    }

    function votingPower(address _user) external view returns (uint256) {
        return _calculateVotingWeight(_user);
    }

    function createProposal(
        uint256 _startTimestamp,
        uint256 _endTimestamp,
        string calldata _descriptionId
    ) external onlyAdmin {
        require(_endTimestamp > _startTimestamp, WrongParams());
        proposals[proposalIndex] = Proposal({
            proposer: _msgSender(),
            startTimestamp: _startTimestamp,
            endTimestamp: _endTimestamp,
            descriptionId: _descriptionId,
            isExecuted: false,
            isApproved: false
        });
        emit CreateProposal(
            proposalIndex,
            _msgSender(),
            _startTimestamp,
            _endTimestamp,
            _descriptionId
        );
        proposalIndex += 1;
    }

    function voteForProposal(
        uint256 _proposalId,
        bool _voteType
    ) external onlyActiveProposal(_proposalId) {
        require(!votedProposal[_msgSender()][_proposalId], AlreadyVoted());
        require(
            proposals[_proposalId].endTimestamp >= block.timestamp &&
                block.timestamp >= proposals[_proposalId].startTimestamp,
            InvalidVotePeriod()
        );
        uint256 votingWeight = _calculateVotingWeight(_msgSender());
        proposalWeight[_proposalId][_voteType] =
            proposalWeight[_proposalId][_voteType] +
            votingWeight;
        votedProposal[_msgSender()][_proposalId] = true;
        votedDirection[_msgSender()][_proposalId] = _voteType;
        emit VoteForProposal(_msgSender(), _proposalId, _voteType, votingWeight);
    }

    function executeProposal(uint256 _proposalId) external onlyActiveProposal(_proposalId) {
        require(proposals[_proposalId].endTimestamp <= block.timestamp, NotEnded());
        require(_proposalId < proposalIndex, WrongIndex());
        _executeProposal(_proposalId);
    }

    function _executeProposal(uint256 _proposalId) private {
        Proposal storage proposal = proposals[_proposalId];
        bool isApproved = proposalWeight[_proposalId][true] > proposalWeight[_proposalId][false];
        proposal.isApproved = isApproved;
        proposal.isExecuted = true;

        emit ExecuteProposal(_proposalId, isApproved);
    }

    function _calculateVotingWeight(address _user) private view returns (uint256 votingWeight) {
        uint256 stakingAmount = IJavStakeX(stakingAddress).userShares(0, _user);
        if (stakingAmount > 0) {
            votingWeight += (stakingFactor * stakingAmount) / 100;
        }
        if (IJavFreezer(freezerAddress).userDepositTokens(0, _user) > 0) {
            uint256 lastId = IJavFreezer(freezerAddress).getUserLastDepositId(0, _user);
            for (uint256 i = 0; i <= lastId; ++i) {
                IJavFreezer.UserDeposit memory depositDetails = IJavFreezer(freezerAddress)
                    .userDeposit(_user, 0, i);
                if (!depositDetails.is_finished) {
                    votingWeight +=
                        (freezerFactor[depositDetails.stakePeriod] * depositDetails.depositTokens) /
                        100;
                }
            }
        }
        uint256 vestingCount = ITokenVesting(vestingAddress).holdersVestingCount(_user);
        if (vestingCount > 0) {
            for (uint256 i = 0; i < vestingCount; ++i) {
                ITokenVesting.VestingSchedule memory schedule = ITokenVesting(vestingAddress)
                    .getVestingScheduleByAddressAndIndex(_user, i);
                if (schedule.released != schedule.amountTotal && !schedule.revoked) {
                    votingWeight +=
                        (vestingFactor * (schedule.amountTotal - schedule.released)) /
                        100;
                }
            }
        }
    }
}
