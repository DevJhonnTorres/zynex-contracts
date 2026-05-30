// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/MockUSDT.sol";
import "../src/DisputeModule.sol";
import "../src/EscrowFactory.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);

        address treasury = vm.envOr("TREASURY_ADDRESS", deployer);
        address arbitro  = vm.envOr("ARBITRO_ADDRESS",  deployer);
        address agente   = vm.envOr("AGENT_ADDRESS",    deployer);
        uint256 feeBps   = vm.envOr("FEE_BPS", uint256(500));

        vm.startBroadcast(deployerKey);

        MockUSDT usdt = new MockUSDT();
        console.log("MockUSDT:      ", address(usdt));

        DisputeModule dm = new DisputeModule(deployer, arbitro);
        console.log("DisputeModule: ", address(dm));

        EscrowFactory factory = new EscrowFactory(
            deployer, address(usdt), address(dm), treasury, feeBps
        );
        console.log("EscrowFactory: ", address(factory));

        factory.setAgentePrincipal(agente);
        console.log("Agente:        ", agente);

        usdt.mint(deployer, 10_000e6);
        console.log("USDT mint:      10000 USDT al deployer para testing");

        vm.stopBroadcast();

        console.log("\n=== COPIAR A deployments/base-sepolia.json ===");
        console.log("MockUSDT:     ", address(usdt));
        console.log("DisputeModule:", address(dm));
        console.log("EscrowFactory:", address(factory));
    }
}
