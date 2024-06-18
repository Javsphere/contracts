const delay = (ms) => new Promise((res) => setTimeout(res, ms));

const logDeploy = (contractName, address) => {
    console.info(`\x1b[32m${contractName}\x1b[0m:\t`, "\x1b[36m", address, "\x1b[0m");
};

module.exports = {
    delay,
    logDeploy,
};
