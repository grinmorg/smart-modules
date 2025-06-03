/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/VaultMultisig.sol";

contract VaultMultisigTest is Test {
    VaultMultisig vault;
    uint256 quorum = 2;
    address[] signers;
    address[] signersArray;

    address signer1 = vm.addr(1);
    address signer2 = vm.addr(2);
    address signer3 = vm.addr(3);
    address defaultRecepient = vm.addr(999);
    address stranger = vm.addr(777);

    function setUp() public {
        signers.push(signer1);
        signers.push(signer2);
        signers.push(signer3);

        vault = new VaultMultisig(signers, quorum);
    }

    function test_InitiateTransferRevertsIfNoEtherOnVault(address _randomAddress) public {
        vm.assume(_randomAddress != address(0));

        vm.prank(signer1);

        vm.expectRevert(VaultMultisig.VaultIsEmpty.selector);
        console.log("Vault Balance: ", address(vault).balance);

        vault.initiateTransfer(_randomAddress, 1 wei);
    }

    function test_InitiateTransferRevertsInvalidRecipient() public {
        address recepient = address(0);

        vm.prank(signer1);

        vm.expectRevert(VaultMultisig.InvalidRecipient.selector);

        vault.initiateTransfer(recepient, 1 wei);
    }

    function test_InitiateTransferRevertsInvalidMain(address _randomAddress) public {
        vm.assume(_randomAddress != address(0));

        vm.prank(signer1);

        vm.expectRevert(VaultMultisig.InvalidAmount.selector);

        vault.initiateTransfer(_randomAddress, 0);
    }

    function test_InitiateTransferShouldWork(address _randomAddress) public {
        vm.assume(_randomAddress != address(0));

        fundVault(1 ether);

        vm.prank(signer1);

        vm.expectEmit(true, true, false, true);
        emit VaultMultisig.TransferInitiated(0, _randomAddress, 1 ether);

        vault.initiateTransfer(_randomAddress, 1 ether);

        (address to, uint256 amount, uint256 approvals, bool executed) = vault.getTransfer(0);

        assertEq(to, _randomAddress);
        assertEq(amount, 1 ether);
        assertEq(approvals, 1);
        assertEq(executed, false);
    }

    function test_approveTransferShouldWork() public {
        vm.startPrank(signer1);
        fundVault(1 ether);
        vault.initiateTransfer(defaultRecepient, 1 ether);

        //1st approve
        vm.expectRevert(abi.encodeWithSelector(VaultMultisig.SignerAlreadyApproved.selector, signer1));
        vault.approveTransfer(0);

        //2nd approve
        vm.startPrank(signer2);
        vault.approveTransfer(0);

        //3d approve
        vm.startPrank(signer3);
        vault.approveTransfer(0);

        (,, uint256 approvals,) = vault.getTransfer(0);

        assertEq(approvals, 3);
    }

    function test_approveTransferShoulEmitTransferApproved() public {
        vm.startPrank(signer1);
        fundVault(1 ether);
        vault.initiateTransfer(defaultRecepient, 1 ether);

        vm.expectEmit(true, true, false, false);
        emit VaultMultisig.TransferApproved(0, signer2);
        vm.startPrank(signer2);
        vault.approveTransfer(0);
    }

    function test_executeTransferWors() public {
        vm.startPrank(signer1);
        fundVault(1 ether);
        vault.initiateTransfer(defaultRecepient, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(VaultMultisig.QuorumHasNotBeenReached.selector, 0));
        vault.executeTransfer(0);

        vm.startPrank(signer2);
        vault.approveTransfer(0);

        vm.expectEmit(true, false, false, false);
        emit VaultMultisig.TransferExecuted(0);
        vault.executeTransfer(0);

        vm.expectRevert(abi.encodeWithSelector(VaultMultisig.TransferIsAlreadyExecuted.selector, 0));
        vault.executeTransfer(0);

        (address to, uint256 amount, uint256 approvals, bool executed) = vault.getTransfer(0);

        assertEq(to, defaultRecepient);
        assertEq(amount, 1 ether);
        assertEq(approvals, 2);
        assertEq(executed, true);
    }

    function test_hasSignedTransferWorks() public {
        vm.startPrank(signer1);
        fundVault(1 ether);
        vault.initiateTransfer(defaultRecepient, 1 ether);
        assertTrue(vault.hasSignedTransfer(0, signer1));
        assertFalse(vault.hasSignedTransfer(0, signer2));

        vm.startPrank(signer2);
        vault.approveTransfer(0);

        assertTrue(vault.hasSignedTransfer(0, signer1));
        assertTrue(vault.hasSignedTransfer(0, signer2));
    }

    function test_getTransferCountWorks() public {
        uint256 beforeTransferInitiation = vault.getTransferCount();
        assertEq(beforeTransferInitiation, 0);

        vm.startPrank(signer1);
        fundVault(1 ether);
        vault.initiateTransfer(defaultRecepient, 1 ether);

        uint256 afterTransferInitiation = vault.getTransferCount();
        assertEq(afterTransferInitiation, 1);
    }

    function test_onlyMultisigSignerModifierWorks() public {
        vm.prank(stranger);
        fundVault(1 ether);

        vm.expectRevert(VaultMultisig.InvalidMultisigSigner.selector);
        vault.initiateTransfer(defaultRecepient, 1 ether);
    }

    function test_constructrRevertsSignersArrayCannotBeEmpty() public {
        address[] memory empty;

        vm.expectRevert(VaultMultisig.SignersArrayCannotBeEmpty.selector);
        new VaultMultisig(empty, 1);
    }

    function test_constructrRevertsQuorumGreaterThanSigners() public {
        signersArray.push(signer1);
        signersArray.push(signer2);

        vm.expectRevert(VaultMultisig.QuorumGreaterThanSigners.selector);
        new VaultMultisig(signersArray, 3);
    }

    function test_constructrRevertsQuorumCannotBeZero() public {
        signersArray.push(signer1);

        vm.expectRevert(VaultMultisig.QuorumCannotBeZero.selector);
        new VaultMultisig(signersArray, 0);
    }

    function test_updateSignersAndQuorumComprehensive() public {
        // === ПОДГОТОВКА ===
        // Создаем первую транзакцию со старыми подписантами
        fundVault(3 ether);

        vm.prank(signer1);
        vault.initiateTransfer(defaultRecepient, 1 ether);

        vm.prank(signer2);
        vault.approveTransfer(0);

        // Выполняем первую транзакцию
        vm.prank(signer1);
        vault.executeTransfer(0);

        // Проверяем начальное состояние
        assertEq(vault.quorum(), 2);
        assertEq(vault.getTransferCount(), 1);

        // === ТЕСТ ОШИБОК ===
        // Пустой массив подписантов
        address[] memory emptySigners = new address[](0);
        vm.prank(signer1);
        vm.expectRevert(VaultMultisig.SignersArrayCannotBeEmpty.selector);
        vault.updateSignersAndQuorum(emptySigners, 1);

        // Нулевой кворум
        address[] memory validSigners = new address[](2);
        validSigners[0] = vm.addr(10);
        validSigners[1] = vm.addr(11);

        vm.prank(signer1);
        vm.expectRevert(VaultMultisig.QuorumCannotBeZero.selector);
        vault.updateSignersAndQuorum(validSigners, 0);

        // Кворум больше количества подписантов
        vm.prank(signer1);
        vm.expectRevert(VaultMultisig.QuorumGreaterThanSigners.selector);
        vault.updateSignersAndQuorum(validSigners, 3);

        // Нулевой адрес в подписантах
        address[] memory signersWithZero = new address[](2);
        signersWithZero[0] = vm.addr(10);
        signersWithZero[1] = address(0);

        vm.prank(signer1);
        vm.expectRevert("Zero address in signers");
        vault.updateSignersAndQuorum(signersWithZero, 1);

        // === УСПЕШНОЕ ОБНОВЛЕНИЕ ===
        // Создаем новый массив подписантов
        address[] memory newSigners = new address[](3);
        newSigners[0] = vm.addr(20);
        newSigners[1] = vm.addr(21);
        newSigners[2] = vm.addr(22);
        uint256 newQuorum = 2;

        // Обновляем подписантов
        vm.prank(signer1);

        vm.expectEmit(false, false, false, false);
        emit VaultMultisig.MultiSigSignersUpdated();

        vm.expectEmit(false, false, false, true);
        emit VaultMultisig.QuorumUpdated(newQuorum);

        vault.updateSignersAndQuorum(newSigners, newQuorum);

        // Проверяем, что кворум обновился
        assertEq(vault.quorum(), newQuorum);

        // === ПРОВЕРКА УДАЛЕНИЯ СТАРЫХ ПОДПИСАНТОВ ===
        // Все старые подписанты должны потерять доступ
        vm.prank(signer1);
        vm.expectRevert(VaultMultisig.InvalidMultisigSigner.selector);
        vault.initiateTransfer(defaultRecepient, 1 ether);

        vm.prank(signer2);
        vm.expectRevert(VaultMultisig.InvalidMultisigSigner.selector);
        vault.initiateTransfer(defaultRecepient, 1 ether);

        vm.prank(signer3);
        vm.expectRevert(VaultMultisig.InvalidMultisigSigner.selector);
        vault.initiateTransfer(defaultRecepient, 1 ether);

        // === ПРОВЕРКА РАБОТЫ НОВЫХ ПОДПИСАНТОВ ===
        // Новые подписанты должны иметь доступ
        vm.prank(newSigners[0]);
        vault.initiateTransfer(defaultRecepient, 1 ether);

        // Проверяем состояние новой транзакции
        (address to, uint256 amount, uint256 approvals, bool executed) = vault.getTransfer(1);
        assertEq(to, defaultRecepient);
        assertEq(amount, 1 ether);
        assertEq(approvals, 1);
        assertEq(executed, false);

        // Второй новый подписант одобряет
        vm.prank(newSigners[1]);
        vault.approveTransfer(1);

        // Проверяем, что достигнут кворум
        (,, uint256 finalApprovals,) = vault.getTransfer(1);
        assertEq(finalApprovals, 2);

        // Выполняем транзакцию
        vm.prank(newSigners[0]);
        vault.executeTransfer(1);

        // Проверяем, что транзакция выполнена
        (,,, bool finalExecuted) = vault.getTransfer(1);
        assertTrue(finalExecuted);

        // === ПРОВЕРКА ФУНКЦИЙ ПРОСМОТРА ===
        // hasSignedTransfer должен работать корректно
        assertTrue(vault.hasSignedTransfer(1, newSigners[0]));
        assertTrue(vault.hasSignedTransfer(1, newSigners[1]));
        assertFalse(vault.hasSignedTransfer(1, newSigners[2]));

        // Проверяем общее количество транзакций
        assertEq(vault.getTransferCount(), 2);

        // === ПРОВЕРКА ПОВТОРНОГО ОБНОВЛЕНИЯ ===
        // Создаем еще один набор подписантов
        address[] memory newerSigners = new address[](1);
        newerSigners[0] = vm.addr(100);

        vm.prank(newSigners[0]);
        vault.updateSignersAndQuorum(newerSigners, 1);

        // Проверяем, что предыдущие новые подписанты тоже потеряли доступ
        vm.prank(newSigners[0]);
        vm.expectRevert(VaultMultisig.InvalidMultisigSigner.selector);
        vault.initiateTransfer(defaultRecepient, 1 ether);

        // А новейший подписант имеет доступ
        vm.prank(newerSigners[0]);
        vault.initiateTransfer(defaultRecepient, 1 ether);

        assertEq(vault.quorum(), 1);
        assertEq(vault.getTransferCount(), 3);
    }

    function fundVault(uint256 amount) internal {
        vm.deal(address(vault), amount);
    }
}
