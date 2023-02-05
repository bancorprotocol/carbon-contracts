export const testCaseTemplateBySourceAmount = {
    sourceSymbol: 'ETH',
    targetSymbol: 'USDC',
    byTargetAmount: false,
    strategies: [
        {
            orders: [
                {
                    token: 'ETH',
                    liquidity: '123000000000000000000',
                    lowestRate: '950000000',
                    highestRate: '1050000000',
                    marginalRate: '1000000000',
                    expected: {
                        liquidity: '124230000000000000000',
                        lowestRate: '949999999.999999945717',
                        highestRate: '1049999999.999988007042',
                        marginalRate: '1000506475.423472343294'
                    }
                },
                {
                    token: 'USDC',
                    liquidity: '123000000000',
                    lowestRate: '0.00000000095',
                    highestRate: '0.00000000105',
                    marginalRate: '0.000000001',
                    expected: {
                        liquidity: '121770325691',
                        lowestRate: '0.00000000095',
                        highestRate: '0.00000000105',
                        marginalRate: '0.000000000999'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'ETH',
                    liquidity: '456000000000000000000',
                    lowestRate: '950000000',
                    highestRate: '1050000000',
                    marginalRate: '1000000000',
                    expected: {
                        liquidity: '460560000000000000000',
                        lowestRate: '949999999.999999945717',
                        highestRate: '1049999999.999988007042',
                        marginalRate: '1000506475.423472343294'
                    }
                },
                {
                    token: 'USDC',
                    liquidity: '456000000000',
                    lowestRate: '0.00000000095',
                    highestRate: '0.00000000105',
                    marginalRate: '0.000000001',
                    expected: {
                        liquidity: '451441207438',
                        lowestRate: '0.00000000095',
                        highestRate: '0.00000000105',
                        marginalRate: '0.000000000999'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'ETH',
                    liquidity: '789000000000000000000',
                    lowestRate: '950000000',
                    highestRate: '1050000000',
                    marginalRate: '1000000000',
                    expected: {
                        liquidity: '796890000000000000000',
                        lowestRate: '949999999.999999945717',
                        highestRate: '1049999999.999988007042',
                        marginalRate: '1000506475.423472343294'
                    }
                },
                {
                    token: 'USDC',
                    liquidity: '789000000000',
                    lowestRate: '0.00000000095',
                    highestRate: '0.00000000105',
                    marginalRate: '0.000000001',
                    expected: {
                        liquidity: '781112089185',
                        lowestRate: '0.00000000095',
                        highestRate: '0.00000000105',
                        marginalRate: '0.000000000999'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'ETH',
                    liquidity: '123000000000000000000',
                    lowestRate: '760000000',
                    highestRate: '840000000',
                    marginalRate: '800000000',
                    expected: {
                        liquidity: '124230000000000000000',
                        lowestRate: '759999999.999997069614',
                        highestRate: '839999999.999999155284',
                        marginalRate: '800405180.338775602121'
                    }
                },
                {
                    token: 'USDC',
                    liquidity: '123000000000',
                    lowestRate: '0.000000001187',
                    highestRate: '0.000000001312',
                    marginalRate: '0.00000000125',
                    expected: {
                        liquidity: '121462991039',
                        lowestRate: '0.000000001187',
                        highestRate: '0.000000001312',
                        marginalRate: '0.000000001249'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'ETH',
                    liquidity: '456000000000000000000',
                    lowestRate: '760000000',
                    highestRate: '840000000',
                    marginalRate: '800000000',
                    expected: {
                        liquidity: '460560000000000000000',
                        lowestRate: '759999999.999997069614',
                        highestRate: '839999999.999999155284',
                        marginalRate: '800405180.338775602121'
                    }
                },
                {
                    token: 'USDC',
                    liquidity: '456000000000',
                    lowestRate: '0.000000001187',
                    highestRate: '0.000000001312',
                    marginalRate: '0.00000000125',
                    expected: {
                        liquidity: '450301820435',
                        lowestRate: '0.000000001187',
                        highestRate: '0.000000001312',
                        marginalRate: '0.000000001249'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'ETH',
                    liquidity: '789000000000000000000',
                    lowestRate: '760000000',
                    highestRate: '840000000',
                    marginalRate: '800000000',
                    expected: {
                        liquidity: '796890000000000000000',
                        lowestRate: '759999999.999997069614',
                        highestRate: '839999999.999999155284',
                        marginalRate: '800405180.338775602121'
                    }
                },
                {
                    token: 'USDC',
                    liquidity: '789000000000',
                    lowestRate: '0.000000001187',
                    highestRate: '0.000000001312',
                    marginalRate: '0.00000000125',
                    expected: {
                        liquidity: '779140649831',
                        lowestRate: '0.000000001187',
                        highestRate: '0.000000001312',
                        marginalRate: '0.000000001249'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'ETH',
                    liquidity: '123000000000000000000',
                    lowestRate: '633333333.333333333333',
                    highestRate: '700000000',
                    marginalRate: '666666666.666666666667',
                    expected: {
                        liquidity: '124230000000000000000',
                        lowestRate: '633333333.333321659174',
                        highestRate: '699999999.99999512983',
                        marginalRate: '667004316.948982523836'
                    }
                },
                {
                    token: 'USDC',
                    liquidity: '123000000000',
                    lowestRate: '0.000000001425',
                    highestRate: '0.000000001575',
                    marginalRate: '0.0000000015',
                    expected: {
                        liquidity: '121155708657',
                        lowestRate: '0.000000001425',
                        highestRate: '0.000000001575',
                        marginalRate: '0.000000001499'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'ETH',
                    liquidity: '456000000000000000000',
                    lowestRate: '633333333.333333333333',
                    highestRate: '700000000',
                    marginalRate: '666666666.666666666667',
                    expected: {
                        liquidity: '460560000000000000000',
                        lowestRate: '633333333.333321659174',
                        highestRate: '699999999.99999512983',
                        marginalRate: '667004316.948982523836'
                    }
                },
                {
                    token: 'USDC',
                    liquidity: '456000000000',
                    lowestRate: '0.000000001425',
                    highestRate: '0.000000001575',
                    marginalRate: '0.0000000015',
                    expected: {
                        liquidity: '449162627216',
                        lowestRate: '0.000000001425',
                        highestRate: '0.000000001575',
                        marginalRate: '0.000000001499'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'ETH',
                    liquidity: '789000000000000000000',
                    lowestRate: '633333333.333333333333',
                    highestRate: '700000000',
                    marginalRate: '666666666.666666666667',
                    expected: {
                        liquidity: '796890000000000000000',
                        lowestRate: '633333333.333321659174',
                        highestRate: '699999999.99999512983',
                        marginalRate: '667004316.948982523836'
                    }
                },
                {
                    token: 'USDC',
                    liquidity: '789000000000',
                    lowestRate: '0.000000001425',
                    highestRate: '0.000000001575',
                    marginalRate: '0.0000000015',
                    expected: {
                        liquidity: '777169545774',
                        lowestRate: '0.000000001425',
                        highestRate: '0.000000001575',
                        marginalRate: '0.000000001499'
                    }
                }
            ]
        }
    ],
    tradeActions: [
        {
            strategyId: '1',
            amount: '1230000000000000000'
        },
        {
            strategyId: '2',
            amount: '4560000000000000000'
        },
        {
            strategyId: '3',
            amount: '7890000000000000000'
        },
        {
            strategyId: '4',
            amount: '1230000000000000000'
        },
        {
            strategyId: '5',
            amount: '4560000000000000000'
        },
        {
            strategyId: '6',
            amount: '7890000000000000000'
        },
        {
            strategyId: '7',
            amount: '1230000000000000000'
        },
        {
            strategyId: '8',
            amount: '4560000000000000000'
        },
        {
            strategyId: '9',
            amount: '7890000000000000000'
        }
    ],
    sourceAmount: '41040000000000000000',
    targetAmount: '51283034734'
};

export const testCaseTemplateByTargetAmount = {
    sourceSymbol: 'USDC',
    targetSymbol: 'ETH',
    byTargetAmount: true,
    strategies: [
        {
            orders: [
                {
                    token: 'USDC',
                    liquidity: '123000000000',
                    lowestRate: '0.00000000095',
                    highestRate: '0.00000000105',
                    marginalRate: '0.000000001',
                    expected: {
                        liquidity: '127924988140',
                        lowestRate: '0.00000000095',
                        highestRate: '0.00000000105',
                        marginalRate: '0.000000001002'
                    }
                },
                {
                    token: 'ETH',
                    liquidity: '123000000000000000000',
                    lowestRate: '950000000',
                    highestRate: '1050000000',
                    marginalRate: '1000000000',
                    expected: {
                        liquidity: '118080000000000000000',
                        lowestRate: '949999999.999999945717',
                        highestRate: '1049999999.999988007042',
                        marginalRate: '997975380.56811997751'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'USDC',
                    liquidity: '456000000000',
                    lowestRate: '0.00000000095',
                    highestRate: '0.00000000105',
                    marginalRate: '0.000000001',
                    expected: {
                        liquidity: '474258492615',
                        lowestRate: '0.00000000095',
                        highestRate: '0.00000000105',
                        marginalRate: '0.000000001002'
                    }
                },
                {
                    token: 'ETH',
                    liquidity: '456000000000000000000',
                    lowestRate: '950000000',
                    highestRate: '1050000000',
                    marginalRate: '1000000000',
                    expected: {
                        liquidity: '437760000000000000000',
                        lowestRate: '949999999.999999945717',
                        highestRate: '1049999999.999988007042',
                        marginalRate: '997975380.56811997751'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'USDC',
                    liquidity: '789000000000',
                    lowestRate: '0.00000000095',
                    highestRate: '0.00000000105',
                    marginalRate: '0.000000001',
                    expected: {
                        liquidity: '820591997090',
                        lowestRate: '0.00000000095',
                        highestRate: '0.00000000105',
                        marginalRate: '0.000000001002'
                    }
                },
                {
                    token: 'ETH',
                    liquidity: '789000000000000000000',
                    lowestRate: '950000000',
                    highestRate: '1050000000',
                    marginalRate: '1000000000',
                    expected: {
                        liquidity: '757440000000000000000',
                        lowestRate: '949999999.999999945717',
                        highestRate: '1049999999.999988007042',
                        marginalRate: '997975380.56811997751'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'USDC',
                    liquidity: '123000000000',
                    lowestRate: '0.000000001187',
                    highestRate: '0.000000001312',
                    marginalRate: '0.00000000125',
                    expected: {
                        liquidity: '129156235175',
                        lowestRate: '0.000000001187',
                        highestRate: '0.000000001312',
                        marginalRate: '0.000000001253'
                    }
                },
                {
                    token: 'ETH',
                    liquidity: '123000000000000000000',
                    lowestRate: '760000000',
                    highestRate: '840000000',
                    marginalRate: '800000000',
                    expected: {
                        liquidity: '118080000000000000000',
                        lowestRate: '759999999.999997069614',
                        highestRate: '839999999.999999155284',
                        marginalRate: '798380304.454493678246'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'USDC',
                    liquidity: '456000000000',
                    lowestRate: '0.000000001187',
                    highestRate: '0.000000001312',
                    marginalRate: '0.00000000125',
                    expected: {
                        liquidity: '478823115768',
                        lowestRate: '0.000000001187',
                        highestRate: '0.000000001312',
                        marginalRate: '0.000000001253'
                    }
                },
                {
                    token: 'ETH',
                    liquidity: '456000000000000000000',
                    lowestRate: '760000000',
                    highestRate: '840000000',
                    marginalRate: '800000000',
                    expected: {
                        liquidity: '437760000000000000000',
                        lowestRate: '759999999.999997069614',
                        highestRate: '839999999.999999155284',
                        marginalRate: '798380304.454493678245'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'USDC',
                    liquidity: '789000000000',
                    lowestRate: '0.000000001187',
                    highestRate: '0.000000001312',
                    marginalRate: '0.00000000125',
                    expected: {
                        liquidity: '828489996362',
                        lowestRate: '0.000000001187',
                        highestRate: '0.000000001312',
                        marginalRate: '0.000000001253'
                    }
                },
                {
                    token: 'ETH',
                    liquidity: '789000000000000000000',
                    lowestRate: '760000000',
                    highestRate: '840000000',
                    marginalRate: '800000000',
                    expected: {
                        liquidity: '757440000000000000000',
                        lowestRate: '759999999.999997069614',
                        highestRate: '839999999.999999155284',
                        marginalRate: '798380304.454493678245'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'USDC',
                    liquidity: '123000000000',
                    lowestRate: '0.000000001425',
                    highestRate: '0.000000001575',
                    marginalRate: '0.0000000015',
                    expected: {
                        liquidity: '130387482210',
                        lowestRate: '0.000000001425',
                        highestRate: '0.000000001575',
                        marginalRate: '0.000000001505'
                    }
                },
                {
                    token: 'ETH',
                    liquidity: '123000000000000000000',
                    lowestRate: '633333333.333333333333',
                    highestRate: '700000000',
                    marginalRate: '666666666.666666666667',
                    expected: {
                        liquidity: '118080000000000000000',
                        lowestRate: '633333333.333321659174',
                        highestRate: '699999999.99999512983',
                        marginalRate: '665316920.378746974045'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'USDC',
                    liquidity: '456000000000',
                    lowestRate: '0.000000001425',
                    highestRate: '0.000000001575',
                    marginalRate: '0.0000000015',
                    expected: {
                        liquidity: '483387738922',
                        lowestRate: '0.000000001425',
                        highestRate: '0.000000001575',
                        marginalRate: '0.000000001505'
                    }
                },
                {
                    token: 'ETH',
                    liquidity: '456000000000000000000',
                    lowestRate: '633333333.333333333333',
                    highestRate: '700000000',
                    marginalRate: '666666666.666666666667',
                    expected: {
                        liquidity: '437760000000000000000',
                        lowestRate: '633333333.333321659174',
                        highestRate: '699999999.99999512983',
                        marginalRate: '665316920.378746974045'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'USDC',
                    liquidity: '789000000000',
                    lowestRate: '0.000000001425',
                    highestRate: '0.000000001575',
                    marginalRate: '0.0000000015',
                    expected: {
                        liquidity: '836387995634',
                        lowestRate: '0.000000001425',
                        highestRate: '0.000000001575',
                        marginalRate: '0.000000001505'
                    }
                },
                {
                    token: 'ETH',
                    liquidity: '789000000000000000000',
                    lowestRate: '633333333.333333333333',
                    highestRate: '700000000',
                    marginalRate: '666666666.666666666667',
                    expected: {
                        liquidity: '757440000000000000000',
                        lowestRate: '633333333.333321659174',
                        highestRate: '699999999.99999512983',
                        marginalRate: '665316920.378746974045'
                    }
                }
            ]
        }
    ],
    tradeActions: [
        {
            strategyId: '1',
            amount: '4920000000000000000'
        },
        {
            strategyId: '2',
            amount: '18240000000000000000'
        },
        {
            strategyId: '3',
            amount: '31560000000000000000'
        },
        {
            strategyId: '4',
            amount: '4920000000000000000'
        },
        {
            strategyId: '5',
            amount: '18240000000000000000'
        },
        {
            strategyId: '6',
            amount: '31560000000000000000'
        },
        {
            strategyId: '7',
            amount: '4920000000000000000'
        },
        {
            strategyId: '8',
            amount: '18240000000000000000'
        },
        {
            strategyId: '9',
            amount: '31560000000000000000'
        }
    ],
    sourceAmount: '205408041916',
    targetAmount: '164160000000000000000'
};

export const testCaseTemplateBySourceAmountEqualHighestAndMarginalRate = {
    sourceSymbol: 'TKN0',
    targetSymbol: 'TKN1',
    byTargetAmount: false,
    strategies: [
        {
            orders: [
                {
                    token: 'TKN0',
                    liquidity: '871192',
                    lowestRate: '8',
                    highestRate: '9',
                    marginalRate: '9',
                    expected: {
                        liquidity: '872192',
                        lowestRate: '7.999999998809',
                        highestRate: '9',
                        marginalRate: '9'
                    }
                },
                {
                    token: 'TKN1',
                    liquidity: '2948985',
                    lowestRate: '1',
                    highestRate: '2',
                    marginalRate: '1.994477228601',
                    expected: {
                        liquidity: '2946991',
                        lowestRate: '1',
                        highestRate: '1.999999999373',
                        marginalRate: '1.993690348171'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'TKN0',
                    liquidity: '999648',
                    lowestRate: '9',
                    highestRate: '10',
                    marginalRate: '10',
                    expected: {
                        liquidity: '1001648',
                        lowestRate: '9',
                        highestRate: '9.999999999566',
                        marginalRate: '9.999999999566'
                    }
                },
                {
                    token: 'TKN1',
                    liquidity: '3914680',
                    lowestRate: '2',
                    highestRate: '3',
                    marginalRate: '2.989993142553',
                    expected: {
                        liquidity: '3908702',
                        lowestRate: '1.999999999373',
                        highestRate: '2.999999999582',
                        marginalRate: '2.988330385468'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'TKN0',
                    liquidity: '1126104',
                    lowestRate: '10',
                    highestRate: '11',
                    marginalRate: '11',
                    expected: {
                        liquidity: '1129104',
                        lowestRate: '9.999999999566',
                        highestRate: '10.999999998951',
                        marginalRate: '10.999999998951'
                    }
                },
                {
                    token: 'TKN1',
                    liquidity: '4878370',
                    lowestRate: '3',
                    highestRate: '4',
                    marginalRate: '3.987009932433',
                    expected: {
                        liquidity: '4866413',
                        lowestRate: '2.999999999582',
                        highestRate: '4',
                        marginalRate: '3.98441943632'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'TKN0',
                    liquidity: '1250560',
                    lowestRate: '11',
                    highestRate: '12',
                    marginalRate: '12',
                    expected: {
                        liquidity: '1254560',
                        lowestRate: '10.999999998951',
                        highestRate: '11.99999999994',
                        marginalRate: '11.99999999994'
                    }
                },
                {
                    token: 'TKN1',
                    liquidity: '5846040',
                    lowestRate: '4',
                    highestRate: '5',
                    marginalRate: '4.985778459056',
                    expected: {
                        liquidity: '5826104',
                        lowestRate: '4',
                        highestRate: '4.999999998965',
                        marginalRate: '4.982232636644'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'TKN0',
                    liquidity: '1373016',
                    lowestRate: '12',
                    highestRate: '13',
                    marginalRate: '13',
                    expected: {
                        liquidity: '1378016',
                        lowestRate: '11.99999999994',
                        highestRate: '12.999999999716',
                        marginalRate: '12.999999999716'
                    }
                },
                {
                    token: 'TKN1',
                    liquidity: '6823681',
                    lowestRate: '5',
                    highestRate: '6',
                    marginalRate: '5.986412468094',
                    expected: {
                        liquidity: '6793761',
                        lowestRate: '4.999999998965',
                        highestRate: '5.999999999839',
                        marginalRate: '5.981893609194'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'TKN0',
                    liquidity: '1493472',
                    lowestRate: '13',
                    highestRate: '14',
                    marginalRate: '14',
                    expected: {
                        liquidity: '1499472',
                        lowestRate: '12.999999999716',
                        highestRate: '13.999999999946',
                        marginalRate: '13.999999999946'
                    }
                },
                {
                    token: 'TKN1',
                    liquidity: '7817299',
                    lowestRate: '6',
                    highestRate: '7',
                    marginalRate: '6.988972398395',
                    expected: {
                        liquidity: '7775382',
                        lowestRate: '5.999999999839',
                        highestRate: '6.999999999542',
                        marginalRate: '6.983468484726'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'TKN0',
                    liquidity: '1611928',
                    lowestRate: '14',
                    highestRate: '15',
                    marginalRate: '15',
                    expected: {
                        liquidity: '1618928',
                        lowestRate: '13.999999999946',
                        highestRate: '14.999999998353',
                        marginalRate: '14.999999998353'
                    }
                },
                {
                    token: 'TKN1',
                    liquidity: '8832909',
                    lowestRate: '7',
                    highestRate: '8',
                    marginalRate: '7.993493761264',
                    expected: {
                        liquidity: '8776978',
                        lowestRate: '6.999999999542',
                        highestRate: '7.999999998809',
                        marginalRate: '7.986995626162'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'TKN0',
                    liquidity: '1728384',
                    lowestRate: '15',
                    highestRate: '16',
                    marginalRate: '16',
                    expected: {
                        liquidity: '1736384',
                        lowestRate: '14.999999998353',
                        highestRate: '16',
                        marginalRate: '16'
                    }
                },
                {
                    token: 'TKN1',
                    liquidity: '9876540',
                    lowestRate: '8',
                    highestRate: '9',
                    marginalRate: '9',
                    expected: {
                        liquidity: '9804571',
                        lowestRate: '7.999999998809',
                        highestRate: '9',
                        marginalRate: '8.992500194206'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'TKN0',
                    liquidity: '1851840',
                    lowestRate: '16',
                    highestRate: '17',
                    marginalRate: '17',
                    expected: {
                        liquidity: '1851840',
                        lowestRate: '16',
                        highestRate: '16.999999998116',
                        marginalRate: '16.999999998116'
                    }
                },
                {
                    token: 'TKN1',
                    liquidity: '10864194',
                    lowestRate: '9',
                    highestRate: '10',
                    marginalRate: '10',
                    expected: {
                        liquidity: '10864194',
                        lowestRate: '9',
                        highestRate: '9.999999999566',
                        marginalRate: '9.999999999566'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'TKN0',
                    liquidity: '1975296',
                    lowestRate: '17',
                    highestRate: '18',
                    marginalRate: '18',
                    expected: {
                        liquidity: '1975296',
                        lowestRate: '16.999999998116',
                        highestRate: '17.999999998308',
                        marginalRate: '17.999999998308'
                    }
                },
                {
                    token: 'TKN1',
                    liquidity: '11851848',
                    lowestRate: '10',
                    highestRate: '11',
                    marginalRate: '11',
                    expected: {
                        liquidity: '11851848',
                        lowestRate: '9.999999999566',
                        highestRate: '10.999999998951',
                        marginalRate: '10.999999998951'
                    }
                }
            ]
        }
    ],
    tradeActions: [
        {
            strategyId: '1',
            amount: '1000'
        },
        {
            strategyId: '2',
            amount: '2000'
        },
        {
            strategyId: '3',
            amount: '3000'
        },
        {
            strategyId: '4',
            amount: '4000'
        },
        {
            strategyId: '5',
            amount: '5000'
        },
        {
            strategyId: '6',
            amount: '6000'
        },
        {
            strategyId: '7',
            amount: '7000'
        },
        {
            strategyId: '8',
            amount: '8000'
        }
    ],
    sourceAmount: '36000',
    targetAmount: '239602'
};

export const testCaseTemplateByTargetAmountEqualHighestAndMarginalRate = {
    sourceSymbol: 'TKN0',
    targetSymbol: 'TKN1',
    byTargetAmount: true,
    strategies: [
        {
            orders: [
                {
                    token: 'TKN0',
                    liquidity: '228073',
                    lowestRate: '2',
                    highestRate: '2.250000000000',
                    marginalRate: '2.250000000000',
                    expected: {
                        liquidity: '230084',
                        lowestRate: '1.999999999373',
                        highestRate: '2.25',
                        marginalRate: '2.25'
                    }
                },
                {
                    token: 'TKN1',
                    liquidity: '734740',
                    lowestRate: '0.250000000000',
                    highestRate: '0.500000000000',
                    marginalRate: '0.497630376785',
                    expected: {
                        liquidity: '733740',
                        lowestRate: '0.25',
                        highestRate: '0.499999999679',
                        marginalRate: '0.497236377062'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'TKN0',
                    liquidity: '260267',
                    lowestRate: '2.250000000000',
                    highestRate: '2.500000000000',
                    marginalRate: '2.500000000000',
                    expected: {
                        liquidity: '262945',
                        lowestRate: '2.25',
                        highestRate: '2.499999999523',
                        marginalRate: '2.499999999523'
                    }
                },
                {
                    token: 'TKN1',
                    liquidity: '977654',
                    lowestRate: '0.500000000000',
                    highestRate: '0.750000000000',
                    marginalRate: '0.747215629964',
                    expected: {
                        liquidity: '975654',
                        lowestRate: '0.499999999679',
                        highestRate: '0.749999999694',
                        marginalRate: '0.746659377022'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'TKN0',
                    liquidity: '289788',
                    lowestRate: '2.500000000000',
                    highestRate: '2.750000000000',
                    marginalRate: '2.750000000000',
                    expected: {
                        liquidity: '292797',
                        lowestRate: '2.499999999523',
                        highestRate: '2.749999999352',
                        marginalRate: '2.749999999352'
                    }
                },
                {
                    token: 'TKN1',
                    liquidity: '1222567',
                    lowestRate: '0.750000000000',
                    highestRate: '1',
                    marginalRate: '0.997397227762',
                    expected: {
                        liquidity: '1219567',
                        lowestRate: '0.749999999694',
                        highestRate: '1',
                        marginalRate: '0.99674706464'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'TKN0',
                    liquidity: '318246',
                    lowestRate: '2.750000000000',
                    highestRate: '3',
                    marginalRate: '3',
                    expected: {
                        liquidity: '321453',
                        lowestRate: '2.749999999352',
                        highestRate: '2.999999999582',
                        marginalRate: '2.999999999582'
                    }
                },
                {
                    token: 'TKN1',
                    liquidity: '1469481',
                    lowestRate: '1',
                    highestRate: '1.250000000000',
                    marginalRate: '1.247863064004',
                    expected: {
                        liquidity: '1465481',
                        lowestRate: '1',
                        highestRate: '1.249999999741',
                        marginalRate: '1.247151158007'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'TKN0',
                    liquidity: '346173',
                    lowestRate: '3',
                    highestRate: '3.250000000000',
                    marginalRate: '3.250000000000',
                    expected: {
                        liquidity: '349511',
                        lowestRate: '2.999999999582',
                        highestRate: '3.249999999929',
                        marginalRate: '3.249999999929'
                    }
                },
                {
                    token: 'TKN1',
                    liquidity: '1718394',
                    lowestRate: '1.250000000000',
                    highestRate: '1.500000000000',
                    marginalRate: '1.498488068523',
                    expected: {
                        liquidity: '1713394',
                        lowestRate: '1.249999999741',
                        highestRate: '1.499999999675',
                        marginalRate: '1.497732388346'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'TKN0',
                    liquidity: '373797',
                    lowestRate: '3.250000000000',
                    highestRate: '3.500000000000',
                    marginalRate: '3.500000000000',
                    expected: {
                        liquidity: '377228',
                        lowestRate: '3.249999999929',
                        highestRate: '3.499999999551',
                        marginalRate: '3.499999999551'
                    }
                },
                {
                    token: 'TKN1',
                    liquidity: '1969308',
                    lowestRate: '1.500000000000',
                    highestRate: '1.750000000000',
                    marginalRate: '1.749211463527',
                    expected: {
                        liquidity: '1963308',
                        lowestRate: '1.499999999675',
                        highestRate: '1.749999999886',
                        marginalRate: '1.748423235212'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'TKN0',
                    liquidity: '401232',
                    lowestRate: '3.500000000000',
                    highestRate: '3.750000000000',
                    marginalRate: '3.750000000000',
                    expected: {
                        liquidity: '404733',
                        lowestRate: '3.499999999551',
                        highestRate: '3.749999999137',
                        marginalRate: '3.749999999137'
                    }
                },
                {
                    token: 'TKN1',
                    liquidity: '2222221',
                    lowestRate: '1.750000000000',
                    highestRate: '2',
                    marginalRate: '2',
                    expected: {
                        liquidity: '2215221',
                        lowestRate: '1.749999999886',
                        highestRate: '1.999999999373',
                        marginalRate: '1.999186302475'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'TKN0',
                    liquidity: '432096',
                    lowestRate: '3.750000000000',
                    highestRate: '4',
                    marginalRate: '4',
                    expected: {
                        liquidity: '432096',
                        lowestRate: '3.749999999137',
                        highestRate: '4',
                        marginalRate: '4'
                    }
                },
                {
                    token: 'TKN1',
                    liquidity: '2469135',
                    lowestRate: '2',
                    highestRate: '2.250000000000',
                    marginalRate: '2.250000000000',
                    expected: {
                        liquidity: '2469135',
                        lowestRate: '1.999999999373',
                        highestRate: '2.25',
                        marginalRate: '2.25'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'TKN0',
                    liquidity: '462960',
                    lowestRate: '4',
                    highestRate: '4.250000000000',
                    marginalRate: '4.250000000000',
                    expected: {
                        liquidity: '462960',
                        lowestRate: '4',
                        highestRate: '4.249999999049',
                        marginalRate: '4.249999999049'
                    }
                },
                {
                    token: 'TKN1',
                    liquidity: '2716048',
                    lowestRate: '2.250000000000',
                    highestRate: '2.500000000000',
                    marginalRate: '2.500000000000',
                    expected: {
                        liquidity: '2716048',
                        lowestRate: '2.25',
                        highestRate: '2.499999999523',
                        marginalRate: '2.499999999523'
                    }
                }
            ]
        },
        {
            orders: [
                {
                    token: 'TKN0',
                    liquidity: '493824',
                    lowestRate: '4.250000000000',
                    highestRate: '4.500000000000',
                    marginalRate: '4.500000000000',
                    expected: {
                        liquidity: '493824',
                        lowestRate: '4.249999999049',
                        highestRate: '4.499999999083',
                        marginalRate: '4.499999999083'
                    }
                },
                {
                    token: 'TKN1',
                    liquidity: '2962962',
                    lowestRate: '2.500000000000',
                    highestRate: '2.750000000000',
                    marginalRate: '2.750000000000',
                    expected: {
                        liquidity: '2962962',
                        lowestRate: '2.499999999523',
                        highestRate: '2.749999999352',
                        marginalRate: '2.749999999352'
                    }
                }
            ]
        }
    ],
    tradeActions: [
        {
            strategyId: '1',
            amount: '1000'
        },
        {
            strategyId: '2',
            amount: '2000'
        },
        {
            strategyId: '3',
            amount: '3000'
        },
        {
            strategyId: '4',
            amount: '4000'
        },
        {
            strategyId: '5',
            amount: '5000'
        },
        {
            strategyId: '6',
            amount: '6000'
        },
        {
            strategyId: '7',
            amount: '7000'
        }
    ],
    sourceAmount: '21175',
    targetAmount: '28000'
};
