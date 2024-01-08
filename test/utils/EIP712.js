class EIP712Signer {
    constructor({ signing_domain, signature_version, contract }) {
        this.signing_domain = signing_domain;
        this.signature_version = signature_version;
        this.contract = contract;
    }

    async signMessage(message, types, signer) {
        const domain = await this._signingDomain();
        // const signature = await signer._signTypedData(domain, types, message);
        const signature = await signer.signTypedData(domain, types, message);

        return {
            ...message,
            signature,
        };
    }

    async _signingDomain() {
        if (this._domain != void 0) {
            return this._domain;
        }

        this._domain = {
            name: this.signing_domain,
            version: this.signature_version,
            verifyingContract: this.contract.target,
            chainId: 31337,
        };

        return this._domain;
    }
}

module.exports = EIP712Signer;
