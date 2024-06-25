import Contracts from '../components/Contracts';
import { DeployedContracts, getNamedSigners, isTenderly } from '../utils/Deploy';
import Logger from '../utils/Logger';
import '@nomiclabs/hardhat-ethers';
import '@typechain/hardhat';
import { getNamedAccounts } from 'hardhat';
import 'hardhat-deploy';

const main = async () => {
    if (!isTenderly()) {
        throw new Error('Invalid network');
    }

    const { usdcWhale } = await getNamedSigners();
    const { usdc } = await getNamedAccounts();

    const carbonController = await DeployedContracts.CarbonController.deployed();

    const usdcToken = await Contracts.ERC20.attach(usdc);
    const amount = 5000;

    Logger.log('Previous USDC balance', (await usdcToken.balanceOf(usdcWhale.address)).toString());

    Logger.log();

    const res = await usdcToken.connect(usdcWhale).approve(carbonController.address, amount);

    Logger.log('Transaction Hash', res.hash);
    Logger.log();

    Logger.log('Current USDC balance', (await usdcToken.balanceOf(usdcWhale.address)).toString());
    Logger.log();
};

main()
    .then(() => process.exit(0))
    .catch((error) => {
        Logger.error(error);
        process.exit(1);
    });
