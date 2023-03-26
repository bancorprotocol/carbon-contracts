import { utils } from 'ethers';

const { id } = utils;

export const Roles = {
    Upgradeable: {
        ROLE_ADMIN: id('ROLE_ADMIN')
    },

    CarbonController: {
        ROLE_EMERGENCY_STOPPER: id('ROLE_EMERGENCY_STOPPER'),
        ROLE_FEES_MANAGER: id('ROLE_FEES_MANAGER')
    }
};

export const RoleIds = Object.values(Roles)
    .map((contractRoles) => Object.values(contractRoles))
    .flat(1);
