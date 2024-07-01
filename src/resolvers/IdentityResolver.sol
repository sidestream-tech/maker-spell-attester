// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

import { SchemaResolver } from "lib/eas-contracts/contracts/resolver/SchemaResolver.sol";
import { IEAS, Attestation, AttestationRequest, AttestationRequestData, RevocationRequest, RevocationRequestData } from "lib/eas-contracts/contracts/IEAS.sol";
import { SpellAttesterAbstract } from "src/SpellAttesterAbstract.sol";

contract IdentityResolver is SchemaResolver {
    // --- Data ---

    /// @notice Internal name of the contract.
    bytes32 public constant name = "identity";

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

    /// @notice Mapping between user address and hash of the relevant pseudonym.
    mapping (address userAddress => bytes32 userPseudonymHash) public addressToPseudonymHash;

    /// @notice Mapping between pseudonym hash and hash of the relevant teamName.
    mapping (bytes32 userPseudonymHash => bytes32 userTeamHash) public pseudonymHashToTeamHash;

    // --- Events ---

    /// @notice Emitted when a new Identity is attested.
    /// @param attestationId Created attestation UID.
    /// @param attester Address of the attester.
    /// @param userPseudonymHash Hash of the attested userPseudonym.
    event Created(bytes32 attestationId, address indexed attester, bytes32 indexed userPseudonymHash);

    /// @notice Emitted when an Identity is revoked.
    /// @param attestationId Revoked attestation UID.
    /// @param attester Address of the attester.
    /// @param userPseudonymHash Hash of the revoked userPseudonym.
    event Removed(bytes32 attestationId, address indexed attester, bytes32 indexed userPseudonymHash);

    // --- Modifiers ---

    /// @notice Check admin rights using wards of the SpellAttester contract.
    /// @param attestation Attestation struct (provided by the EAS).
    modifier onlyAdmin(Attestation calldata attestation) {
        require(spellAttester.wards(attestation.attester) == 1, "IdentityResolver/not-authorized-attester");
        _;
    }

    /// @notice Check that only previously filed EAS schema can call this contract.
    /// @param attestation Attestation struct (provided by the EAS).
    modifier onlyKnownSchema(Attestation calldata attestation) {
        require(attestation.schema == spellAttester.schemaNameToSchemaId(name), "IdentityResolver/unknown-schema");
        _;
    }

    // --- Init ---

    /// @param _easAttester Ethereum Attestation Service main contract.
    /// @param _spellAttester Address of the main SpellAttester contract.
    constructor(address _easAttester, address _spellAttester) SchemaResolver(IEAS(_easAttester)) {
        spellAttester = SpellAttesterAbstract(_spellAttester);
    }

    // --- Internal helpers ---

    /// @dev Check if provided string contains only valid characters.
    /// @param str String to be checked.
    /// @return Result of the check.
    function isValidName(string memory str) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        for (uint256 i; i < strBytes.length; i++) {
            // Ensure each character is either lowercase latin letter or an underscore
            if (strBytes[i] < 0x61 && strBytes[i] != 0x5f || strBytes[i] > 0x7a) {
                return false;
            }
        }
        return true;
    }

    // --- Attestation hooks ---

    /// @inheritdoc SchemaResolver
    function onAttest(Attestation calldata attestation, uint256 value) internal override onlyAdmin(attestation) onlyKnownSchema(attestation) returns (bool) {
        // Ensure default values
        require(attestation.recipient == defaultAttestationData.recipient, "IdentityResolver/unexpected-recipient");
        require(attestation.expirationTime == defaultAttestationData.expirationTime, "IdentityResolver/unexpected-expirationTime");
        require(attestation.revocable == defaultAttestationData.revocable, "IdentityResolver/unexpected-revocable");
        require(attestation.refUID == defaultAttestationData.refUID, "IdentityResolver/unexpected-refUID");
        require(value == defaultAttestationData.value, "IdentityResolver/unexpected-value");

        (string memory userTeam, string memory userPseudonym, address userAddress) = abi.decode(attestation.data, (string, string, address));

        // Ensure userTeam and userPseudonym contains correct characters
        require(isValidName(userTeam) == true, "IdentityResolver/invalid-team-name");
        require(isValidName(userPseudonym) == true, "IdentityResolver/invalid-user-pseudonym");

        // Ensure uniqueness of userPseudonym
        bytes32 userPseudonymHash = keccak256(abi.encodePacked(userPseudonym));
        require(pseudonymHashToTeamHash[userPseudonymHash] == "", "IdentityResolver/pseudonym-already-attested");
        pseudonymHashToTeamHash[userPseudonymHash] = keccak256(abi.encodePacked(userTeam));

        // Ensure uniqueness of userAddress
        require(addressToPseudonymHash[userAddress] == "", "IdentityResolver/address-already-attested");
        addressToPseudonymHash[userAddress] = userPseudonymHash;

        emit Created(attestation.uid, attestation.attester, userPseudonymHash);
        return true;
    }

    /// @inheritdoc SchemaResolver
    function onRevoke(Attestation calldata attestation, uint256 value) internal override onlyAdmin(attestation) onlyKnownSchema(attestation) returns (bool) {
        // Ensure default values
        require(value == defaultAttestationData.value, "IdentityResolver/unexpected-value");

        // Cleanup storage
        (, string memory userPseudonym, address userAddress) = abi.decode(attestation.data, (string, string, address));
        addressToPseudonymHash[userAddress] = "";
        bytes32 userPseudonymHash = keccak256(abi.encodePacked(userPseudonym));
        pseudonymHashToTeamHash[userPseudonymHash] = "";

        emit Removed(attestation.uid, attestation.attester, userPseudonymHash);
        return true;
    }

    // --- External helpers ---

    /// @notice Helper to create Identity attestation request with default values.
    /// @param teamName Name of the team (only lowercase latin letters and underscores are accepted).
    /// @param userPseudonym Unique pseudonym of the new user (only lowercase latin letters and underscores are accepted).
    /// @param userAddress Unique user-controlled address.
    /// @return attestationRequest Attestation request submittable to the EAS.
    function createAttestationRequest(string memory teamName, string memory userPseudonym, address userAddress) external view returns (AttestationRequest memory attestationRequest) {
        attestationRequest = AttestationRequest({
            schema: spellAttester.schemaNameToSchemaId(name),
            data: AttestationRequestData({
                recipient: defaultAttestationData.recipient,
                expirationTime: defaultAttestationData.expirationTime,
                revocable: defaultAttestationData.revocable,
                refUID: defaultAttestationData.refUID,
                data: abi.encode(teamName, userPseudonym, userAddress),
                value: defaultAttestationData.value
            })
        });
    }

    /// @notice Helper to create Identity revocation request with default values.
    /// @param attestationId Uid of the previously created Identity attestation.
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
