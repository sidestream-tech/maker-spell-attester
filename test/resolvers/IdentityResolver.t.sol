// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

import { Test } from "forge-std/Test.sol";
import { AttestationRequest } from "lib/eas-contracts/contracts/IEAS.sol";
import { Helpers } from "script/Helpers.s.sol";
import { DeployAll, DeployParams, DeployInstance } from "script/dependencies/DeployAll.sol";

contract IdentityResolverTest is Test {
    string private json;
    DeployInstance private instance;

    // Test users
    address private alice = address(0x111);
    string private alicePseudonym = "alice";
    string private aliceTeam = "team_a";

    address private bob = address(0x222);
    string private bobPseudonym = "bob";
    string private bobTeam = "team_b";

    // Events
    event Created(bytes32 attestationId, address indexed attester, bytes32 indexed userPseudonymHash);
    event Removed(bytes32 attestationId, address indexed attester, bytes32 indexed userPseudonymHash);

    function setUp() public {
        json = Helpers.readInput();
        instance = DeployAll.deploy(DeployParams({
            easAttester: vm.parseJsonAddress(json, ".EAS_ATTESTER"),
            easRegistry: vm.parseJsonAddress(json, ".EAS_REGISTRY")
        }));
    }

    function testAttestRevokeAttest() public {
        AttestationRequest memory attestationRequest = instance.identityResolver.createAttestationRequest(aliceTeam, alicePseudonym, alice);
        vm.expectEmit(true, true, true, false); emit Created("", address(this), keccak256(abi.encodePacked(alicePseudonym)));
        bytes32 uid = instance.easAttester.attest(attestationRequest);
        bytes32 alicePseudonymHash = keccak256(abi.encodePacked(alicePseudonym));
        assertEq(instance.identityResolver.addressToPseudonymHash(alice), alicePseudonymHash);
        assertEq(instance.identityResolver.pseudonymHashToTeamHash(alicePseudonymHash), keccak256(abi.encodePacked(aliceTeam)));

        vm.expectEmit(true, true, true, true); emit Removed(uid, address(this), keccak256(abi.encodePacked(alicePseudonym)));
        instance.easAttester.revoke(instance.identityResolver.createRevocationRequest(uid));
        assertEq(instance.identityResolver.addressToPseudonymHash(alice), "");
        assertEq(instance.identityResolver.pseudonymHashToTeamHash(alicePseudonymHash), "");

        instance.easAttester.attest(attestationRequest);
    }

    function testOnlyAuthorizedUserCanAttest() public {
        address testUser = address(0x1);

        AttestationRequest memory attestationRequest = instance.identityResolver.createAttestationRequest(aliceTeam, alicePseudonym, alice);

        // Can not attest without being relied
        vm.startPrank(testUser);
        vm.expectRevert("IdentityResolver/not-authorized-attester");
        instance.easAttester.attest(attestationRequest);
        vm.stopPrank();

        // Can attest after being relied
        instance.spellAttester.rely(testUser);
        vm.prank(testUser);
        instance.easAttester.attest(attestationRequest);

        // Can not attest after being denied
        vm.startPrank(testUser);
        instance.spellAttester.deny(testUser);
        attestationRequest = instance.identityResolver.createAttestationRequest(bobTeam, bobPseudonym, bob);
        vm.expectRevert("IdentityResolver/not-authorized-attester");
        instance.easAttester.attest(attestationRequest);
        vm.stopPrank();
    }

    function testAttestRevertOnDuplicatedUserAddress() public {
        instance.easAttester.attest(instance.identityResolver.createAttestationRequest(aliceTeam, alicePseudonym, alice));

        AttestationRequest memory attestationRequest = instance.identityResolver.createAttestationRequest(aliceTeam, bobPseudonym, alice);
        vm.expectRevert("IdentityResolver/address-already-attested");
        instance.easAttester.attest(attestationRequest);
    }

    function testAttestRevertOnDuplicatedUserPseudonym() public {
        instance.easAttester.attest(instance.identityResolver.createAttestationRequest(aliceTeam, alicePseudonym, alice));

        AttestationRequest memory attestationRequest = instance.identityResolver.createAttestationRequest(aliceTeam, alicePseudonym, bob);
        vm.expectRevert("IdentityResolver/pseudonym-already-attested");
        instance.easAttester.attest(attestationRequest);
    }

    function testAttestationRevokeOnWrongDefaultValue() public {
        AttestationRequest memory attestationRequest = instance.identityResolver.createAttestationRequest(aliceTeam, alicePseudonym, alice);
        attestationRequest.data.recipient = address(0x1);
        vm.expectRevert("IdentityResolver/unexpected-recipient");
        instance.easAttester.attest(attestationRequest);

        attestationRequest = instance.identityResolver.createAttestationRequest(aliceTeam, alicePseudonym, alice);
        attestationRequest.data.expirationTime = uint64(block.timestamp + 1 days);
        vm.expectRevert("IdentityResolver/unexpected-expirationTime");
        instance.easAttester.attest(attestationRequest);

        attestationRequest = instance.identityResolver.createAttestationRequest(aliceTeam, alicePseudonym, alice);
        attestationRequest.data.revocable = false;
        vm.expectRevert("IdentityResolver/unexpected-revocable");
        instance.easAttester.attest(attestationRequest);

        bytes32 uid = instance.easAttester.attest(instance.identityResolver.createAttestationRequest(bobTeam, bobPseudonym, bob));
        attestationRequest = instance.identityResolver.createAttestationRequest(aliceTeam, alicePseudonym, alice);
        attestationRequest.data.refUID = uid;
        vm.expectRevert("IdentityResolver/unexpected-refUID");
        instance.easAttester.attest(attestationRequest);
    }

    function testNameValidity() public {
        string memory validString = "abcdefghijklmnopqrstuvwxyz_";
        instance.easAttester.attest(instance.identityResolver.createAttestationRequest(validString, validString, alice));

        string[12] memory invalidStrings = [
            " ", ",", "?", // Punctuation
            "1", "2", "0", // Numbers
            "A", "B", "Z", // Сapital letters
            unicode"ä", unicode"а", unicode"一" // Unicode characters
        ];
        for (uint256 i; i < invalidStrings.length; i++) {
            AttestationRequest memory attestationRequestWithInvalidTeam = instance.identityResolver.createAttestationRequest(invalidStrings[i], alicePseudonym, alice);
            vm.expectRevert("IdentityResolver/invalid-team-name");
            instance.easAttester.attest(attestationRequestWithInvalidTeam);

            AttestationRequest memory attestationRequestWithInvalidPseudonym = instance.identityResolver.createAttestationRequest(aliceTeam, invalidStrings[i], alice);
            vm.expectRevert("IdentityResolver/invalid-user-pseudonym");
            instance.easAttester.attest(attestationRequestWithInvalidPseudonym);
        }
    }
}
