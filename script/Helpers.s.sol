// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

import { VmSafe } from "forge-std/Vm.sol";

library Helpers {
    VmSafe private constant vm = VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));

    function readInput() internal view returns (string memory) {
        string memory inputDir = string.concat(vm.projectRoot(), "/script/input/");
        string memory chainDir = string.concat(vm.toString(block.chainid), "/");
        string memory file = string.concat("input.json");
        return vm.readFile(string.concat(inputDir, chainDir, file));
    }
}
