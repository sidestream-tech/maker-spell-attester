// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

interface DeploymentResolverAbstract {
    /// @notice Get Deployment attestationId from payloadIdHash and pseudonymHash.
    /// @param payloadIdHash hash of the payloadId string.
    /// @param pseudonymHash hash of the userPseudonym string.
    /// @return payloadAddress address of the attested payload.
    function payloadIdHashToPseudonymHashToPayloadAddress(bytes32 payloadIdHash, bytes32 pseudonymHash) external view returns (address payloadAddress);
}
