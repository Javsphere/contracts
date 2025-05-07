const ADMIN_ERROR = "BaseUpgradable: only admin";
const MANAGER_ERROR = "BaseUpgradable: only manager";
const OWNER_ERROR = "OwnableUnauthorizedAccount";
const MAX_UINT256 = BigInt(2) ** BigInt(256) - BigInt(1);

module.exports = {
    ADMIN_ERROR,
    MANAGER_ERROR,
    OWNER_ERROR,
    MAX_UINT256,
};
