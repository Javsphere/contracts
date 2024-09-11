// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

/**
 * @title Multisignature wallet - Allows multiple parties to agree on transactions before execution.
 * @custom:id 1
 */
contract MultiSigWallet {
    /*
     *  Events
     */
    event Confirmation(address indexed sender, uint256 indexed transactionId);
    event Revocation(address indexed sender, uint256 indexed transactionId);
    event Submission(uint256 indexed transactionId);
    event Execution(uint256 indexed transactionId);
    event Deposit(address indexed sender, uint256 value);
    event OwnerAddition(address indexed owner);
    event OwnerRemoval(address indexed owner);
    event RequirementChange(uint256 required);
    event SubmitTransaction(uint256 indexed transactionId);

    /*
     *  views
     */
    uint256 public constant MAX_OWNER_COUNT = 50;

    /*
     *  Storage
     */
    mapping(uint256 => Transaction) public transactions;
    mapping(uint256 => mapping(address => bool)) public confirmations;
    mapping(address => bool) public isOwner;
    address[] public owners;
    uint256 public required;
    uint256 public transactionCount;

    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
    }

    /*
     *  Modifiers
     */
    modifier onlyWallet() {
        require(msg.sender == address(this), "MultiSigWallet: only wallet");
        _;
    }

    modifier ownerDoesNotExist(address owner) {
        require(!isOwner[owner], "MultiSigWallet: owner already exist");
        _;
    }

    modifier ownerExists(address owner) {
        require(isOwner[owner], "MultiSigWallet: owner does not exist");
        _;
    }

    modifier transactionExists(uint256 transactionId) {
        require(
            transactions[transactionId].to != address(0),
            "MultiSigWallet: transaction does not exist"
        );
        _;
    }

    modifier confirmed(uint256 transactionId, address owner) {
        require(confirmations[transactionId][owner], "MultiSigWallet: transaction not confirmed");
        _;
    }

    modifier notConfirmed(uint256 transactionId, address owner) {
        require(
            !confirmations[transactionId][owner],
            "MultiSigWallet: transaction already confirmed"
        );
        _;
    }

    modifier notExecuted(uint256 transactionId) {
        require(
            !transactions[transactionId].executed,
            "MultiSigWallet: confirmed already executed"
        );
        _;
    }

    modifier notNull(address _address) {
        require(_address != address(0), "MultiSigWallet: value is null");
        _;
    }

    modifier validRequirement(uint256 ownerCount, uint256 _required) {
        require(
            ownerCount <= MAX_OWNER_COUNT &&
                _required <= ownerCount &&
                _required != 0 &&
                ownerCount != 0,
            "MultiSigWallet: invalid required number or owners count"
        );
        _;
    }

    receive() external payable {}

    fallback() external payable {}

    /*
     * Public functions
     */
    /// @dev Contract constructor sets initial owners and required number of confirmations.
    /// @param _owners List of initial owners.
    /// @param _required Number of required confirmations.
    constructor(
        address[] memory _owners,
        uint256 _required
    ) validRequirement(_owners.length, _required) {
        for (uint256 i = 0; i < _owners.length; i++) {
            require(
                !isOwner[_owners[i]] && _owners[i] != address(0),
                "MultiSigWallet: owner exist or null"
            );
            isOwner[_owners[i]] = true;
        }
        owners = _owners;
        required = _required;
    }

    /// @dev Allows to add a new owner. Transaction has to be sent by wallet.
    /// @param owner Address of new owner.
    function addOwner(
        address owner
    )
        external
        onlyWallet
        ownerDoesNotExist(owner)
        notNull(owner)
        validRequirement(owners.length + 1, required)
    {
        isOwner[owner] = true;
        owners.push(owner);
        emit OwnerAddition(owner);
    }

    /// @dev Allows to replace an owner with a new owner. Transaction has to be sent by wallet.
    /// @param owner Address of owner to be replaced.
    /// @param newOwner Address of new owner.
    function replaceOwner(
        address owner,
        address newOwner
    ) external onlyWallet ownerExists(owner) ownerDoesNotExist(newOwner) {
        for (uint256 i = 0; i < owners.length; i++)
            if (owners[i] == owner) {
                owners[i] = newOwner;
                break;
            }
        isOwner[owner] = false;
        isOwner[newOwner] = true;
        emit OwnerRemoval(owner);
        emit OwnerAddition(newOwner);
    }

    /// @dev Allows to change the number of required confirmations. Transaction has to be sent by wallet.
    /// @param _required Number of required confirmations.
    function changeRequirement(
        uint256 _required
    ) public onlyWallet validRequirement(owners.length, _required) {
        required = _required;
        emit RequirementChange(_required);
    }

    /// @dev Allows an owner to submit and confirm a transaction.
    /// @param to Transaction target address.
    /// @param value Transaction ether value.
    /// @param data Transaction data payload.
    /// @return Returns transaction ID.
    function submitTransaction(
        address to,
        uint256 value,
        bytes memory data
    ) external ownerExists(msg.sender) returns (uint256) {
        uint256 transactionId = addTransaction(to, value, data);
        confirmTransaction(transactionId);
        emit SubmitTransaction(transactionId);
        return transactionId;
    }

    /// @dev Allows an owner to confirm a transaction.
    /// @param transactionId Transaction ID.
    function confirmTransaction(
        uint256 transactionId
    )
        public
        ownerExists(msg.sender)
        transactionExists(transactionId)
        notConfirmed(transactionId, msg.sender)
    {
        confirmations[transactionId][msg.sender] = true;
        emit Confirmation(msg.sender, transactionId);
    }

    /// @dev Allows an owner to revoke a confirmation for a transaction.
    /// @param transactionId Transaction ID.
    function revokeConfirmation(
        uint256 transactionId
    )
        external
        ownerExists(msg.sender)
        confirmed(transactionId, msg.sender)
        notExecuted(transactionId)
    {
        confirmations[transactionId][msg.sender] = false;
        emit Revocation(msg.sender, transactionId);
    }

    /// @dev Allows anyone to execute a confirmed transaction.
    /// @param transactionId Transaction ID.
    function executeTransaction(
        uint256 transactionId
    )
        external
        ownerExists(msg.sender)
        confirmed(transactionId, msg.sender)
        notExecuted(transactionId)
    {
        require(_isConfirmed(transactionId), "MultiSigWallet: transaction not confirmed");
        Transaction storage txn = transactions[transactionId];
        (bool success, ) = txn.to.call{value: txn.value}(txn.data);
        require(success, "MultiSigWallet: contract call failed");
        txn.executed = true;
        emit Execution(transactionId);
    }

    /*
     * Internal functions
     */
    /// @dev Adds a new transaction to the transaction mapping, if transaction does not exist yet.
    /// @param to Transaction target address.
    /// @param value Transaction ether value.
    /// @param data Transaction data payload.
    /// @return Returns transaction ID.
    function addTransaction(
        address to,
        uint256 value,
        bytes memory data
    ) internal notNull(to) returns (uint256) {
        uint256 transactionId = transactionCount;
        transactions[transactionId] = Transaction({
            to: to,
            value: value,
            data: data,
            executed: false
        });
        transactionCount += 1;
        emit Submission(transactionId);

        return transactionId;
    }

    /*
     * Web3 call functions
     */
    /// @dev Returns number of confirmations of a transaction.
    /// @param transactionId Transaction ID.
    /// @return Number of confirmations.
    function getConfirmationCount(uint256 transactionId) external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < owners.length; i++)
            if (confirmations[transactionId][owners[i]]) count++;
        return count;
    }

    /// @dev Returns total number of transactions after filers are applied.
    /// @param pending Include pending transactions.
    /// @param executed Include executed transactions.
    /// @return Total number of transactions after filters are applied.
    function getTransactionCount(bool pending, bool executed) external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < transactionCount; i++)
            if ((pending && !transactions[i].executed) || (executed && transactions[i].executed))
                count++;
        return count;
    }

    /// @dev Returns list of owners.
    /// @return List of owner addresses.
    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    /// @dev Returns array with owner addresses, which confirmed transaction.
    /// @param transactionId Transaction ID.
    /// @return Returns array of owner addresses.
    function getConfirmations(uint256 transactionId) external view returns (address[] memory) {
        address[] memory confirmationsTemp = new address[](owners.length);
        uint256 count = 0;
        uint256 i;
        for (i = 0; i < owners.length; i++)
            if (confirmations[transactionId][owners[i]]) {
                confirmationsTemp[count] = owners[i];
                count += 1;
            }
        address[] memory _confirmations = new address[](count);
        for (i = 0; i < count; i++) _confirmations[i] = confirmationsTemp[i];

        return _confirmations;
    }

    /// @dev Returns list of transaction IDs in defined range.
    /// @param from Index start position of transaction array.
    /// @param to Index end position of transaction array.
    /// @param pending Include pending transactions.
    /// @param executed Include executed transactions.
    /// @return Returns array of transaction IDs.
    function getTransactionIds(
        uint256 from,
        uint256 to,
        bool pending,
        bool executed
    ) external view returns (uint256[] memory) {
        uint256[] memory transactionIdsTemp = new uint256[](transactionCount);
        uint256 count = 0;
        uint256 i;
        for (i = 0; i < transactionCount; i++)
            if ((pending && !transactions[i].executed) || (executed && transactions[i].executed)) {
                transactionIdsTemp[count] = i;
                count += 1;
            }
        uint256[] memory _transactionIds = new uint256[](to - from);
        for (i = from; i < to; i++) _transactionIds[i - from] = transactionIdsTemp[i];

        return _transactionIds;
    }

    /// @dev Returns the confirmation status of a transaction.
    /// @param transactionId Transaction ID.
    /// @return Confirmation status.
    function _isConfirmed(uint256 transactionId) private view returns (bool) {
        uint256 count = 0;
        for (uint256 i = 0; i < owners.length; i++) {
            if (confirmations[transactionId][owners[i]]) count++;
            if (count == required) return true;
        }
        return false;
    }
}
