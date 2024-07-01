// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

interface SpellResolverAbstract {
    /// @notice Get Spell attestationId from payloadIdHash.
    /// @param payloadIdHash hash of the payloadId string.
    /// @return attestationId UID of the Spell attestation.
    function payloadIdHashToAttestationId(bytes32 payloadIdHash) external view returns (bytes32 attestationId);
}
