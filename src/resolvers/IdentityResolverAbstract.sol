// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

interface IdentityResolverAbstract {
    /// @notice Get userPseudonym hash from the previously attested and non-revoked Identity address.
    /// @param userAddress Address of the previously attested user.
    /// @return userPseudonymHash Hash of the associated userPseudonym.
    function addressToPseudonymHash(address userAddress) external view returns (bytes32 userPseudonymHash);

    /// @notice Get teamName hash from a previously attested and non-revoked Identity pseudonym.
    /// @param userPseudonymHash Hash of the previously attested userPseudonym.
    /// @return userTeamHash Hash of the associated teamName.
    function pseudonymHashToTeamHash(bytes32 userPseudonymHash) external view returns (bytes32 userTeamHash);
}
