// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "../../interfaces/leverageX/types/IPairsStorage.sol";
import "../../interfaces/leverageX/libraries/IPairsStorageUtils.sol";
import "../../interfaces/leverageX/IGeneralErrors.sol";

import "./StorageUtils.sol";
import "./ConstantsUtils.sol";

/**
 * @custom:version 8
 * @dev JavPairsStorage facet internal library
 */
library PairsStorageUtils {
    uint256 private constant MIN_LEVERAGE = 2;
    uint256 private constant MAX_LEVERAGE = 1000;

    function initializeGroupLiquidationParams(
        IPairsStorage.GroupLiquidationParams[] memory _groupLiquidationParams
    ) internal {
        IPairsStorage.PairsStorage storage s = _getStorage();
        if (_groupLiquidationParams.length != s.groupsCount) revert IGeneralErrors.WrongLength();

        for (uint256 i = 0; i < _groupLiquidationParams.length; ++i) {
            setGroupLiquidationParams(i, _groupLiquidationParams[i]);
        }
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function addPairs(IPairsStorage.Pair[] calldata _pairs) internal {
        for (uint256 i = 0; i < _pairs.length; ++i) {
            _addPair(_pairs[i]);
        }
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function updatePairs(
        uint256[] calldata _pairIndices,
        IPairsStorage.Pair[] calldata _pairs
    ) internal {
        if (_pairIndices.length != _pairs.length) revert IGeneralErrors.WrongLength();

        for (uint256 i = 0; i < _pairs.length; ++i) {
            _updatePair(_pairIndices[i], _pairs[i]);
        }
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function removePairs(uint256[] calldata _pairIndices) internal {
        for (uint256 i = 0; i < _pairIndices.length; ++i) {
            _removePair(_pairIndices[i]);
        }
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function addGroups(IPairsStorage.Group[] calldata _groups) internal {
        for (uint256 i = 0; i < _groups.length; ++i) {
            _addGroup(_groups[i]);
        }
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function updateGroups(
        uint256[] calldata _ids,
        IPairsStorage.Group[] calldata _groups
    ) internal {
        if (_ids.length != _groups.length) revert IGeneralErrors.WrongLength();

        for (uint256 i = 0; i < _groups.length; ++i) {
            _updateGroup(_ids[i], _groups[i]);
        }
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function addFees(IPairsStorage.Fee[] calldata _fees) internal {
        for (uint256 i = 0; i < _fees.length; ++i) {
            _addFee(_fees[i]);
        }
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function updateFees(uint256[] calldata _ids, IPairsStorage.Fee[] calldata _fees) internal {
        if (_ids.length != _fees.length) revert IGeneralErrors.WrongLength();

        for (uint256 i = 0; i < _fees.length; ++i) {
            _updateFee(_ids[i], _fees[i]);
        }
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function setPairCustomMaxLeverages(
        uint256[] calldata _indices,
        uint256[] calldata _values
    ) internal {
        if (_indices.length != _values.length) revert IGeneralErrors.WrongLength();

        IPairsStorage.PairsStorage storage s = _getStorage();

        for (uint256 i; i < _indices.length; ++i) {
            s.pairCustomMaxLeverage[_indices[i]] = _values[i];

            emit IPairsStorageUtils.PairCustomMaxLeverageUpdated(_indices[i], _values[i]);
        }
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function setGroupLiquidationParams(
        uint256 _groupIndex,
        IPairsStorage.GroupLiquidationParams memory _params
    ) internal groupListed(_groupIndex) {
        IPairsStorage.PairsStorage storage s = _getStorage();

        if (
            _params.maxLiqSpreadP == 0 ||
            _params.startLiqThresholdP == 0 ||
            _params.endLiqThresholdP == 0 ||
            _params.startLeverage == 0 ||
            _params.endLeverage == 0
        ) revert IGeneralErrors.ZeroValue();

        if (_params.maxLiqSpreadP > ConstantsUtils.MAX_LIQ_SPREAD_P)
            revert IPairsStorageUtils.MaxLiqSpreadPTooHigh();

        if (_params.startLiqThresholdP < _params.endLiqThresholdP)
            revert IPairsStorageUtils.WrongLiqParamsThresholds();
        if (_params.startLiqThresholdP > ConstantsUtils.LEGACY_LIQ_THRESHOLD_P)
            revert IPairsStorageUtils.StartLiqThresholdTooHigh();
        if (_params.endLiqThresholdP < ConstantsUtils.MIN_LIQ_THRESHOLD_P)
            revert IPairsStorageUtils.EndLiqThresholdTooLow();

        if (_params.startLeverage > _params.endLeverage)
            revert IPairsStorageUtils.WrongLiqParamsLeverages();
        if (_params.startLeverage < groups(_groupIndex).minLeverage * 1e3)
            revert IPairsStorageUtils.StartLeverageTooLow();
        if (_params.endLeverage > groups(_groupIndex).maxLeverage * 1e3)
            revert IPairsStorageUtils.EndLeverageTooHigh();

        s.groupLiquidationParams[_groupIndex] = _params;

        emit IPairsStorageUtils.GroupLiquidationParamsUpdated(_groupIndex, _params);
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function pairFeed(uint256 _pairIndex) internal view returns (bytes32) {
        IPairsStorage.PairsStorage storage s = _getStorage();

        IPairsStorage.Pair memory p = s.pairs[_pairIndex];
        if (!s.isPairListed[p.from][p.to]) revert IPairsStorageUtils.PairNotListed();

        return p.feedId;
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function isPairListed(string calldata _from, string calldata _to) internal view returns (bool) {
        return _getStorage().isPairListed[_from][_to];
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function isPairIndexListed(uint256 _pairIndex) internal view returns (bool) {
        IPairsStorage.PairsStorage storage s = _getStorage();
        return _pairIndex < s.pairsCount && !s.isPairRemoved[_pairIndex];
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function pairs(uint256 _index) internal view returns (IPairsStorage.Pair memory) {
        return _getStorage().pairs[_index];
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function pairsCount() internal view returns (uint256) {
        return _getStorage().pairsCount;
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function pairSpreadP(uint256 _pairIndex) internal view returns (uint256) {
        return pairs(_pairIndex).spreadP;
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function pairMinLeverage(uint256 _pairIndex) internal view returns (uint256) {
        return groups(pairs(_pairIndex).groupIndex).minLeverage;
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function pairOpenFeeP(uint256 _pairIndex) internal view returns (uint256) {
        return fees(pairs(_pairIndex).feeIndex).openFeeP;
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function pairCloseFeeP(uint256 _pairIndex) internal view returns (uint256) {
        return fees(pairs(_pairIndex).feeIndex).closeFeeP;
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function pairTriggerOrderFeeP(uint256 _pairIndex) internal view returns (uint256) {
        return fees(pairs(_pairIndex).feeIndex).triggerOrderFeeP;
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function pairMinPositionSizeUsd(uint256 _pairIndex) internal view returns (uint256) {
        return fees(pairs(_pairIndex).feeIndex).minPositionSizeUsd;
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function pairMinFeeUsd(uint256 _pairIndex) internal view returns (uint256) {
        IPairsStorage.Fee memory f = fees(pairs(_pairIndex).feeIndex);
        return
            (f.minPositionSizeUsd * (f.openFeeP * 2 + f.triggerOrderFeeP)) /
            ConstantsUtils.P_10 /
            100;
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function pairFeeIndex(uint256 _pairIndex) internal view returns (uint256) {
        return _getStorage().pairs[_pairIndex].feeIndex;
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function groups(uint256 _index) internal view returns (IPairsStorage.Group memory) {
        return _getStorage().groups[_index];
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function groupsCount() internal view returns (uint256) {
        return _getStorage().groupsCount;
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function fees(uint256 _index) internal view returns (IPairsStorage.Fee memory) {
        return _getStorage().fees[_index];
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function feesCount() internal view returns (uint256) {
        return _getStorage().feesCount;
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function pairsBackend(
        uint256 _index
    )
        internal
        view
        returns (IPairsStorage.Pair memory, IPairsStorage.Group memory, IPairsStorage.Fee memory)
    {
        IPairsStorage.Pair memory p = pairs(_index);
        return (p, PairsStorageUtils.groups(p.groupIndex), PairsStorageUtils.fees(p.feeIndex));
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function pairMaxLeverage(uint256 _pairIndex) internal view returns (uint256) {
        IPairsStorage.PairsStorage storage s = _getStorage();

        uint256 maxLeverage = s.pairCustomMaxLeverage[_pairIndex];
        return maxLeverage > 0 ? maxLeverage : s.groups[s.pairs[_pairIndex].groupIndex].maxLeverage;
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function pairCustomMaxLeverage(uint256 _pairIndex) internal view returns (uint256) {
        return _getStorage().pairCustomMaxLeverage[_pairIndex];
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function getAllPairsRestrictedMaxLeverage() internal view returns (uint256[] memory) {
        uint256[] memory lev = new uint256[](pairsCount());

        for (uint256 i; i < lev.length; ++i) {
            lev[i] = pairCustomMaxLeverage(i);
        }

        return lev;
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function getGroupLiquidationParams(
        uint256 _groupIndex
    ) internal view returns (IPairsStorage.GroupLiquidationParams memory) {
        return _getStorage().groupLiquidationParams[_groupIndex];
    }

    /**
     * @dev Check IPairsStorageUtils interface for documentation
     */
    function getPairLiquidationParams(
        uint256 _pairIndex
    ) internal view returns (IPairsStorage.GroupLiquidationParams memory) {
        return _getStorage().groupLiquidationParams[pairs(_pairIndex).groupIndex];
    }

    /**
     * @dev Returns storage slot to use when fetching storage relevant to library
     */
    function _getSlot() internal pure returns (uint256) {
        return StorageUtils.GLOBAL_PAIRS_STORAGE_SLOT;
    }

    /**
     * @dev Returns storage pointer for storage struct in diamond contract, at defined slot
     */
    function _getStorage() internal pure returns (IPairsStorage.PairsStorage storage s) {
        uint256 storageSlot = _getSlot();
        assembly {
            s.slot := storageSlot
        }
    }

    /**
     * Reverts if group is not listed
     * @param _groupIndex group index to check
     */
    modifier groupListed(uint256 _groupIndex) {
        if (_getStorage().groups[_groupIndex].minLeverage == 0)
            revert IPairsStorageUtils.GroupNotListed();
        _;
    }

    /**
     * Reverts if fee is not listed
     * @param _feeIndex fee index to check
     */
    modifier feeListed(uint256 _feeIndex) {
        if (_getStorage().fees[_feeIndex].openFeeP == 0) revert IPairsStorageUtils.FeeNotListed();
        _;
    }

    /**
     * Reverts if group is not valid
     * @param _group group to check
     */
    modifier groupOk(IPairsStorage.Group calldata _group) {
        if (
            _group.minLeverage < MIN_LEVERAGE ||
            _group.maxLeverage > MAX_LEVERAGE ||
            _group.minLeverage >= _group.maxLeverage
        ) revert IPairsStorageUtils.WrongLeverages();
        _;
    }

    /**
     * @dev Reverts if fee is not valid
     * @param _fee fee to check
     */
    modifier feeOk(IPairsStorage.Fee calldata _fee) {
        if (
            _fee.openFeeP == 0 ||
            _fee.closeFeeP == 0 ||
            _fee.triggerOrderFeeP == 0 ||
            _fee.minPositionSizeUsd == 0
        ) revert IPairsStorageUtils.WrongFees();
        _;
    }

    /**
     * @dev Adds a new trading pair
     * @param _pair pair to add
     */
    function _addPair(
        IPairsStorage.Pair calldata _pair
    ) internal groupListed(_pair.groupIndex) feeListed(_pair.feeIndex) {
        IPairsStorage.PairsStorage storage s = _getStorage();
        if (s.isPairListed[_pair.from][_pair.to]) revert IPairsStorageUtils.PairAlreadyListed();

        s.pairs[s.pairsCount] = _pair;
        s.isPairListed[_pair.from][_pair.to] = true;

        emit IPairsStorageUtils.PairAdded(s.pairsCount++, _pair.from, _pair.to);
    }

    /**
     * @dev Updates an existing trading pair
     * @param _pairIndex index of pair to update
     * @param _pair new pair value
     */
    function _updatePair(
        uint256 _pairIndex,
        IPairsStorage.Pair calldata _pair
    ) internal groupListed(_pair.groupIndex) feeListed(_pair.feeIndex) {
        IPairsStorage.PairsStorage storage s = _getStorage();

        IPairsStorage.Pair storage p = s.pairs[_pairIndex];
        if (!s.isPairListed[p.from][p.to]) revert IPairsStorageUtils.PairNotListed();

        p.spreadP = _pair.spreadP;
        p.groupIndex = _pair.groupIndex;
        p.feeIndex = _pair.feeIndex;
        p.feedId = _pair.feedId;

        emit IPairsStorageUtils.PairUpdated(_pairIndex);
    }

    /**
     * @dev Remove an existing trading pair
     * @param _pairIndex index of pair to remove
     */
    function _removePair(uint256 _pairIndex) internal {
        IPairsStorage.PairsStorage storage s = _getStorage();

        IPairsStorage.Pair memory p = s.pairs[_pairIndex];
        if (!s.isPairListed[p.from][p.to]) revert IPairsStorageUtils.PairNotListed();

        s.isPairRemoved[_pairIndex] = true;

        emit IPairsStorageUtils.PairRemoved(_pairIndex);
    }

    /**
     * @dev Adds a new pair group
     * @param _group group to add
     */
    function _addGroup(IPairsStorage.Group calldata _group) internal groupOk(_group) {
        IPairsStorage.PairsStorage storage s = _getStorage();
        s.groups[s.groupsCount] = _group;

        emit IPairsStorageUtils.GroupAdded(s.groupsCount++, _group.name);
    }

    /**
     * @dev Updates an existing pair group
     * @param _id index of group to update
     * @param _group new group value
     */
    function _updateGroup(
        uint256 _id,
        IPairsStorage.Group calldata _group
    ) internal groupListed(_id) groupOk(_group) {
        _getStorage().groups[_id] = _group;

        emit IPairsStorageUtils.GroupUpdated(_id);
    }

    /**
     * @dev Adds a new pair fee group
     * @param _fee fee to add
     */
    function _addFee(IPairsStorage.Fee calldata _fee) internal feeOk(_fee) {
        IPairsStorage.PairsStorage storage s = _getStorage();
        s.fees[s.feesCount] = _fee;

        emit IPairsStorageUtils.FeeAdded(s.feesCount++, _fee.name);
    }

    /**
     * @dev Updates an existing pair fee group
     * @param _id index of fee to update
     * @param _fee new fee value
     */
    function _updateFee(
        uint256 _id,
        IPairsStorage.Fee calldata _fee
    ) internal feeListed(_id) feeOk(_fee) {
        _getStorage().fees[_id] = _fee;

        emit IPairsStorageUtils.FeeUpdated(_id);
    }
}
