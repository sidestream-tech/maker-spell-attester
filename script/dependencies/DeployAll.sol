// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

import { IEAS, ISchemaRegistry } from "lib/eas-contracts/contracts/IEAS.sol";
import { SpellAttester } from "src/SpellAttester.sol";
import { IdentityResolver } from "src/resolvers/IdentityResolver.sol";
import { SpellResolver } from "src/resolvers/SpellResolver.sol";
import { DeploymentResolver } from "src/resolvers/DeploymentResolver.sol";

struct DeployParams {
    address easAttester;
    address easRegistry;
}

struct DeployInstance {
    IEAS easAttester;
    ISchemaRegistry easRegistry;
    SpellAttester spellAttester;
    IdentityResolver identityResolver;
    bytes32 identitySchemaId;
    SpellResolver spellResolver;
    bytes32 spellSchemaId;
    DeploymentResolver deploymentResolver;
    bytes32 deploymentSchemaId;
}

library DeployAll {
    function deploy(DeployParams memory params) internal returns (DeployInstance memory instance) {
        instance.easAttester = IEAS(params.easAttester);
        instance.easRegistry = ISchemaRegistry(params.easRegistry);

        // Deploy main contract
        instance.spellAttester = new SpellAttester(params.easAttester, params.easRegistry);

        // Deploy identity resolver
        instance.identityResolver = new IdentityResolver(params.easAttester, address(instance.spellAttester));
        // Create identity attestation schema
        instance.identitySchemaId = instance.easRegistry.register(
            "string teamName, string userPseudonym, address userAddress",           // schema
            instance.identityResolver,                                              // resolver
            true                                                                    // revocable
        );
        // File identity schema id into the main contract
        instance.spellAttester.fileSchema(instance.identityResolver.name(), instance.identitySchemaId);

        // Deploy spell resolver
        instance.spellResolver = new SpellResolver(params.easAttester, address(instance.spellAttester));
        // Create spell attestation schema
        instance.spellSchemaId = instance.easRegistry.register(
            "string payloadId, string crafter, string reviewerA, string reviewerB", // schema
            instance.spellResolver,                                                  // resolver
            true                                                                    // revocable
        );
        // File spell schema id into the main contract
        instance.spellAttester.fileSchema(instance.spellResolver.name(), instance.spellSchemaId);

        // Deploy deployment resolver
        instance.deploymentResolver = new DeploymentResolver(params.easAttester, address(instance.spellAttester));
        // Create deployment attestation schema
        instance.deploymentSchemaId = instance.easRegistry.register(
            "string payloadId, address payloadAddress, bytes32 payloadHash",        // schema
            instance.deploymentResolver,                                            // resolver
            true                                                                    // revocable
        );
        // File deployment schema id into the main contract
        instance.spellAttester.fileSchema("deployment", instance.deploymentSchemaId);
    }
}
