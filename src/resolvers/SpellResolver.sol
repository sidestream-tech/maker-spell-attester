// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

import { SchemaResolver } from "lib/eas-contracts/contracts/resolver/SchemaResolver.sol";
import { IEAS, Attestation, AttestationRequest, AttestationRequestData, RevocationRequest, RevocationRequestData } from "lib/eas-contracts/contracts/IEAS.sol";
import { SpellAttesterAbstract } from "src/SpellAttesterAbstract.sol";
import { IdentityResolverAbstract } from "./IdentityResolverAbstract.sol";

/// @title Ethereum Attestation Service resolver contract for the Spell attestation.
contract SpellResolver is SchemaResolver {
    // --- Data ---

    /// @notice Internal name of the contract.
    bytes32 public constant name = "spell";

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

    /// @notice Mapping between hashed payloadId strings and relevant Spell attestation UID.
    mapping (bytes32 payloadIdHash => bytes32 attestationId) public payloadIdHashToAttestationId;

    // --- Events ---

    /// @notice Emitted when a new Spell is attested.
    /// @param attestationId Created attestation UID.
    /// @param attester Address of the attester.
    /// @param payloadIdHash Hash of the attested payloadId.
    event Created(bytes32 attestationId, address indexed attester, bytes32 indexed payloadIdHash);

    /// @notice Emitted when an Spell is revoked.
    /// @param attestationId Revoked attestation UID.
    /// @param attester Address of the attester.
    /// @param payloadIdHash Hash of the revoked payloadId.
    event Removed(bytes32 attestationId, address indexed attester, bytes32 indexed payloadIdHash);

    // --- Modifiers ---

    /// @notice Check admin rights using wards of the SpellAttester contract.
    /// @param attestation Attestation struct (provided by the EAS).
    modifier onlyAdmin(Attestation calldata attestation) {
        require(spellAttester.wards(attestation.attester) == 1, "SpellResolver/not-authorized-attester");
        _;
    }

    /// @notice Check that only previously filed EAS schema can call this contract.
    /// @param attestation Attestation struct (provided by the EAS).
    modifier onlyKnownSchema(Attestation calldata attestation) {
        require(attestation.schema == spellAttester.schemaNameToSchemaId(name), "SpellResolver/unknown-schema");
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
    function onAttest(Attestation calldata attestation, uint256 value) internal override onlyAdmin(attestation) onlyKnownSchema(attestation) returns (bool) {
        // Ensure default values
        require(attestation.recipient == defaultAttestationData.recipient, "SpellResolver/unexpected-recipient");
        require(attestation.expirationTime == defaultAttestationData.expirationTime, "SpellResolver/unexpected-expirationTime");
        require(attestation.revocable == defaultAttestationData.revocable, "SpellResolver/unexpected-revocable");
        require(attestation.refUID == defaultAttestationData.refUID, "SpellResolver/unexpected-refUID");
        require(value == defaultAttestationData.value, "SpellResolver/unexpected-value");

        (string memory payloadId, string memory crafter, string memory reviewerA, string memory reviewerB) = abi.decode(attestation.data, (string, string, string, string));

        // Ensure uniqueness of payloadId
        bytes32 payloadIdHash = keccak256(abi.encodePacked(payloadId));
        require(payloadIdHashToAttestationId[payloadIdHash] == "", "SpellResolver/already-attested-payload-id");
        payloadIdHashToAttestationId[payloadIdHash] = attestation.uid;

        {
            // Ensure crafters pseudonym was previously attested via Identity
            IdentityResolverAbstract identityResolver = IdentityResolverAbstract(spellAttester.schemaNameToResolver("identity"));
            bytes32 crafterHash = keccak256(abi.encodePacked(crafter));
            require(identityResolver.pseudonymHashToTeamHash(crafterHash) != "", "SpellResolver/unknown-crafter");

            // Ensure reviewers A pseudonym was previously attested via Identity
            bytes32 reviewerAHash = keccak256(abi.encodePacked(reviewerA));
            bytes32 reviewerAteamHash = identityResolver.pseudonymHashToTeamHash(reviewerAHash);
            require(reviewerAteamHash != "", "SpellResolver/unknown-reviewerA");

            // Ensure reviewers B pseudonym was previously attested via Identity
            bytes32 reviewerBHash = keccak256(abi.encodePacked(reviewerB));
            bytes32 reviewerBteamHash = identityResolver.pseudonymHashToTeamHash(reviewerBHash);
            require(reviewerBteamHash != "", "SpellResolver/unknown-reviewerB");

            // Ensure all pseudonyms are different
            require(
                crafterHash != reviewerAHash &&
                crafterHash != reviewerBHash &&
                reviewerAHash != reviewerBHash,
                "SpellResolver/non-unique-spell-members"
            );

            // Ensure both reviewers have different team names
            require(reviewerAteamHash != reviewerBteamHash, "SpellResolver/same-team-reviewers");
        }

        emit Created(attestation.uid, attestation.attester, payloadIdHash);
        return true;
    }

    /// @inheritdoc SchemaResolver
    function onRevoke(Attestation calldata attestation, uint256 value) internal override onlyAdmin(attestation) onlyKnownSchema(attestation) returns (bool) {
        // Ensure default values
        require(value == defaultAttestationData.value, "SpellResolver/unexpected-value");

        // Cleanup storage
        (string memory payloadId, , , ) = abi.decode(attestation.data, (string, string, string, string));
        bytes32 payloadIdHash = keccak256(abi.encodePacked(payloadId));
        payloadIdHashToAttestationId[payloadIdHash] = "";

        emit Removed(attestation.uid, attestation.attester, payloadIdHash);
        return true;
    }

    // --- External helpers ---

    /// @notice Helper to create Spell attestation request with default values.
    /// @param payloadId Unique string identifying a particular spell (e.g.: '2024-06-27').
    /// @param crafter userPseudonym of a previously created Identity attestation that will get a crafter role.
    /// @param reviewerA userPseudonym of a previously created Identity attestation that will get a reviewer role.
    /// @param reviewerB userPseudonym of a previously created Identity attestation that will get a reviewer role.
    /// @return attestationRequest Attestation request submittable to the EAS.
    function createAttestationRequest(string memory payloadId, string memory crafter, string memory reviewerA, string memory reviewerB) external view returns (AttestationRequest memory attestationRequest) {
        attestationRequest = AttestationRequest({
            schema: spellAttester.schemaNameToSchemaId(name),
            data: AttestationRequestData({
                recipient: defaultAttestationData.recipient,
                expirationTime: defaultAttestationData.expirationTime,
                revocable: defaultAttestationData.revocable,
                refUID: defaultAttestationData.refUID,
                data: abi.encode(payloadId, crafter, reviewerA, reviewerB),
                value: defaultAttestationData.value
            })
        });
    }

    /// @notice Helper to create Spell revocation request with default values.
    /// @param attestationId Uid of the previously created Spell attestation.
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
