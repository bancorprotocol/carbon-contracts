import { utils } from 'ethers';

const { id } = utils;

export const Roles = {
    Upgradeable: {
        ROLE_ADMIN: id('ROLE_ADMIN')
    },

    CarbonController: {
        ROLE_FEES_MANAGER: id('ROLE_FEES_MANAGER')
    },

    Vault: {
        ROLE_ASSET_MANAGER: id('ROLE_ASSET_MANAGER')
    },

    Voucher: {
        ROLE_MINTER: id('ROLE_MINTER')
    }
};

export const RoleIds = Object.values(Roles)
    .map((contractRoles) => Object.values(contractRoles))
    .flat(1);
