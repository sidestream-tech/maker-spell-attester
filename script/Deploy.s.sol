// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

import { Script } from "forge-std/Script.sol";
import { Helpers } from "script/Helpers.s.sol";
import { DeployAll, DeployParams } from "script/dependencies/DeployAll.sol";

contract Deploy is Script {
    string private json;

    function setUp() public {
        json = Helpers.readInput();
    }

    function run() public {
        address easAttester = vm.parseJsonAddress(json, ".EAS_ATTESTER");
        address easRegistry = vm.parseJsonAddress(json, ".EAS_REGISTRY");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        DeployAll.deploy(DeployParams({
            easAttester: easAttester,
            easRegistry: easRegistry
        }));
        vm.stopBroadcast();
    }
}
