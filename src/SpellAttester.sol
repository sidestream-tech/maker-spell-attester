// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

import { IEAS, Attestation } from "lib/eas-contracts/contracts/IEAS.sol";
import { ISchemaRegistry, SchemaRecord } from "lib/eas-contracts/contracts/ISchemaRegistry.sol";
import { SpellResolverAbstract } from "./resolvers/SpellResolverAbstract.sol";
import { DeploymentResolverAbstract } from "./resolvers/DeploymentResolverAbstract.sol";

/// @title A registry contract to keep relevant attestation schemas in one place.
contract SpellAttester {
    // --- Auth ---

    /// @notice Map with admins.
    mapping (address => uint256) public wards;

    /// @notice Add a new admin.
    /// @param usr Address that will become an admin.
    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }

    /// @notice Remove existing admin.
    /// @param usr Address that will loose admin rights.
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }

    /// @notice Check admin rights.
    modifier auth {
        require(wards[msg.sender] == 1, "SpellAttester/not-authorized");
        _;
    }

    // --- Data ---

    /// @notice Ethereum Attestation Service main contract.
    IEAS public immutable easAttester;

    /// @notice Ethereum Attestation Service schema registry.
    ISchemaRegistry public immutable easRegistry;

    /// @notice Mapping between schema names (e.g.: 'identity', 'spell', 'deployment') and their EAS ids.
    mapping (bytes32 schemaName => bytes32 schemaId) public schemaNameToSchemaId;

    /// @notice Mapping between schema names (e.g.: 'identity', 'spell', 'deployment') and their resolver contracts.
    mapping (bytes32 schemaName => address resolver) public schemaNameToResolver;

    // --- Events ---

    /// @notice Event emitted when new admin is added.
    /// @param usr Address that became admin.
    event Rely(address indexed usr);

    /// @notice Event emitted when admin is removed.
    /// @param usr Address that was removed from admins.
    event Deny(address indexed usr);

    // --- Init ---

    /// @param _easAttester Ethereum Attestation Service main contract.
    /// @param _easRegistry Ethereum Attestation Service schema registry.
    constructor(address _easAttester, address _easRegistry) {
        easAttester = IEAS(_easAttester);
        easRegistry = ISchemaRegistry(_easRegistry);
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Administration ---

    /// @notice Add, remove or replace schema id using its name.
    /// @param schemaName Internal schema name (e.g.: 'identity', 'spell', 'deployment').
    /// @param schemaId Attestation schema unique ID.
    function fileSchema(bytes32 schemaName, bytes32 schemaId) external auth {
        schemaNameToSchemaId[schemaName] = schemaId;
        schemaNameToResolver[schemaName] = address(easRegistry.getSchema(schemaId).resolver);
    }

    // --- Friendly helpers ---

    /// @notice Get full schema information using its name.
    /// @param schemaName Internal schema name (e.g.: 'identity', 'spell', 'deployment').
    /// @return schema Struct containing its id, resolver address, if its revocable, its ABI.
    function getSchemaByName(string memory schemaName) external view returns (SchemaRecord memory schema) {
        bytes32 schemaId = schemaNameToSchemaId[bytes32(bytes(schemaName))];
        schema = easRegistry.getSchema(schemaId);
    }

    /// @notice Get spell address after it is verified by the team.
    /// @param payloadId Unique string identifying a particular spell (e.g.: '2024-06-27').
    /// @return payloadAddress Address of the spell verified by two pre-defined reviewers.
    function getSpellAddressByPayloadId(string memory payloadId) external view returns (address) {
        bytes32 payloadIdHash = keccak256(abi.encodePacked(payloadId));
        bytes32 attestationId = SpellResolverAbstract(schemaNameToResolver["spell"]).payloadIdHashToAttestationId(payloadIdHash);
        Attestation memory spellAttestation = easAttester.getAttestation(attestationId);
        require(spellAttestation.uid != "", "SpellAttester/spell-not-found");

        DeploymentResolverAbstract deploymentResolver = DeploymentResolverAbstract(schemaNameToResolver["deployment"]);
        (, string memory crafter, string memory reviewerA, string memory reviewerB) = abi.decode(spellAttestation.data, (string, string, string, string));
        address payloadAddress = deploymentResolver.payloadIdHashToPseudonymHashToPayloadAddress(payloadIdHash, keccak256(abi.encodePacked(crafter)));
        require(payloadAddress != address(0), "SpellAttester/spell-not-yet-deployed");

        require(
            deploymentResolver.payloadIdHashToPseudonymHashToPayloadAddress(payloadIdHash, keccak256(abi.encodePacked(reviewerA))) != address(0) &&
            deploymentResolver.payloadIdHashToPseudonymHashToPayloadAddress(payloadIdHash, keccak256(abi.encodePacked(reviewerB))) != address(0)
        , "SpellAttester/spell-not-yet-reviewed");

        return payloadAddress;
    }
}
