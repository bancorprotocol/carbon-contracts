import testData from '../carbon/trading/testData2.json';
import fs from 'fs';

/**
 * @dev helper function to convert a test data json's order values to carbon-encoded values
 * @returns
 */
const convertJson = (data: any) => {
    for (const key of Object.keys(data)) {
        const encodedStrategies = reformatStrategies(data[key].strategies);
        data[key].strategies = encodedStrategies;
        delete data[key].sourceSymbol;
        delete data[key].targetSymbol;
    }
    return data;
};

function reformatStrategies(strategies: any): any {
    const reformattedStrategies = [];

    for (const strategy of strategies) {
        const orders = [];
        const expectedOrders = [];
        for (const order of strategy.orders) {
            orders.push({
                y: order.y,
                z: order.z,
                A: order.A,
                B: order.B
            });
            if (order.expected) {
                expectedOrders.push({
                    y: order.expected.y,
                    z: order.expected.z,
                    A: order.expected.A,
                    B: order.expected.B
                });
            }
        }
        reformattedStrategies.push({
            orders,
            expectedOrders
        });
    }
    return reformattedStrategies;
}

const result = convertJson(testData);

fs.writeFileSync('./test/carbon/trading/testDataFormatted.json', JSON.stringify(result, null, 2));
