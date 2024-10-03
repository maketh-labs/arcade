// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Arcade} from "../src/Arcade.sol";
import {MulRewardPolicy} from "../src/MulRewardPolicy.sol";
import {GiveawayPolicy} from "../src/GiveawayPolicy.sol";
import {console} from "forge-std/console.sol";

contract DeployScript is Script {
    function run() public {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address arcade = address(new Arcade(vm.envAddress("PROTOCOL_OWNER"), vm.envAddress("WETH_ADDRESS")));
        address mulRewardPolicy = address(new MulRewardPolicy());
        address giveawayPolicy = address(new GiveawayPolicy());
        vm.stopBroadcast();

        console.log("Arcade:", arcade);
        console.log("MulRewardPolicy:", mulRewardPolicy);
        console.log("GiveawayPolicy:", giveawayPolicy);
        console.log("Owner:", vm.envAddress("PROTOCOL_OWNER"));
    }
}
