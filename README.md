## Subnet Bridge and Fuji Bridge

* These contracts work with CLI to complete the end-to-end bridging experience. This is meant to experiment and is not
  meant for production.

### Fuji Bridge Contract

* This bridge contract allows users to deposit a contract specific ERC20 token on Fuji. The admin of the subnet contract
  will call the completeTransfer method to transfer native tokens of the subnet to the beneficiary.

### Subnet Bridge Contract

* This bridge contract allows users to deposit the native token on subnet. The admin of the Fuji bridge contract will
  call the completeTransfer method to transfer the ERC20 tokens to the beneficiary on Fuji.

### Testing

`forge test`
