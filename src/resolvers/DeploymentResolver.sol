// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

import { SchemaResolver } from "lib/eas-contracts/contracts/resolver/SchemaResolver.sol";
import { IEAS, Attestation, AttestationRequest, AttestationRequestData, RevocationRequest, RevocationRequestData } from "lib/eas-contracts/contracts/IEAS.sol";
import { SpellAttesterAbstract } from "src/SpellAttesterAbstract.sol";
import { IdentityResolverAbstract } from "./IdentityResolverAbstract.sol";
import { SpellResolverAbstract } from "./SpellResolverAbstract.sol";

contract DeploymentResolver is SchemaResolver {
    // --- Data ---

    /// @notice Internal name of the contract.
    bytes32 public constant name = "deployment";

    /// @notice Default attestation parameters.
    AttestationRequestData public defaultAttestationData = AttestationRequestData({
        recipient: address(0), // No recipient
        expirationTime: 0,     // No expiration time
        revocable: true,       // Revocable
        refUID: 0,             // No references UID
        data: "",              // Empty data
        value: 0               // No value/ETH
    });

    /// @notice Address of the main SpellAttester contract.
    SpellAttesterAbstract public immutable spellAttester;

    /// @notice Mapping between hashed payloadId strings, hashed userPseudonym and the attested payload address.
    mapping (bytes32 payloadIdHash => mapping (bytes32 pseudonymHash => address payloadAddress)) public payloadIdHashToPseudonymHashToPayloadAddress;

    /// @notice Mapping between hashed payloadId strings, hashed userPseudonym and the attested payload hash.
    mapping (bytes32 payloadIdHash => mapping (bytes32 pseudonymHash => bytes32 payloadHash)) public payloadIdHashToPseudonymHashToPayloadHash;

    // --- Events ---

    /// @notice Emitted when a new Deployment is attested.
    /// @param attestationId Created attestation UID.
    /// @param attester Address of the attester.
    /// @param payloadIdHash Hash of the attested payloadId.
    event Created(bytes32 attestationId, address indexed attester, bytes32 indexed payloadIdHash);

    /// @notice Emitted when an Deployment is revoked.
    /// @param attestationId Revoked attestation UID.
    /// @param attester Address of the attester.
    /// @param payloadIdHash Hash of the revoked payloadId.
    event Removed(bytes32 attestationId, address indexed attester, bytes32 indexed payloadIdHash);

    // --- Modifiers ---

    /// @notice Check that only previously filed EAS schema can call this contract.
    /// @param attestation Attestation struct (provided by the EAS).
    modifier onlyKnownSchema(Attestation calldata attestation) {
        require(attestation.schema == spellAttester.schemaNameToSchemaId(name), "DeploymentResolver/unknown-schema");
        _;
    }

    // --- Init ---

    /// @param _easAttester Ethereum Attestation Service main contract.
    /// @param _spellAttester Address of the main SpellAttester contract.
    constructor(address _easAttester, address _spellAttester) SchemaResolver(IEAS(_easAttester)) {
        spellAttester = SpellAttesterAbstract(_spellAttester);
    }

    // --- Attestation hooks ---

    /// @inheritdoc SchemaResolver
    function onAttest(Attestation calldata attestation, uint256 value) internal override onlyKnownSchema(attestation) returns (bool) {
        // Ensure default values
        require(attestation.recipient == defaultAttestationData.recipient, "DeploymentResolver/unexpected-recipient");
        require(attestation.expirationTime == defaultAttestationData.expirationTime, "DeploymentResolver/unexpected-expirationTime");
        require(attestation.revocable == defaultAttestationData.revocable, "DeploymentResolver/unexpected-revocable");
        require(attestation.refUID == defaultAttestationData.refUID, "DeploymentResolver/unexpected-refUID");
        require(value == defaultAttestationData.value, "DeploymentResolver/unexpected-value");

        (string memory payloadId, address payloadAddress, bytes32 payloadHash) = abi.decode(attestation.data, (string, address, bytes32));

        // Ensure payloadId was previously attested via Spell
        bytes32 payloadIdHash = keccak256(abi.encodePacked(payloadId));
        bytes32 spellAttestationId = SpellResolverAbstract(spellAttester.schemaNameToResolver("spell")).payloadIdHashToAttestationId(payloadIdHash);
        require(spellAttestationId != "", "DeploymentResolver/unknown-payload-id");

        (, string memory crafter, string memory reviewerA, string memory reviewerB) = abi.decode(
            _eas.getAttestation(spellAttestationId).data,
            (string, string, string, string)
        );

        {
            // Ensure only relevant Spell attestation members can attest
            bytes32 crafterPseudonymHash = keccak256(abi.encodePacked(crafter));
            bytes32 attesterPseudonymHash = IdentityResolverAbstract(spellAttester.schemaNameToResolver("identity")).addressToPseudonymHash(attestation.attester);
            require(
                attesterPseudonymHash == crafterPseudonymHash ||
                attesterPseudonymHash == keccak256(abi.encodePacked(reviewerA)) ||
                attesterPseudonymHash == keccak256(abi.encodePacked(reviewerB)),
            "DeploymentResolver/not-spell-member");

            // Ensure only one attestation is possible per payloadId
            require(payloadIdHashToPseudonymHashToPayloadAddress[payloadIdHash][attesterPseudonymHash] == address(0), "DeploymentResolver/already-attested-by-you");
            payloadIdHashToPseudonymHashToPayloadAddress[payloadIdHash][attesterPseudonymHash] = payloadAddress;

            // Ensure crafter already attested this payloadId
            address craftersPayloadAddress = payloadIdHashToPseudonymHashToPayloadAddress[payloadIdHash][crafterPseudonymHash];
            require(craftersPayloadAddress != address(0), "DeploymentResolver/not-crafter-first");

            // Ensure payloadAddress is the same as provided by the crafter
            require(payloadAddress == craftersPayloadAddress, "DeploymentResolver/unknown-payload-address");

            // Ensure payloadHash matches hash of the payloadAddress
            // TODO re-enable the check before mainnnet deployment
            // require(payloadHash == payloadAddress.codehash, "DeploymentResolver/incorrect-payload-hash");

            // Ensure payloadHash isn't of empty address
            require(payloadHash != keccak256(""), "DeploymentResolver/empty-payload-hash");

            // Ensure payloadHash is the same as provided by the crafter
            payloadIdHashToPseudonymHashToPayloadHash[payloadIdHash][attesterPseudonymHash] = payloadHash;
            require(payloadHash == payloadIdHashToPseudonymHashToPayloadHash[payloadIdHash][crafterPseudonymHash], "DeploymentResolver/unknown-payload-hash");
        }

        emit Created(attestation.uid, attestation.attester, payloadIdHash);
        return true;
    }

    /// @inheritdoc SchemaResolver
    function onRevoke(Attestation calldata attestation, uint256 value) internal override onlyKnownSchema(attestation) returns (bool) {
        // Ensure default values
        require(value == defaultAttestationData.value, "DeploymentResolver/unexpected-value");

        // Cleanup storage
        (string memory payloadId, , ) = abi.decode(attestation.data, (string, address, bytes32));
        bytes32 attesterPseudonymHash = IdentityResolverAbstract(spellAttester.schemaNameToResolver("identity")).addressToPseudonymHash(attestation.attester);
        bytes32 payloadIdHash = keccak256(abi.encodePacked(payloadId));
        payloadIdHashToPseudonymHashToPayloadAddress[payloadIdHash][attesterPseudonymHash] = address(0);
        payloadIdHashToPseudonymHashToPayloadHash[payloadIdHash][attesterPseudonymHash] = "";

        emit Removed(attestation.uid, attestation.attester, payloadIdHash);
        return true;
    }

    // --- External helpers ---

    /// @notice Helper to create Deployment attestation request with default values.
    /// @param payloadId Unique string identifying a particular spell (e.g.: '2024-06-27').
    /// @param payloadAddress Address of the spell.
    /// @param payloadHash EXTCODEHASH of the spell (generated locally from the reviewed spell code).
    /// @return attestationRequest Attestation request submittable to the EAS.
    function createAttestationRequest(string memory payloadId, address payloadAddress, bytes32 payloadHash) external view returns (AttestationRequest memory attestationRequest) {
        attestationRequest = AttestationRequest({
            schema: spellAttester.schemaNameToSchemaId(name),
            data: AttestationRequestData({
                recipient: defaultAttestationData.recipient,
                expirationTime: defaultAttestationData.expirationTime,
                revocable: defaultAttestationData.revocable,
                refUID: defaultAttestationData.refUID,
                data: abi.encode(payloadId, payloadAddress, payloadHash),
                value: defaultAttestationData.value
            })
        });
    }

    /// @notice Helper to create Deployment revocation request with default values.
    /// @param attestationId Uid of the previously created Deployment attestation.
    /// @return revocationRequest Revocation request submittable to the EAS.
    function createRevocationRequest(bytes32 attestationId) external view returns (RevocationRequest memory revocationRequest) {
        revocationRequest = RevocationRequest({
            schema: spellAttester.schemaNameToSchemaId(name),
            data: RevocationRequestData({
                uid: attestationId,
                value: defaultAttestationData.value
            })
        });
    }
}
