// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

interface SpellAttesterAbstract {
    /// @notice Get schemaId using internal schema name.
    /// @param schemaName Internal schema name (e.g.: 'identity', 'spell', 'deployment').
    /// @return schemaId Relevant EAS schema UID.
    function schemaNameToSchemaId(bytes32 schemaName) external view returns (bytes32 schemaId);

    /// @notice Get schema resolver address using internal schema name.
    /// @param schemaName Internal schema name (e.g.: 'identity', 'spell', 'deployment').
    /// @return resolver Address of the relevant resolver contract.
    function schemaNameToResolver(bytes32 schemaName) external view returns (address resolver);

    /// @notice Check whether address have admin rights.
    /// @param usr Address to be checked.
    /// @return result Result of the check: 1 = is admin, 0 = not admin.
    function wards(address usr) external view returns (uint256 result);
}
