// SPDX-License-Identifier: MIT
/// @title: Contract for wallet with multisig withdraw functionality for ERC-20 tokens.
/// @notice: Allows to withdraw ERC-20 tokens from the vault only if a certain number of signers approve the transaction.
/// @author: Solidity University
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract VaultMultisig {
    using SafeERC20 for IERC20;

    /// @notice The number of signatures required to execute a transaction
    uint256 public quorum;

    /// @notice The number of transfers executed
    uint256 public transfersCount;

    /// @notice The current multisig signers
    address[] public currentMultiSigSigners;

    /// @dev The struct is used to store the details of a transfer
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to transfer
    /// @param token The ERC-20 token contract address
    /// @param approvals The number of approvals required to execute the transfer
    /// @param executed Whether the transfer has been executed
    /// @param approved The mapping of signers to their approval status
    struct Transfer {
        address to;
        uint256 amount;
        address token;
        uint256 approvals;
        bool executed;
        mapping(address => bool) approved;
    }

    /// @notice The mapping of transfer IDs to transfer details
    mapping(uint256 => Transfer) private transfers;

    /// @notice The mapping for verification that address is a signer
    mapping(address => bool) private multiSigSigners;

    /// @notice Checks that signers array is not empty
    error SignersArrayCannotBeEmpty();

    /// @notice Checks that quorum is not greather than the number of signers
    error QuorumGreaterThanSigners();

    /// @notice Checks that quorum is greater than zero
    error QuorumCannotBeZero();

    /// @notice Checks that the recipient is not the zero address
    error InvalidRecipient();

    /// @notice Checks that the token address is not the zero address
    error InvalidToken();

    /// @notice Checks that amount is greater than zero
    error InvalidAmount();

    /// @notice Checks that the signer is a multisig signer
    error InvalidMultisigSigner();

    /// @notice Checks that the balance is sufficient for the transfer
    error InsufficientBalance(uint256 balance, uint256 desiredAmount);

    /// @notice Checks that the transfer is not already executed
    /// @param transferId The ID of the transfer
    error TransferIsAlreadyExecuted(uint256 transferId);

    /// @notice Checks that the signer is already approved
    /// @param signer The address of the signer
    error SignerAlreadyApproved(address signer);

    /// @notice Checks that the transfer failed
    /// @param transferId The ID of the transfer
    error TransferFailed(uint256 transferId);

    /// @notice Checks that quorum was reached for transfer
    /// @param transferId The ID of the transfer
    error QuorumHasNotBeenReached(uint256 transferId);

    /// @notice Checks that the signer is a multisig admin
    error InvalidMultisigAdmin();

    /// @notice Emitted when a transfer is initiated
    event TransferInitiated(uint256 indexed transferId, address indexed to, uint256 amount, address indexed token);

    /// @notice Emitted when a transfer is approved
    /// @param transferId The ID of the transfer
    /// @param approver The address of the approver
    event TransferApproved(uint256 indexed transferId, address indexed approver);

    /// @notice Emitted when a transfer is executed
    /// @param transferId The ID of the transfer
    event TransferExecuted(uint256 indexed transferId);

    /// @notice Emitted when the multisig signers are updated
    event MultiSigSignersUpdated();

    /// @notice Emitted when the quorum is updated
    /// @param quorum The new quorum
    event QuorumUpdated(uint256 quorum);

    modifier onlyMultisigSigner() {
        if (!multiSigSigners[msg.sender]) revert InvalidMultisigSigner();
        _;
    }

    /// @notice Initializes the multisig contract
    /// @param _signers The array of multisig signers
    /// @param _quorum The number of signatures required to execute a transaction
    constructor(address[] memory _signers, uint256 _quorum) {
        if (_signers.length == 0) revert SignersArrayCannotBeEmpty();
        if (_quorum > _signers.length) revert QuorumGreaterThanSigners();
        if (_quorum == 0) revert QuorumCannotBeZero();

        for (uint256 i = 0; i < _signers.length; i++) {
            multiSigSigners[_signers[i]] = true;
        }

        currentMultiSigSigners = _signers;
        quorum = _quorum;
    }

    /// @notice Initiates a transfer
    /// @param _to The address of the recipient
    /// @param _amount The amount of tokens to transfer
    /// @param _token The ERC-20 token contract address
    function initiateTransfer(address _to, uint256 _amount, address _token) external onlyMultisigSigner {
        if (_to == address(0)) revert InvalidRecipient();
        if (_token == address(0)) revert InvalidToken();
        if (_amount <= 0) revert InvalidAmount();

        uint256 transferId = transfersCount++;
        Transfer storage transfer = transfers[transferId];
        transfer.to = _to;
        transfer.amount = _amount;
        transfer.token = _token;
        transfer.approvals = 1; // Initiator automatically approves
        transfer.executed = false;
        transfer.approved[msg.sender] = true;

        emit TransferInitiated(transferId, _to, _amount, _token);
    }

    /// @notice Approves a transfer
    /// @param _transferId The ID of the transfer
    function approveTransfer(uint256 _transferId) external onlyMultisigSigner {
        Transfer storage transfer = transfers[_transferId];
        if (transfer.executed) revert TransferIsAlreadyExecuted(_transferId);
        if (transfer.approved[msg.sender]) revert SignerAlreadyApproved(msg.sender);

        transfer.approvals++;
        transfer.approved[msg.sender] = true;

        emit TransferApproved(_transferId, msg.sender);
    }

    /// @notice Executes a transfer
    /// @param _transferId The ID of the transfer
    function executeTransfer(uint256 _transferId) external onlyMultisigSigner {
        Transfer storage transfer = transfers[_transferId];
        if (transfer.approvals < quorum) revert QuorumHasNotBeenReached(_transferId);
        if (transfer.executed) revert TransferIsAlreadyExecuted(_transferId);

        IERC20 token = IERC20(transfer.token);
        uint256 balance = token.balanceOf(address(this));
        if (transfer.amount > balance) revert InsufficientBalance(balance, transfer.amount);

        transfer.executed = true;

        // Use SafeERC20 for secure token transfer
        token.safeTransfer(transfer.to, transfer.amount);

        emit TransferExecuted(_transferId);
    }

    /// @notice Gets the details of a transfer
    /// @param _transferId The ID of the transfer
    /// @return to The address of the recipient
    /// @return amount The amount of tokens to transfer
    /// @return token The ERC-20 token contract address
    /// @return approvals The number of approvals required to execute the transfer
    /// @return executed Whether the transfer has been executed
    function getTransfer(uint256 _transferId)
        external
        view
        returns (address to, uint256 amount, address token, uint256 approvals, bool executed)
    {
        Transfer storage transfer = transfers[_transferId];
        return (transfer.to, transfer.amount, transfer.token, transfer.approvals, transfer.executed);
    }

    /// @notice Checks if a signer has signed a transfer
    /// @param _transferId The ID of the transfer
    /// @param _signer The address of the signer
    /// @return hasSigned Whether the signer has signed the transfer
    function hasSignedTransfer(uint256 _transferId, address _signer) external view returns (bool) {
        Transfer storage transfer = transfers[_transferId];
        return transfer.approved[_signer];
    }

    /// @notice Gets the number of transfers
    /// @return The number of transfers
    function getTransferCount() external view returns (uint256) {
        return transfersCount;
    }

    /// @notice Gets the balance of a specific ERC-20 token held by this contract
    /// @param _token The ERC-20 token contract address
    /// @return The token balance
    function getTokenBalance(address _token) external view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    /// @notice Gets the list of current multisig signers
    /// @return The array of current signers
    function getCurrentSigners() external view returns (address[] memory) {
        return currentMultiSigSigners;
    }

    /// @notice Checks if an address is a multisig signer
    /// @param _signer The address to check
    /// @return Whether the address is a signer
    function isSigner(address _signer) external view returns (bool) {
        return multiSigSigners[_signer];
    }
}
