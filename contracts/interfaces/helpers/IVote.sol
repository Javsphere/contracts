// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "./IGeneralErrors.sol";

interface IVote is IGeneralErrors {
    struct Proposal {
        address proposer;
        uint256 startTimestamp;
        uint256 endTimestamp;
        string descriptionId;
        bool isExecuted;
        bool isApproved;
    }

    event CreateProposal(
        uint256 indexed id,
        address indexed proposer,
        uint256 startTimestamp,
        uint256 endTimestamp,
        string descriptionId
    );
    event ExecuteProposal(uint256 indexed id, bool isApproved);
    event VoteForProposal(
        address indexed user,
        uint256 indexed id,
        bool voteType,
        uint256 votingPower
    );

    error AlreadyExecuted();
    error AlreadyVoted();
    error InvalidVotePeriod();
    error NotEnded();
}
