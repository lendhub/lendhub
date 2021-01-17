module.exports = {
  networks: {
    development: {
      protocol: 'http',
      host: 'localhost',
      port: 8545,
      gas: 9000000,
      gasLimit: 9000000,
      gasPrice: 1,
      networkId: '*',
    },
  },
};
