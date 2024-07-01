
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

import { Test } from "forge-std/Test.sol";
import { Helpers } from "script/Helpers.s.sol";
import { DeployAll, DeployParams, DeployInstance } from "script/dependencies/DeployAll.sol";
import { AttestationRequest } from "lib/eas-contracts/contracts/IEAS.sol";

contract SpellResolverTest is Test {
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
    }

    function testAttestRevokeAttest() public {
        AttestationRequest memory attestationRequest = instance.spellResolver.createAttestationRequest(payloadId1, alicePseudonym, arthurPseudonym, bobPseudonym);
        vm.expectEmit(true, true, true, false); emit Created("", address(this), keccak256(abi.encodePacked(payloadId1)));
        bytes32 uid = instance.easAttester.attest(attestationRequest);
        assertEq(instance.spellResolver.payloadIdHashToAttestationId(keccak256(abi.encodePacked(payloadId1))), uid);

        vm.expectEmit(true, true, true, true); emit Removed(uid, address(this), keccak256(abi.encodePacked(payloadId1)));
        instance.easAttester.revoke(instance.spellResolver.createRevocationRequest(uid));
        assertEq(instance.spellResolver.payloadIdHashToAttestationId(keccak256(abi.encodePacked(payloadId1))), "");

        instance.easAttester.attest(attestationRequest);
    }

    function testOnlyAuthorizedUserCanAttestSpell() public {
        address testUser = address(0x1);

        AttestationRequest memory attestationRequest = instance.spellResolver.createAttestationRequest(payloadId1, alicePseudonym, arthurPseudonym, bobPseudonym);

        // Can not attest without being relied
        vm.startPrank(testUser);
        vm.expectRevert("SpellResolver/not-authorized-attester");
        instance.easAttester.attest(attestationRequest);
        vm.stopPrank();

        // Can attest after being relied
        instance.spellAttester.rely(testUser);
        vm.prank(testUser);
        instance.easAttester.attest(attestationRequest);

        // Can not attest after being denied
        vm.startPrank(testUser);
        instance.spellAttester.deny(testUser);
        attestationRequest = instance.spellResolver.createAttestationRequest(payloadId2, alicePseudonym, arthurPseudonym, bobPseudonym);
        vm.expectRevert("SpellResolver/not-authorized-attester");
        instance.easAttester.attest(attestationRequest);
        vm.stopPrank();
    }

    function testRevertOnDuplicatedPayloadId() public {
        AttestationRequest memory attestationRequest1 = instance.spellResolver.createAttestationRequest(payloadId1, alicePseudonym, arthurPseudonym, bobPseudonym);
        instance.easAttester.attest(attestationRequest1);
        AttestationRequest memory attestationRequest2 = instance.spellResolver.createAttestationRequest(payloadId1, bobPseudonym, alicePseudonym, arthurPseudonym);
        vm.expectRevert("SpellResolver/already-attested-payload-id");
        instance.easAttester.attest(attestationRequest2);
    }

    function testRevertOnUnknownCrafter() public {
        AttestationRequest memory attestationRequest = instance.spellResolver.createAttestationRequest(payloadId1, "unknownPseudonym", bobPseudonym, arthurPseudonym);
        vm.expectRevert("SpellResolver/unknown-crafter");
        instance.easAttester.attest(attestationRequest);
    }

    function testRevertOnUnknownReviewerA() public {
        AttestationRequest memory attestationRequest = instance.spellResolver.createAttestationRequest(payloadId1, alicePseudonym, "unknownPseudonym", arthurPseudonym);
        vm.expectRevert("SpellResolver/unknown-reviewerA");
        instance.easAttester.attest(attestationRequest);
    }

    function testRevertOnUnknownReviewerB() public {
        AttestationRequest memory attestationRequest = instance.spellResolver.createAttestationRequest(payloadId1, alicePseudonym, bobPseudonym, "unknownPseudonym");
        vm.expectRevert("SpellResolver/unknown-reviewerB");
        instance.easAttester.attest(attestationRequest);
    }

    function testRevertOnSameTeamReviewers() public {
        AttestationRequest memory attestationRequest = instance.spellResolver.createAttestationRequest(payloadId1, bobPseudonym, alicePseudonym, arthurPseudonym);
        vm.expectRevert("SpellResolver/same-team-reviewers");
        instance.easAttester.attest(attestationRequest);
    }

    function testRevertOnNonUniqueSpellMembers() public {
        AttestationRequest memory attestationRequest = instance.spellResolver.createAttestationRequest(payloadId1, alicePseudonym, alicePseudonym, bobPseudonym);
        vm.expectRevert("SpellResolver/non-unique-spell-members");
        instance.easAttester.attest(attestationRequest);

        attestationRequest = instance.spellResolver.createAttestationRequest(payloadId1, alicePseudonym, bobPseudonym, bobPseudonym);
        vm.expectRevert("SpellResolver/non-unique-spell-members");
        instance.easAttester.attest(attestationRequest);

        attestationRequest = instance.spellResolver.createAttestationRequest(payloadId1, bobPseudonym, alicePseudonym, bobPseudonym);
        vm.expectRevert("SpellResolver/non-unique-spell-members");
        instance.easAttester.attest(attestationRequest);
    }

    function testRevokeOnWrongDefaultData() public {
        AttestationRequest memory attestationRequest = instance.spellResolver.createAttestationRequest(payloadId1, alicePseudonym, arthurPseudonym, bobPseudonym);
        attestationRequest.data.recipient = address(0x1);
        vm.expectRevert("SpellResolver/unexpected-recipient");
        instance.easAttester.attest(attestationRequest);

        attestationRequest = instance.spellResolver.createAttestationRequest(payloadId1, alicePseudonym, arthurPseudonym, bobPseudonym);
        attestationRequest.data.expirationTime = uint64(block.timestamp + 1 days);
        vm.expectRevert("SpellResolver/unexpected-expirationTime");
        instance.easAttester.attest(attestationRequest);

        attestationRequest = instance.spellResolver.createAttestationRequest(payloadId1, alicePseudonym, arthurPseudonym, bobPseudonym);
        attestationRequest.data.revocable = false;
        vm.expectRevert("SpellResolver/unexpected-revocable");
        instance.easAttester.attest(attestationRequest);

        bytes32 uid = instance.easAttester.attest(instance.spellResolver.createAttestationRequest(payloadId2, alicePseudonym, arthurPseudonym, bobPseudonym));
        attestationRequest = instance.spellResolver.createAttestationRequest(payloadId1, alicePseudonym, arthurPseudonym, bobPseudonym);
        attestationRequest.data.refUID = uid;
        vm.expectRevert("SpellResolver/unexpected-refUID");
        instance.easAttester.attest(attestationRequest);
    }
}
