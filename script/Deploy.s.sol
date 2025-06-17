// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {Arcade} from "../src/Arcade.sol";
import {ShootPolicy} from "../src/ShootPolicy.sol";
import {GiveawayPolicy} from "../src/GiveawayPolicy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {console} from "forge-std/console.sol";

contract DeployScript is Script {
    function run() public {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        // Deploy the Arcade contract
        Arcade arcade = new Arcade();

        // Initialize the contract directly
        arcade.initialize(vm.envAddress("PROTOCOL_OWNER"), vm.envAddress("WETH_ADDRESS"), vm.envAddress("VERIFY_SIG"));

        // Deploy policies
        address shootPolicy = address(new ShootPolicy());
        address giveawayPolicy = address(new GiveawayPolicy());

        vm.stopBroadcast();

        console.log("Arcade:", address(arcade));
        console.log("ShootPolicy:", shootPolicy);
        console.log("GiveawayPolicy:", giveawayPolicy);
        console.log("Owner:", vm.envAddress("PROTOCOL_OWNER"));
    }
}
