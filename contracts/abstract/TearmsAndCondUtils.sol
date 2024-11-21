// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/helpers/ITermsAndConditionsAgreement.sol";

abstract contract TermsAndCondUtils {
    event SetTermsAndConditionsAddress(address indexed _address);

    error OnlyAgreedToTerms();

    modifier onlyAgreeToTerms(address termsAndConditionsAddress) {
        require(
            ITermsAndConditionsAgreement(termsAndConditionsAddress).hasAgreed(msg.sender),
            OnlyAgreedToTerms()
        );
        _;
    }
}
