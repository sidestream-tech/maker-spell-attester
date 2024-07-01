// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

import { Test } from "forge-std/Test.sol";
import { ISchemaResolver } from "lib/eas-contracts/contracts/resolver/ISchemaResolver.sol";
import { AttestationRequest } from "lib/eas-contracts/contracts/IEAS.sol";
import { Helpers } from "script/Helpers.s.sol";
import { DeployAll, DeployParams, DeployInstance } from "script/dependencies/DeployAll.sol";
import { TestContractA } from "test/testContract/TestContractA.sol";

interface VersionLike {
    function VERSION() external view returns (string memory);
}

contract SpellAttesterTest is Test {
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

    address private brian = address(0x223);
    string private brianPseudonym = "brian";
    string private brianTeam = "team_b";

    // Test payloadIds
    string private payloadId1 = "2024-01-01";
    string private payloadId2 = "2024-01-02";

    function setUp() public {
        json = Helpers.readInput();
        instance = DeployAll.deploy(DeployParams({
            easAttester: vm.parseJsonAddress(json, ".EAS_ATTESTER"),
            easRegistry: vm.parseJsonAddress(json, ".EAS_REGISTRY")
        }));
    }

    function testEasVersion() public view {
        assertEq(VersionLike(address(instance.spellAttester.easAttester())).VERSION(), "0.26");
        assertEq(VersionLike(address(instance.easRegistry)).VERSION(), "0.26");
    }

    function testAttesterValues() public view {
        assertEq(address(instance.spellAttester.easAttester()), vm.parseJsonAddress(json, ".EAS_ATTESTER"));
        assertEq(address(instance.spellAttester.easRegistry()), vm.parseJsonAddress(json, ".EAS_REGISTRY"));
        assertEq(
            address(instance.easRegistry.getSchema(instance.spellAttester.schemaNameToSchemaId("identity")).resolver),
            address(instance.identityResolver)
        );
        assertEq(
            address(instance.easRegistry.getSchema(instance.spellAttester.schemaNameToSchemaId("spell")).resolver),
            address(instance.spellResolver)
        );
        assertEq(
            address(instance.easRegistry.getSchema(instance.spellAttester.schemaNameToSchemaId("deployment")).resolver),
            address(instance.deploymentResolver)
        );
    }

    function testDefaultAuth() public view {
        assertEq(instance.spellAttester.wards(address(this)), 1);
    }

    function testOnlyAuthorizedUserCanFileSchema() public {
        address testUser = address(0x1);

        // Can not file without being relied
        vm.startPrank(testUser);
        vm.expectRevert("SpellAttester/not-authorized");
        instance.spellAttester.fileSchema("test", "id123");
        vm.stopPrank();

        // Can file after being relied
        instance.spellAttester.rely(testUser);
        vm.prank(testUser);
        instance.spellAttester.fileSchema("test", "id123");

        // Can not file after being denied
        vm.startPrank(testUser);
        instance.spellAttester.deny(testUser);
        vm.expectRevert("SpellAttester/not-authorized");
        instance.spellAttester.fileSchema("test", "id123");
        vm.stopPrank();
    }

    function testFileSchema() public {
        instance.spellAttester.fileSchema("test", "id123");
        assertEq(instance.spellAttester.schemaNameToSchemaId("test"), "id123");
    }

    function testSchemaByName() public {
        assertTrue(instance.spellAttester.getSchemaByName("identity").resolver == instance.identityResolver);
        assertEq(instance.spellAttester.getSchemaByName("identity").uid, instance.identitySchemaId);
        assertTrue(instance.spellAttester.getSchemaByName("spell").resolver == instance.spellResolver);
        assertEq(instance.spellAttester.getSchemaByName("spell").uid, instance.spellSchemaId);
        assertTrue(instance.spellAttester.getSchemaByName("deployment").resolver == instance.deploymentResolver);
        assertEq(instance.spellAttester.getSchemaByName("deployment").uid, instance.deploymentSchemaId);

        instance.spellAttester.fileSchema("test", "id123");
        assertTrue(instance.spellAttester.getSchemaByName("test").resolver == ISchemaResolver(address(0)));
        assertEq(instance.spellAttester.getSchemaByName("test").uid, "");
    }

    function testSpellStatus() public {
        // Throws "spell-not-found" by default
        vm.expectRevert("SpellAttester/spell-not-found");
        instance.spellAttester.getSpellAddressByPayloadId(payloadId1);

        // Throws "spell-not-yet-deployed" as soon as Spell is attested
        instance.easAttester.attest(instance.identityResolver.createAttestationRequest(aliceTeam, alicePseudonym, alice));
        instance.easAttester.attest(instance.identityResolver.createAttestationRequest(arthurTeam, arthurPseudonym, arthur));
        instance.easAttester.attest(instance.identityResolver.createAttestationRequest(bobTeam, bobPseudonym, bob));
        bytes32 spellAttestationId = instance.easAttester.attest(instance.spellResolver.createAttestationRequest(payloadId1, alicePseudonym, arthurPseudonym, bobPseudonym));
        vm.expectRevert("SpellAttester/spell-not-yet-deployed");
        instance.spellAttester.getSpellAddressByPayloadId(payloadId1);

        // Throws "spell-not-yet-reviewed" as soon as crafter attested Deployment
        address testContract = address(new TestContractA());
        bytes32 testContractHash = testContract.codehash;
        AttestationRequest memory deploymentAttestationRequest = instance.deploymentResolver.createAttestationRequest(payloadId1, testContract, testContractHash);
        vm.prank(alice);
        bytes32 crafterDeploymentUid = instance.easAttester.attest(deploymentAttestationRequest);
        vm.expectRevert("SpellAttester/spell-not-yet-reviewed");
        instance.spellAttester.getSpellAddressByPayloadId(payloadId1);

        // Throws "spell-not-yet-reviewed" if only confirmed by one reviewer
        vm.prank(arthur);
        instance.easAttester.attest(deploymentAttestationRequest);
        vm.expectRevert("SpellAttester/spell-not-yet-reviewed");
        instance.spellAttester.getSpellAddressByPayloadId(payloadId1);

        // Returns address if confirmed by both reviewers
        vm.prank(bob);
        instance.easAttester.attest(deploymentAttestationRequest);
        assertEq(testContract, instance.spellAttester.getSpellAddressByPayloadId(payloadId1));

        // Back to "spell-not-yet-deployed" after crafter revoked Deployment
        vm.startPrank(alice);
        instance.easAttester.revoke(instance.deploymentResolver.createRevocationRequest(crafterDeploymentUid));
        vm.stopPrank();
        vm.expectRevert("SpellAttester/spell-not-yet-deployed");
        instance.spellAttester.getSpellAddressByPayloadId(payloadId1);

        // Back to no errors after crafter re-attested Deployment
        vm.prank(alice);
        instance.easAttester.attest(deploymentAttestationRequest);
        assertEq(testContract, instance.spellAttester.getSpellAddressByPayloadId(payloadId1));

        // Back to "spell-not-yet-deployed" after Spell revocation
        instance.easAttester.revoke(instance.spellResolver.createRevocationRequest(spellAttestationId));
        vm.expectRevert("SpellAttester/spell-not-found");
        instance.spellAttester.getSpellAddressByPayloadId(payloadId1);

        // Back to  "spell-not-yet-deployed" after re-attesting Spell with a different crafter
        instance.easAttester.attest(instance.identityResolver.createAttestationRequest(brianTeam, brianPseudonym, brian));
        spellAttestationId = instance.easAttester.attest(instance.spellResolver.createAttestationRequest(payloadId1, brianPseudonym, arthurPseudonym, bobPseudonym));
        vm.expectRevert("SpellAttester/spell-not-yet-deployed");
        instance.spellAttester.getSpellAddressByPayloadId(payloadId1);

        // Back to no errors after re-attesting Spell with same members
        instance.easAttester.revoke(instance.spellResolver.createRevocationRequest(spellAttestationId));
        instance.easAttester.attest(instance.spellResolver.createAttestationRequest(payloadId1, alicePseudonym, arthurPseudonym, bobPseudonym));
        assertEq(testContract, instance.spellAttester.getSpellAddressByPayloadId(payloadId1));
    }
}
