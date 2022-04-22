require("hardhat-gas-reporter");
require('hardhat-contract-sizer');
require("solidity-coverage");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");
require("dotenv").config();
// const web3 = require('web3');

//const dotenv = require('dotenv').config()
//npx hardhat run scripts/deploy.js --network rinkeby
//npx hardhat run scripts/deploy.js --network harmony_testnet
//npx hardhat run scripts/deploy.js --network harmony_mainnet

//Tellor Address(flex)
//Token -bridged TRB
//owner- multis wallet
//fee - 20 = 2%

var feeAmount = 20
//mumbai
// var tellorAddress = '0x41b66dd93b03e89D29114a7613A6f9f0d4F40178'
// var ownerAddress = '0x80fc34a2f9FfE86F41580F47368289C402DEc660'
// var bridgedTrb = '0x45cAF1aae42BA5565EC92362896cc8e0d55a2126'

//polygon
// var tellorAddress = '0xFd45Ae72E81Adaaf01cC61c8bCe016b7060DD537'
// var ownerAddress = '0x3F0C1eB3FA7fCe2b0932d6d4D9E03b5481F3f0A7'
// var bridgedTrb = '0xE3322702BEdaaEd36CdDAb233360B939775ae5f1'

//Arbitrum- Rinkeby
//npx hardhat run scripts/deploy.js --network arbitrum_testnet
// var tellorAddress = '0x8D1F54d8975124988eF65302FE487D83868B7ad7'
// var ownerAddress = '0x73B6715D9289bdfE5e758bB7ace782Cc7C933cfC'
// var bridgedTrb = '0xa800d52F5E72b918f8E09D5439beBEBf09ea2f74'

//Arbitrum- Rinkeby
//npx hardhat run scripts/deploy.js --network arbitrum_testnet
// var tellorAddress = ''
// var ownerAddress = ''
// var bridgedTrb = ''

//harmony testnet
// var tellorAddress = '0xcc12c7d111879526a63bdd59136cc969977daab2'
// var ownerAddress = '0xb69273AD994835b851ae3aA1F04685559f1297Ee'
// var bridgedTrb = '0x9ff6799d07cbc824ec16cf5fe7bdc6798849e9cc'

//harmony 
var tellorAddress = '0xb32e05DF1f11B1f0E1DE2A35F4D99393EB86FF8B'
var ownerAddress = '0x73B6715D9289bdfE5e758bB7ace782Cc7C933cfC'
var bridgedTrb = '0xd4b28ecb7b765C89F1e67dE3359d09A3520f794E'

// 0xb32e05DF1f11B1f0E1DE2A35F4D99393EB86FF8B,0xd4b28ecb7b765C89F1e67dE3359d09A3520f794E,0x73B6715D9289bdfE5e758bB7ace782Cc7C933cfC,20

async function deployAutopay(_network, _pk, _nodeURL, tellorAdd, ownerAdd, feeAmt) {
    console.log("deploy autopay")
    await run("compile")

    var net = _network

    ///////////////Connect to the network
    let privateKey = _pk;
    var provider = new ethers.providers.JsonRpcProvider(_nodeURL)
    let wallet = new ethers.Wallet(privateKey, provider)

    /////////// Deploy Polygon governance
    console.log("deploy autopay")

    /////////////PolygonGovernance
    console.log("Starting deployment for Autopay contract...")
    const Autopay = await ethers.getContractFactory("contracts/Autopay.sol:Autopay", wallet)
    const autopaywithsigner = await Autopay.connect(wallet)
    const autopay = await autopaywithsigner.deploy(tellorAdd,bridgedTrb, ownerAdd, feeAmt)
    await autopay.deployed();

    if (net == "mainnet"){
        console.log("Autopay contract deployed to:", "https://etherscan.io/address/" + autopay.address);
        console.log("    transaction hash:", "https://etherscan.io/tx/" + autopay.deployTransaction.hash);
    } else if (net == "rinkeby") {
        console.log("Autopay contract deployed to:", "https://rinkeby.etherscan.io/address/" + autopay.address);
        console.log("    transaction hash:", "https://rinkeby.etherscan.io/tx/" + autopay.deployTransaction.hash);
    } else if (net == "bsc_testnet") {
        console.log("Autopay contract deployed to:", "https://testnet.bscscan.com/address/" + autopay.address);
        console.log("    transaction hash:", "https://testnet.bscscan.com/tx/" + autopay.deployTransaction.hash);
    } else if (net == "bsc") {
        console.log("Autopay contract deployed to:", "https://bscscan.com/address/" + autopay.address);
        console.log("    transaction hash:", "https://bscscan.com/tx/" + autopay.deployTransaction.hash);
    } else if (net == "polygon") {
        console.log("Autopay contract deployed to:", "https://polygonscan.com/address/" + autopay.address);
        console.log("    transaction hash:", "https://polygonscan.com/tx/" + autopay.deployTransaction.hash);
    } else if (net == "polygon_testnet") {
        console.log("Autopay contract deployed to:", "https://mumbai.polygonscan.com/address/" + autopay.address);
        console.log("    transaction hash:", "https://mumbai.polygonscan.com/tx/" + autopay.deployTransaction.hash);
    } else if (net == "arbitrum_testnet"){
        console.log("Autopay contract deployed to:","https://rinkeby-explorer.arbitrum.io/#/"+ autopay.address)
        console.log("    transaction hash:", "https://rinkeby-explorer.arbitrum.io/#/tx/" + autopay.deployTransaction.hash);
    } else if (net == "harmony_testnet"){
        console.log("Autopay contract deployed to:","https://explorer.pops.one/address/"+ autopay.address)
        console.log("    transaction hash:", "https://explorer.pops.one/txt/" + autopay.deployTransaction.hash);
    } else if (net == "harmony_mainnet"){
        console.log("Autopay contract deployed to:","https://explorer.harmony.one/address/"+ autopay.address)
        console.log("    transaction hash:", "https://explorer.harmony.one/txt/" + autopay.deployTransaction.hash);
    } else if (net == "xdaiSokol"){ //https://blockscout.com/poa/xdai/address/
      console.log("Autopay contract deployed to:","https://blockscout.com/poa/sokol/address/"+ autopay.address)
      console.log("    transaction hash:", "https://blockscout.com/poa/sokol/tx/" + autopay.deployTransaction.hash);
    } else if (net == "xdai"){ //https://blockscout.com/poa/xdai/address/
      console.log("Autopay contract deployed to:","https://blockscout.com/xdai/mainnet/address/"+ autopay.address)
      console.log("    transaction hash:", "https://blockscout.com/xdai/mainnet/tx/" + autopay.deployTransaction.hash);
    } else if (net == "arbitrum_testnet"){ //https://blockscout.com/poa/xdai/address/
        console.log("Autopay contract deployed to:","https://testnet.arbiscan.io/address/"+ autopay.address)
        console.log("    transaction hash:", "https://testnet.arbiscan.io/tx/" + autopay.deployTransaction.hash);
    } else if (net == "arbitrum"){ //https://blockscout.com/poa/xdai/address/
        console.log("Autopay contract deployed to:","https://arbiscan.io/address/"+ autopay.address)
        console.log("    transaction hash:", "https://arbiscan.io/tx/" + autopay.deployTransaction.hash);
    } else {
        console.log("Please add network explorer details")
    }


    // Wait for few confirmed transactions.
    // Otherwise the etherscan api doesn't find the deployed contract.
    console.log('waiting for TellorFlex tx confirmation...');
    await autopay.deployTransaction.wait(7)

    console.log('submitting TellorFlex contract for verification...');

    await run("verify:verify",
        {
            address: autopay.address,
            constructorArguments: [tellorAdd, bridgedTrb, ownerAdd, feeAmt]
        },
    )

    console.log("Autopay contract verified")

}

deployAutopay("polygon", process.env.PRIVATE_KEY, process.env.NODE_URL_MATIC, tellorAddress, ownerAddress, feeAmount)
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });

// deployAutopay("harmony_testnet", process.env.TESTNET_PK, process.env.NODE_URL_HARMONY_TESTNET, tellorAddress, ownerAddress, feeAmount)
//     .then(() => process.exit(0))
//     .catch(error => {
//         console.error(error);
//         process.exit(1);
//     });

// deployAutopay("harmony_mainnet", process.env.TESTNET_PK, process.env.NODE_URL_HARMONY_MAINNET, tellorAddress, ownerAddress, feeAmount)
//     .then(() => process.exit(0))
//     .catch(error => {
//         console.error(error);
//         process.exit(1);
//     });

