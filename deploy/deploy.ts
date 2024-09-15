import { Wallet } from "zksync-ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Deployer } from "@matterlabs/hardhat-zksync";
import { vars } from "hardhat/config";

export default async function (hre: HardhatRuntimeEnvironment) {
  console.log(`Running deploy script`);

  // Initialize the wallet using your private key.
  const wallet = new Wallet(vars.get("DEPLOYER_PRIVATE_KEY"));

  // Create deployer object and load the artifact of the contract we want to deploy.
  const deployer = new Deployer(hre, wallet);
  // Load contract
  const arcadeArtifact = await deployer.loadArtifact("Arcade");
  const mulRewardPolicyArtifact = await deployer.loadArtifact("MulRewardPolicy");
  const giveawayPolicyArtifact = await deployer.loadArtifact("GiveawayPolicy");
  const arcadeContract = await deployer.deploy(arcadeArtifact, [vars.get("PROTOCOL_OWNER")]);
  const mulRewardPolicyContract = await deployer.deploy(mulRewardPolicyArtifact);
  const giveawayPolicyContract = await deployer.deploy(giveawayPolicyArtifact);

  console.log(`${arcadeArtifact.contractName}: ${await arcadeContract.getAddress()}`);
  console.log(`${mulRewardPolicyArtifact.contractName}: ${await mulRewardPolicyContract.getAddress()}`);
  console.log(`${giveawayPolicyArtifact.contractName}: ${await giveawayPolicyContract.getAddress()}`);
}
