// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {Arcade} from "../src/Arcade.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {console} from "forge-std/console.sol";

contract DeployScript is Script {
    function prepare() public {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        Arcade arcade = new Arcade(vm.envAddress("WETH_ADDRESS"), vm.envAddress("VERIFY_SIG"));
        vm.stopBroadcast();
        console.log("Arcade:", address(arcade));
    }

    function run(address payable arcade) public {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        // Deploy the Arcade contract
        Arcade a = Arcade(
            payable(
                new ERC1967Proxy(
                    arcade,
                    abi.encodeWithSelector(
                        Arcade.initialize.selector,
                        vm.envAddress("PROTOCOL_OWNER")
                    )
                )
            )
        );

        vm.stopBroadcast();

        console.log("Arcade:", address(a));
        console.log("Owner:", vm.envAddress("PROTOCOL_OWNER"));
    }
}
