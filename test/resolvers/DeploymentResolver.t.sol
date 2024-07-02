
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

import { Test } from "forge-std/Test.sol";
import { AttestationRequest } from "lib/eas-contracts/contracts/IEAS.sol";
import { Helpers } from "script/Helpers.s.sol";
import { DeployAll, DeployParams, DeployInstance } from "script/dependencies/DeployAll.sol";
import { TestContractA } from "test/testContract/TestContractA.sol";
import { TestContractB } from "test/testContract/TestContractB.sol";

contract DeploymentResolverTest is Test {
    string private json;
    DeployInstance private instance;

    // Test users
    address private alice = address(0x111);
    string private alicePseudonym = "alice";
    string private aliceTeam = "team_a";

    address private arthur = address(0x112);
    string private arthurPseudonym = "arthur";
    string private arthurTeam = "team_a";

    address private bob = address(0x222);
    string private bobPseudonym = "bob";
    string private bobTeam = "team_b";

    // Test payloadIds
    string private payloadId1 = "2024-01-01";
    string private payloadId2 = "2024-01-02";

    // Test contract data
    address private testContractA;
    address private testContractB;

    // Events
    event Created(bytes32 attestationId, address indexed attester, bytes32 indexed payloadIdHash);
    event Removed(bytes32 attestationId, address indexed attester, bytes32 indexed payloadIdHash);

    function setUp() public {
        json = Helpers.readInput();
        instance = DeployAll.deploy(DeployParams({
            easAttester: vm.parseJsonAddress(json, ".EAS_ATTESTER"),
            easRegistry: vm.parseJsonAddress(json, ".EAS_REGISTRY")
        }));

        // Create identity attestation for all test users
        instance.easAttester.attest(instance.identityResolver.createAttestationRequest(aliceTeam, alicePseudonym, alice));
        instance.easAttester.attest(instance.identityResolver.createAttestationRequest(arthurTeam, arthurPseudonym, arthur));
        instance.easAttester.attest(instance.identityResolver.createAttestationRequest(bobTeam, bobPseudonym, bob));

        // Create Spell attestation
        instance.easAttester.attest(instance.spellResolver.createAttestationRequest(payloadId1, alicePseudonym, arthurPseudonym, bobPseudonym));

        // Deploy test contract
        testContractA = address(new TestContractA());
        testContractB = address(new TestContractB());
    }

    function testAttestRevokeAttest() public {
        AttestationRequest memory attestationRequest = instance.deploymentResolver.createAttestationRequest(payloadId1, testContractA, testContractA.codehash);
        bytes32 payloadIdHash = keccak256(abi.encodePacked(payloadId1));
        bytes32 alicePseudonymHash = keccak256(abi.encodePacked(alicePseudonym));

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, false); emit Created("", alice, payloadIdHash);
        bytes32 uid = instance.easAttester.attest(attestationRequest);
        assertEq(instance.deploymentResolver.payloadIdHashToPseudonymHashToPayloadAddress(payloadIdHash, alicePseudonymHash), testContractA);

        vm.expectEmit(true, true, true, true); emit Removed(uid, alice, payloadIdHash);
        instance.easAttester.revoke(instance.deploymentResolver.createRevocationRequest(uid));
        assertEq(instance.deploymentResolver.payloadIdHashToPseudonymHashToPayloadAddress(payloadIdHash, alicePseudonymHash), address(0));

        instance.easAttester.attest(attestationRequest);
        vm.stopPrank();
    }

    function testOnlyMatchingSpellMembersCanAttestDeployment() public {
        AttestationRequest memory attestationRequest = instance.deploymentResolver.createAttestationRequest(payloadId1, testContractA, testContractA.codehash);

        // Non-spell member can not attest
        address charlie = address(0x311);
        string memory charliePseudonym = "charlie";
        string memory charlieTeam = "team_c";
        instance.easAttester.attest(instance.identityResolver.createAttestationRequest(charlieTeam, charliePseudonym, charlie));
        vm.startPrank(charlie);
        vm.expectRevert("DeploymentResolver/not-spell-member");
        instance.easAttester.attest(attestationRequest);
        vm.stopPrank();

        // Valid Spell members of another payloadId can not attest
        instance.easAttester.attest(instance.spellResolver.createAttestationRequest(payloadId2, alicePseudonym, arthurPseudonym, charliePseudonym));
        vm.startPrank(charlie);
        vm.expectRevert("DeploymentResolver/not-spell-member");
        instance.easAttester.attest(attestationRequest);
        vm.stopPrank();
    }

    function testNotCrafterFirst() public {
        AttestationRequest memory attestationRequest = instance.deploymentResolver.createAttestationRequest(payloadId1, testContractA, testContractA.codehash);

        // Will fail if a reviewer tries to attest first
        vm.prank(arthur);
        vm.expectRevert("DeploymentResolver/not-crafter-first");
        instance.easAttester.attest(attestationRequest);

        vm.prank(bob);
        vm.expectRevert("DeploymentResolver/not-crafter-first");
        instance.easAttester.attest(attestationRequest);

        // But works in the correct order
        vm.prank(alice);
        instance.easAttester.attest(attestationRequest);
        vm.prank(arthur);
        instance.easAttester.attest(attestationRequest);
        vm.prank(bob);
        instance.easAttester.attest(attestationRequest);
    }

    function testUnknownPayloadAddress() public {
        AttestationRequest memory aliceAttestationRequest = instance.deploymentResolver.createAttestationRequest(payloadId1, testContractA, testContractA.codehash);
        vm.prank(alice);
        instance.easAttester.attest(aliceAttestationRequest);

        AttestationRequest memory arthurAttestationRequest = instance.deploymentResolver.createAttestationRequest(payloadId1, testContractB, testContractB.codehash);
        vm.prank(arthur);
        vm.expectRevert("DeploymentResolver/unknown-payload-address");
        instance.easAttester.attest(arthurAttestationRequest);
    }

    function testUnknownPayloadHash() public {
        AttestationRequest memory aliceAttestationRequest = instance.deploymentResolver.createAttestationRequest(payloadId1, testContractA, testContractA.codehash);
        vm.prank(alice);
        instance.easAttester.attest(aliceAttestationRequest);

        AttestationRequest memory arthurAttestationRequest = instance.deploymentResolver.createAttestationRequest(payloadId1, testContractA, testContractB.codehash);
        vm.prank(arthur);
        vm.expectRevert("DeploymentResolver/unknown-payload-hash");
        instance.easAttester.attest(arthurAttestationRequest);
    }

    function testRevertOnNotAttestedPayloadId() public {
        AttestationRequest memory attestationRequest = instance.deploymentResolver.createAttestationRequest(payloadId2, testContractA, testContractA.codehash);
        vm.expectRevert("DeploymentResolver/unknown-payload-id");
        instance.easAttester.attest(attestationRequest);
    }

    function testRevertOnDuplicatedPayloadIdAndAttesterCombination() public {
        AttestationRequest memory attestationRequest = instance.deploymentResolver.createAttestationRequest(payloadId1, testContractA, testContractA.codehash);
        vm.startPrank(alice);
        bytes32 uid = instance.easAttester.attest(attestationRequest);

        // Second attest will revert
        vm.expectRevert("DeploymentResolver/already-attested-by-you");
        instance.easAttester.attest(attestationRequest);

        // But will not revert if revoked
        instance.easAttester.revoke(instance.deploymentResolver.createRevocationRequest(uid));
        instance.easAttester.attest(attestationRequest);
        vm.stopPrank();
    }

    function testRevertOnEmptyAddress() public {
        AttestationRequest memory attestationRequest = instance.deploymentResolver.createAttestationRequest(payloadId1, address(1), keccak256(""));
        vm.startPrank(alice);
        vm.expectRevert("DeploymentResolver/empty-payload-hash");
        instance.easAttester.attest(attestationRequest);
        vm.stopPrank();
    }

    // TODO re-enable the check before mainnnet deployment
    // function testRevertOnIncorrectPayloadHash() public {
    //     AttestationRequest memory attestationRequestWithIncorrectPayloadHash = instance.deploymentResolver.createAttestationRequest(payloadId1, testContractA, keccak256("WrongHash"));
    //     vm.startPrank(alice);
    //     vm.expectRevert("DeploymentResolver/incorrect-payload-hash");
    //     instance.easAttester.attest(attestationRequestWithIncorrectPayloadHash);
    //     vm.stopPrank();
    // }

    function testRevokeOnWrongDefaultData() public {
        AttestationRequest memory attestationRequest = instance.deploymentResolver.createAttestationRequest(payloadId1, testContractA, testContractA.codehash);
        attestationRequest.data.recipient = address(0x1);
        vm.expectRevert("DeploymentResolver/unexpected-recipient");
        instance.easAttester.attest(attestationRequest);

        attestationRequest = instance.deploymentResolver.createAttestationRequest(payloadId1, testContractA, testContractA.codehash);
        attestationRequest.data.expirationTime = uint64(block.timestamp + 1 days);
        vm.expectRevert("DeploymentResolver/unexpected-expirationTime");
        instance.easAttester.attest(attestationRequest);

        attestationRequest = instance.deploymentResolver.createAttestationRequest(payloadId1, testContractA, testContractA.codehash);
        attestationRequest.data.revocable = false;
        vm.expectRevert("DeploymentResolver/unexpected-revocable");
        instance.easAttester.attest(attestationRequest);

        bytes32 spellAttestationId = instance.easAttester.attest(instance.spellResolver.createAttestationRequest(payloadId2, alicePseudonym, arthurPseudonym, bobPseudonym));
        attestationRequest = instance.deploymentResolver.createAttestationRequest(payloadId1, testContractA, testContractA.codehash);
        attestationRequest.data.refUID = spellAttestationId;
        vm.expectRevert("DeploymentResolver/unexpected-refUID");
        instance.easAttester.attest(attestationRequest);
    }
}
